import Foundation

actor HomebrewFormulaClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIndex() async -> HomebrewFormulaIndex {
        guard let url = URL(string: "https://formulae.brew.sh/api/formula.json") else {
            return .empty
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .empty
            }
            guard data.count <= SecurityPolicy.homebrewIndexMaxBytes else {
                return .empty
            }
            return parseIndex(data)
        } catch {
            return .empty
        }
    }

    func parseIndex(_ data: Data) -> HomebrewFormulaIndex {
        guard data.count <= SecurityPolicy.homebrewIndexMaxBytes else {
            return .empty
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .empty
        }

        var byToken: [String: HomebrewFormulaEntry] = [:]

        for item in raw {
            guard let tokenRaw = (item["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !tokenRaw.isEmpty else {
                continue
            }
            let token = tokenRaw.lowercased()
            guard SecurityPolicy.isValidHomebrewToken(token) else { continue }

            let version = Version(stableVersion(from: item))
            let homepageURL = (item["homepage"] as? String)
                .flatMap(URL.init(string:))
                .flatMap { SecurityPolicy.sanitizeExternalURL($0) }
            let description = (item["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let entry = HomebrewFormulaEntry(
                token: token,
                version: version,
                homepageURL: homepageURL,
                description: description?.isEmpty == true ? nil : description
            )
            let key = token.lowercased()
            if let existing = byToken[key], existing.version > entry.version {
                continue
            }
            byToken[key] = entry
        }

        return HomebrewFormulaIndex(byToken: byToken)
    }

    func searchFormulae(
        query: String,
        in index: HomebrewFormulaIndex,
        excludingTokens: Set<String>,
        limit: Int = 24
    ) -> [HomebrewCaskDiscoveryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let queryLowercased = trimmedQuery.lowercased()
        let compactQuery = compactSearchText(queryLowercased)
        let excluded = Set(excludingTokens.map { $0.lowercased() })

        var matches: [(entry: HomebrewFormulaEntry, rank: Int)] = []
        matches.reserveCapacity(index.byToken.count)

        for entry in index.byToken.values {
            let tokenKey = entry.token.lowercased()
            guard !excluded.contains(tokenKey) else { continue }
            guard let rank = searchRank(for: entry, query: queryLowercased, compactQuery: compactQuery) else {
                continue
            }
            matches.append((entry, rank))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            let tokenComparison = lhs.entry.token.localizedCaseInsensitiveCompare(rhs.entry.token)
            if tokenComparison != .orderedSame {
                return tokenComparison == .orderedAscending
            }
            return lhs.entry.version > rhs.entry.version
        }

        return sorted.prefix(max(limit, 0)).map { matched in
            let entry = matched.entry
            return HomebrewCaskDiscoveryItem(
                kind: .formula,
                token: entry.token,
                displayName: entry.token.lowercased(),
                version: entry.version,
                homepageURL: SecurityPolicy.sanitizeExternalURL(
                    URL(string: "https://formulae.brew.sh/formula/\(entry.token)")
                ) ?? SecurityPolicy.sanitizeExternalURL(entry.homepageURL)
            )
        }
    }

    private func stableVersion(from item: [String: Any]) -> String {
        if let versions = item["versions"] as? [String: Any] {
            if let stable = versions["stable"] as? String {
                return stable
            }
            if let head = versions["head"] as? String {
                return head
            }
        }
        if let version = item["version"] as? String {
            return version
        }
        return ""
    }

    private func searchRank(
        for entry: HomebrewFormulaEntry,
        query: String,
        compactQuery: String
    ) -> Int? {
        let token = entry.token.lowercased()
        let compactToken = compactSearchText(token)
        let description = entry.description?.lowercased() ?? ""
        let compactDescription = compactSearchText(description)

        if token == query || (!compactQuery.isEmpty && compactToken == compactQuery) {
            return 0
        }
        if token.hasPrefix(query) || (!compactQuery.isEmpty && compactToken.hasPrefix(compactQuery)) {
            return 1
        }
        if description.hasPrefix(query)
            || (!compactQuery.isEmpty && compactDescription.hasPrefix(compactQuery)) {
            return 2
        }
        if token.contains(query)
            || description.contains(query)
            || (!compactQuery.isEmpty && compactToken.contains(compactQuery))
            || (!compactQuery.isEmpty && compactDescription.contains(compactQuery)) {
            return 3
        }

        return nil
    }

    private func compactSearchText(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
