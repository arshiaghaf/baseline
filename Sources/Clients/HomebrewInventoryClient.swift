import Foundation

actor HomebrewInventoryClient {
    private let parser = HomebrewInventoryParser()
    private let resolveBrewExecutableURL: @Sendable () -> URL?

    init(
        resolveBrewExecutableURL: @escaping @Sendable () -> URL? = {
            SecurityPolicy.resolvedBrewExecutableURL()
        }
    ) {
        self.resolveBrewExecutableURL = resolveBrewExecutableURL
    }

    func fetchInventory() async -> [HomebrewManagedItem] {
        async let formulaVersionsOutput = runBrewCommand(["list", "--formula", "--versions"])
        async let caskVersionsOutput = runBrewCommand(["list", "--cask", "--versions"])
        async let formulaOutdatedJSONOutput = runBrewCommand(["outdated", "--formula", "--json=v2"])
        async let caskOutdatedJSONOutput = runBrewCommand(["outdated", "--cask", "--greedy", "--json=v2"])

        let formulaResult = await formulaVersionsOutput
        let caskResult = await caskVersionsOutput
        let formulaOutdatedResult = await formulaOutdatedJSONOutput
        let caskOutdatedResult = await caskOutdatedJSONOutput

        let formulaOutput = formulaResult?.output ?? ""
        let caskOutput = caskResult?.output ?? ""
        let formulaOutdatedData = Data((formulaOutdatedResult?.output ?? "{}").utf8)
        let caskOutdatedData = Data((caskOutdatedResult?.output ?? "{}").utf8)

        return parser.buildInventory(
            formulaVersionsOutput: formulaOutput,
            caskVersionsOutput: caskOutput,
            formulaOutdatedJSONData: formulaOutdatedData,
            caskOutdatedJSONData: caskOutdatedData
        )
    }

    private func runBrewCommand(_ arguments: [String]) async -> (status: Int32, output: String)? {
        guard let brewExecutableURL = resolveBrewExecutableURL() else { return nil }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = brewExecutableURL
            process.arguments = arguments

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                continuation.resume(returning: (process.terminationStatus, output) as (Int32, String)?)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

struct HomebrewInventoryParser {
    private enum SharedDateParsers {
        static let lock = NSLock()
        nonisolated(unsafe) static let iso8601WithFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
            ISO8601DateFormatter()
        }()
        static let dayPrecision: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }

    private struct OutdatedMetadata {
        let latestVersion: Version
        let releaseDate: Date?
    }

    func buildInventory(
        formulaVersionsOutput: String,
        caskVersionsOutput: String,
        outdatedJSONData: Data
    ) -> [HomebrewManagedItem] {
        buildInventory(
            formulaVersionsOutput: formulaVersionsOutput,
            caskVersionsOutput: caskVersionsOutput,
            formulaOutdatedJSONData: outdatedJSONData,
            caskOutdatedJSONData: outdatedJSONData
        )
    }

    func buildInventory(
        formulaVersionsOutput: String,
        caskVersionsOutput: String,
        formulaOutdatedJSONData: Data,
        caskOutdatedJSONData: Data
    ) -> [HomebrewManagedItem] {
        let formulaInstalled = parseInstalledVersions(formulaVersionsOutput)
        let caskInstalled = parseInstalledVersions(caskVersionsOutput)
        var outdatedMetadata = parseOutdatedMetadata(from: formulaOutdatedJSONData)
        let caskOutdatedMetadata = parseOutdatedMetadata(from: caskOutdatedJSONData)
        outdatedMetadata.merge(caskOutdatedMetadata) { _, new in new }

        var items: [HomebrewManagedItem] = []
        items.reserveCapacity(formulaInstalled.count + caskInstalled.count)

        for (token, installedVersion) in formulaInstalled {
            let outdatedKey = key(kind: .formula, token: token)
            let metadata = outdatedMetadata[outdatedKey]
            items.append(
                HomebrewManagedItem(
                    token: token,
                    name: token,
                    kind: .formula,
                    installedVersion: installedVersion,
                    latestVersion: metadata?.latestVersion,
                    isOutdated: metadata != nil,
                    releaseDate: metadata?.releaseDate
                )
            )
        }

        for (token, installedVersion) in caskInstalled {
            let outdatedKey = key(kind: .cask, token: token)
            let metadata = outdatedMetadata[outdatedKey]
            items.append(
                HomebrewManagedItem(
                    token: token,
                    name: token,
                    kind: .cask,
                    installedVersion: installedVersion,
                    latestVersion: metadata?.latestVersion,
                    isOutdated: metadata != nil,
                    releaseDate: metadata?.releaseDate
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func parseInstalledVersions(_ output: String) -> [String: Version] {
        var installed: [String: Version] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }

            let token = parts[0].lowercased()
            let versions = parts
                .dropFirst()
                .map(Version.init)

            guard let latestInstalled = versions.max() else { continue }
            installed[token] = latestInstalled
        }

        return installed
    }

    func parseOutdatedVersions(from data: Data) -> [String: Version] {
        var versions: [String: Version] = [:]
        for (key, metadata) in parseOutdatedMetadata(from: data) {
            versions[key] = metadata.latestVersion
        }
        return versions
    }

    private func parseOutdatedMetadata(from data: Data) -> [String: OutdatedMetadata] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var outdated: [String: OutdatedMetadata] = [:]
        populateOutdatedMetadata(
            in: &outdated,
            array: root["formulae"] as? [Any],
            kind: .formula
        )
        populateOutdatedMetadata(
            in: &outdated,
            array: root["casks"] as? [Any],
            kind: .cask
        )

        return outdated
    }

    private func populateOutdatedMetadata(
        in outdated: inout [String: OutdatedMetadata],
        array: [Any]?,
        kind: HomebrewManagedItemKind
    ) {
        guard let array else { return }
        for case let item as [String: Any] in array {
            guard let rawName = item["name"] as? String else { continue }
            let token = rawName.lowercased()
            guard let versionRaw = currentVersion(from: item) else { continue }
            outdated[key(kind: kind, token: token)] = OutdatedMetadata(
                latestVersion: Version(versionRaw),
                releaseDate: releaseDate(from: item)
            )
        }
    }

    private func currentVersion(from item: [String: Any]) -> String? {
        if let value = item["current_version"] as? String {
            return value
        }
        if let value = item["currentVersion"] as? String {
            return value
        }
        if let versions = item["current_version"] as? [String], let first = versions.first {
            return first
        }
        if let versions = item["currentVersion"] as? [String], let first = versions.first {
            return first
        }
        return nil
    }

    private func key(kind: HomebrewManagedItemKind, token: String) -> String {
        "\(kind.rawValue):\(token.lowercased())"
    }

    private func releaseDate(from item: [String: Any]) -> Date? {
        let candidateKeys = [
            "release_date",
            "released_at",
            "published_at",
            "updated_at",
            "created_at",
            "date"
        ]

        for key in candidateKeys {
            guard let raw = item[key] else { continue }
            if let date = parseDate(raw) {
                return date
            }
        }

        return nil
    }

    private func parseDate(_ raw: Any) -> Date? {
        if let timestamp = raw as? Double {
            let date = Date(timeIntervalSince1970: timestamp)
            return isPlausibleReleaseDate(date) ? date : nil
        }
        if let timestamp = raw as? Int {
            let date = Date(timeIntervalSince1970: Double(timestamp))
            return isPlausibleReleaseDate(date) ? date : nil
        }
        guard let value = raw as? String else {
            return nil
        }

        if let date = parseISODate(value) {
            return isPlausibleReleaseDate(date) ? date : nil
        }

        if let date = parseDayPrecisionDate(value) {
            return isPlausibleReleaseDate(date) ? date : nil
        }
        return nil
    }

    private func isPlausibleReleaseDate(_ date: Date) -> Bool {
        // Ignore placeholder epochs (e.g., Unix 0 / DOS 1980 timestamps) that surface as 1979/1980 in UI.
        date >= minimumPlausibleReleaseDate
    }

    private func parseISODate(_ value: String) -> Date? {
        SharedDateParsers.lock.lock()
        defer { SharedDateParsers.lock.unlock() }
        return SharedDateParsers.iso8601WithFractional.date(from: value)
            ?? SharedDateParsers.iso8601.date(from: value)
    }

    private func parseDayPrecisionDate(_ value: String) -> Date? {
        SharedDateParsers.lock.lock()
        defer { SharedDateParsers.lock.unlock() }
        return SharedDateParsers.dayPrecision.date(from: value)
    }

    private var minimumPlausibleReleaseDate: Date {
        Date(timeIntervalSince1970: 946_684_800) // 2000-01-01T00:00:00Z
    }
}
