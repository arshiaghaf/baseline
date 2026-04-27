import Foundation

actor HomebrewCaskClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIndex() async -> HomebrewCaskIndex {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask.json") else {
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

    func lookupUpdate(
        bundleIdentifier: String?,
        appBundleName: String,
        localVersion: Version,
        in index: HomebrewCaskIndex
    ) -> HomebrewLookupResult? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           let entry = index.byBundleIdentifier[bundleIdentifier.lowercased()],
           entry.version > localVersion {
            let infoURL = URL(string: "https://formulae.brew.sh/cask/\(entry.token)")
            return HomebrewLookupResult(
                remoteVersion: entry.version,
                token: entry.token,
                homepageURL: SecurityPolicy.sanitizeExternalURL(infoURL)
                    ?? SecurityPolicy.sanitizeExternalURL(entry.homepageURL)
            )
        }

        guard let normalizedName = normalizeAppBundleName(appBundleName) else {
            return nil
        }
        guard var candidates = index.byAppBundleName[normalizedName] else {
            return nil
        }

        if let tokenHint = tokenHint(forAppBundleName: normalizedName) {
            let exact = candidates.filter { $0.token.lowercased() == tokenHint.lowercased() }
            if let exactBest = pickPreferredEntry(from: exact, localVersion: localVersion) {
                let infoURL = URL(string: "https://formulae.brew.sh/cask/\(exactBest.token)")
                return HomebrewLookupResult(
                    remoteVersion: exactBest.version,
                    token: exactBest.token,
                    homepageURL: SecurityPolicy.sanitizeExternalURL(infoURL)
                        ?? SecurityPolicy.sanitizeExternalURL(exactBest.homepageURL)
                )
            }

            let related = candidates.filter { isToken($0.token, relatedTo: tokenHint) }
            if !related.isEmpty {
                candidates = related
            }
        }

        guard let entry = pickPreferredEntry(from: candidates, localVersion: localVersion) else {
            return nil
        }

        let infoURL = URL(string: "https://formulae.brew.sh/cask/\(entry.token)")
        return HomebrewLookupResult(
            remoteVersion: entry.version,
            token: entry.token,
            homepageURL: SecurityPolicy.sanitizeExternalURL(infoURL)
                ?? SecurityPolicy.sanitizeExternalURL(entry.homepageURL)
        )
    }

    func searchCasks(
        query: String,
        in index: HomebrewCaskIndex,
        excludingTokens: Set<String>,
        limit: Int = 24
    ) -> [HomebrewCaskDiscoveryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let queryLowercased = trimmedQuery.lowercased()
        let compactQuery = compactSearchText(queryLowercased)
        let excluded = Set(excludingTokens.map { $0.lowercased() })

        let allEntries = deduplicatedEntries(from: index)
        var matches: [(entry: HomebrewCaskEntry, rank: Int)] = []
        matches.reserveCapacity(allEntries.count)

        for entry in allEntries {
            let tokenKey = entry.token.lowercased()
            guard !excluded.contains(tokenKey) else { continue }
            guard let rank = searchRank(
                for: entry,
                query: queryLowercased,
                compactQuery: compactQuery
            ) else {
                continue
            }
            matches.append((entry, rank))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            let lhsName = displayName(for: lhs.entry)
            let rhsName = displayName(for: rhs.entry)
            let nameComparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
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
                kind: .cask,
                token: entry.token,
                displayName: displayName(for: entry),
                version: entry.version,
                homepageURL: SecurityPolicy.sanitizeExternalURL(
                    URL(string: "https://formulae.brew.sh/cask/\(entry.token)")
                ) ?? SecurityPolicy.sanitizeExternalURL(entry.homepageURL)
            )
        }
    }

    func parseIndex(_ data: Data) -> HomebrewCaskIndex {
        guard data.count <= SecurityPolicy.homebrewIndexMaxBytes else {
            return .empty
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .empty
        }

        var byBundleIdentifier: [String: HomebrewCaskEntry] = [:]
        var byAppBundleName: [String: [HomebrewCaskEntry]] = [:]

        for item in raw {
            guard let tokenRaw = item["token"] as? String else { continue }
            let token = tokenRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard SecurityPolicy.isValidHomebrewToken(token) else { continue }
            let version = Version(comparableVersion(from: item["version"] as? String))
            let homepageURL = (item["homepage"] as? String)
                .flatMap(URL.init(string:))
                .flatMap { SecurityPolicy.sanitizeExternalURL($0) }
            let bundleIdentifiers = extractBundleIdentifiers(from: item)
            let appBundleNames = extractAppBundleNames(from: item)

            if bundleIdentifiers.isEmpty && appBundleNames.isEmpty {
                continue
            }

            let entry = HomebrewCaskEntry(
                token: token,
                version: version,
                homepageURL: homepageURL,
                bundleIdentifiers: bundleIdentifiers,
                appBundleNames: appBundleNames
            )

            for bundleIdentifier in bundleIdentifiers {
                let key = bundleIdentifier.lowercased()
                if let existing = byBundleIdentifier[key], existing.version > entry.version {
                    continue
                }
                byBundleIdentifier[key] = entry
            }

            for appBundleName in appBundleNames {
                let key = appBundleName.lowercased()
                byAppBundleName[key, default: []].append(entry)
            }
        }

        for (key, entries) in byAppBundleName {
            var dedupedByToken: [String: HomebrewCaskEntry] = [:]
            for entry in entries {
                if let existing = dedupedByToken[entry.token], existing.version > entry.version {
                    continue
                }
                dedupedByToken[entry.token] = entry
            }
            byAppBundleName[key] = dedupedByToken.values.sorted { lhs, rhs in
                compareEntries(lhs, rhs)
            }
        }

        return HomebrewCaskIndex(
            byBundleIdentifier: byBundleIdentifier,
            byAppBundleName: byAppBundleName
        )
    }

    private func extractBundleIdentifiers(from object: Any) -> [String] {
        var identifiers: Set<String> = []
        collectBundleIdentifiers(from: object, into: &identifiers)
        return identifiers.sorted()
    }

    private func deduplicatedEntries(from index: HomebrewCaskIndex) -> [HomebrewCaskEntry] {
        var entriesByToken: [String: HomebrewCaskEntry] = [:]
        let allEntries = index.byBundleIdentifier.values + index.byAppBundleName.values.flatMap { $0 }

        for entry in allEntries {
            let key = entry.token.lowercased()
            if let existing = entriesByToken[key], existing.version > entry.version {
                continue
            }
            entriesByToken[key] = entry
        }

        return Array(entriesByToken.values)
    }

    private func collectBundleIdentifiers(from object: Any, into identifiers: inout Set<String>) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let keyLowercased = key.lowercased()
                if keyLowercased.contains("bundle_identifier")
                    || keyLowercased.contains("bundleidentifier")
                    || keyLowercased.contains("bundle-id")
                    || keyLowercased.contains("bundleid") {
                    if let value = value as? String {
                        identifiers.insert(value)
                    } else if let values = value as? [String] {
                        values.forEach { identifiers.insert($0) }
                    }
                }
                collectBundleIdentifiers(from: value, into: &identifiers)
            }
            return
        }

        if let array = object as? [Any] {
            array.forEach { collectBundleIdentifiers(from: $0, into: &identifiers) }
        }
    }

    private func extractAppBundleNames(from object: Any) -> [String] {
        var appBundleNames: Set<String> = []
        collectAppBundleNames(from: object, into: &appBundleNames)
        return appBundleNames.sorted()
    }

    private func collectAppBundleNames(from object: Any, into appBundleNames: inout Set<String>) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if key.lowercased() == "app" {
                    if let name = value as? String, let normalized = normalizeAppBundleName(name) {
                        appBundleNames.insert(normalized)
                    } else if let names = value as? [String] {
                        for name in names {
                            guard let normalized = normalizeAppBundleName(name) else { continue }
                            appBundleNames.insert(normalized)
                        }
                    } else if let values = value as? [Any] {
                        for value in values {
                            if let name = value as? String, let normalized = normalizeAppBundleName(name) {
                                appBundleNames.insert(normalized)
                            } else if let dict = value as? [String: Any],
                                      let target = dict["target"] as? String,
                                      let normalized = normalizeAppBundleName(target) {
                                appBundleNames.insert(normalized)
                            }
                        }
                    }
                }
                collectAppBundleNames(from: value, into: &appBundleNames)
            }
            return
        }

        if let array = object as? [Any] {
            array.forEach { collectAppBundleNames(from: $0, into: &appBundleNames) }
        }
    }

    private func comparableVersion(from homebrewVersion: String?) -> String {
        let raw = (homebrewVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSegment = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return raw
        }
        return String(firstSegment)
    }

    private func searchRank(
        for entry: HomebrewCaskEntry,
        query: String,
        compactQuery: String
    ) -> Int? {
        let token = entry.token.lowercased()
        let compactToken = compactSearchText(token)
        let appNames = searchableAppNames(for: entry)
        let compactAppNames = appNames.map(compactSearchText)

        if token == query || (!compactQuery.isEmpty && compactToken == compactQuery) {
            return 0
        }

        if token.hasPrefix(query) || (!compactQuery.isEmpty && compactToken.hasPrefix(compactQuery)) {
            return 1
        }

        if appNames.contains(where: { $0.hasPrefix(query) })
            || (!compactQuery.isEmpty && compactAppNames.contains(where: { $0.hasPrefix(compactQuery) })) {
            return 2
        }

        if token.contains(query)
            || appNames.contains(where: { $0.contains(query) })
            || (!compactQuery.isEmpty && compactToken.contains(compactQuery))
            || (!compactQuery.isEmpty && compactAppNames.contains(where: { $0.contains(compactQuery) })) {
            return 3
        }

        return nil
    }

    private func searchableAppNames(for entry: HomebrewCaskEntry) -> [String] {
        entry.appBundleNames
            .map { $0.replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive]) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func displayName(for entry: HomebrewCaskEntry) -> String {
        if let appName = searchableAppNames(for: entry).first {
            return appName
        }
        return entry.token.lowercased()
    }

    private func compactSearchText(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func normalizeAppBundleName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let filename = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !filename.isEmpty else { return nil }

        if filename.lowercased().hasSuffix(".app") {
            return filename.lowercased()
        }
        return "\(filename.lowercased()).app"
    }

    private func tokenHint(forAppBundleName appBundleName: String) -> String? {
        let baseName = appBundleName.replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive])
        guard !baseName.isEmpty else { return nil }

        let parts = baseName
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let token = parts.joined(separator: "-")
        return token.isEmpty ? nil : token
    }

    private func isToken(_ token: String, relatedTo hint: String) -> Bool {
        let tokenParts = canonicalTokenParts(from: token)
        let hintParts = canonicalTokenParts(from: hint)
        guard !tokenParts.isEmpty, !hintParts.isEmpty else { return false }

        return tokenParts == hintParts || tokenParts.starts(with: hintParts)
    }

    private func canonicalTokenParts(from token: String) -> [String] {
        token
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func isChannelToken(_ token: String) -> Bool {
        let channelKeywords: Set<String> = [
            "alpha", "beta", "canary", "daily", "dev", "edge", "insider", "nightly", "preview", "rc"
        ]
        let parts = token
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "@" || $0 == "." || $0 == "_" })
            .map(String.init)
        return parts.contains(where: { channelKeywords.contains($0) })
    }

    private func compareEntries(_ lhs: HomebrewCaskEntry, _ rhs: HomebrewCaskEntry) -> Bool {
        if lhs.version != rhs.version {
            return lhs.version < rhs.version
        }
        return lhs.token.localizedCaseInsensitiveCompare(rhs.token) == .orderedAscending
    }

    private func pickPreferredEntry(
        from candidates: [HomebrewCaskEntry],
        localVersion: Version
    ) -> HomebrewCaskEntry? {
        let newer = candidates.filter { $0.version > localVersion }
        guard !newer.isEmpty else { return nil }

        let stable = newer.filter { !isChannelToken($0.token) }
        let preferred = stable.isEmpty ? newer : stable
        return preferred.max(by: compareEntries)
    }
}
