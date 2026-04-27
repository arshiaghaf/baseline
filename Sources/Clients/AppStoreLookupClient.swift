import Foundation

actor AppStoreLookupClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(bundleIdentifier: String, localVersion: Version) async -> AppStoreLookupResult? {
        switch await lookupOutcome(bundleIdentifier: bundleIdentifier, localVersion: localVersion) {
        case .completed(let value):
            return value
        case .transientFailure:
            return nil
        }
    }

    func lookupOutcome(bundleIdentifier: String, localVersion: Version) async -> LookupOutcome<AppStoreLookupResult> {
        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
            return .transientFailure
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier)
        ]
        // Prefer macOS records from the lookup API to avoid iOS-only false positives.
        queryItems.append(URLQueryItem(name: "entity", value: "macSoftware"))
        components.queryItems = queryItems

        guard let url = components.url else { return .transientFailure }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .transientFailure
            }

            do {
                return .completed(value: try parseLookupResponse(data, localVersion: localVersion))
            } catch {
                return .transientFailure
            }
        } catch {
            return .transientFailure
        }
    }

    func parseLookupResponse(_ data: Data, localVersion: Version) throws -> AppStoreLookupResult? {
        guard data.count <= SecurityPolicy.appStoreLookupMaxBytes else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(LookupResponse.self, from: data)
        guard let selected = selectMacCandidate(from: response.results) else { return nil }

        let remoteVersion = Version(selected.version)
        guard remoteVersion > localVersion else { return nil }

        return AppStoreLookupResult(
            remoteVersion: remoteVersion,
            updateURL: SecurityPolicy.sanitizeExternalURL(selected.trackViewUrl),
            releaseNotesSummary: selected.releaseNotes,
            releaseDate: selected.currentVersionReleaseDate,
            appStoreItemID: selected.trackId
        )
    }

    private func selectMacCandidate(from results: [LookupEntry]) -> LookupEntry? {
        // The API can return iOS and macOS entries with the same bundle identifier.
        // Only trust explicit macOS entries.
        if let macEntry = results.first(where: { $0.kind == "mac-software" }) {
            return macEntry
        }

        // Backward-compatible fallback for fixtures or sparse responses missing `kind`.
        if results.count == 1, results[0].kind == nil {
            return results[0]
        }

        return nil
    }
}

private struct LookupResponse: Decodable {
    let resultCount: Int
    let results: [LookupEntry]
}

private struct LookupEntry: Decodable {
    let kind: String?
    let version: String?
    let trackViewUrl: URL?
    let trackId: Int?
    let releaseNotes: String?
    let currentVersionReleaseDate: Date?
}
