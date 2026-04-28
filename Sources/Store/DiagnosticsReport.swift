import Foundation

struct BaselineDiagnosticsReport: Sendable {
    let generatedAt: Date
    let lastRefreshDate: Date?
    let isRefreshing: Bool
    let appCount: Int
    let availableAppCount: Int
    let installedAppCount: Int
    let ignoredAppCount: Int
    let recentlyUpdatedAppCount: Int
    let homebrewItemCount: Int
    let homebrewOutdatedCount: Int
    let homebrewInstalledCount: Int
    let homebrewIgnoredCount: Int
    let homebrewRecentlyUpdatedCount: Int
    let updateSourceCounts: [UpdateSource: Int]
    let scanDirectories: [URL]
    let additionalDirectoryCount: Int
    let autoRefreshEnabled: Bool
    let refreshIntervalMinutes: Int
    let useMasForAppStoreUpdates: Bool
    let isMasInstalled: Bool
    let isHomebrewInstalled: Bool
    let lastRefreshMessage: String?

    func render() -> String {
        var lines: [String] = []
        lines.append("Baseline Diagnostics")
        lines.append("Generated: \(Self.format(generatedAt))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("App version: \(Self.bundleVersionDescription())")
        lines.append("")
        lines.append("Refresh")
        lines.append("- Last refresh: \(lastRefreshDate.map(Self.format) ?? "Never")")
        lines.append("- Refreshing: \(Self.yesNo(isRefreshing))")
        lines.append("- Auto refresh: \(Self.yesNo(autoRefreshEnabled))")
        lines.append("- Refresh interval: \(refreshIntervalMinutes) minutes")
        if let safeLastRefreshMessage {
            lines.append("- Last message: \(safeLastRefreshMessage)")
        }
        lines.append("")
        lines.append("Apps")
        lines.append("- Scanned apps: \(appCount)")
        lines.append("- Available updates: \(availableAppCount)")
        lines.append("- Installed/current: \(installedAppCount)")
        lines.append("- Recently updated: \(recentlyUpdatedAppCount)")
        lines.append("- Ignored: \(ignoredAppCount)")
        lines.append("- Sources: \(sourceCountsDescription)")
        lines.append("")
        lines.append("Homebrew")
        lines.append("- Items: \(homebrewItemCount)")
        lines.append("- Outdated: \(homebrewOutdatedCount)")
        lines.append("- Installed/current: \(homebrewInstalledCount)")
        lines.append("- Recently updated: \(homebrewRecentlyUpdatedCount)")
        lines.append("- Ignored: \(homebrewIgnoredCount)")
        lines.append("- Homebrew available for helper install: \(Self.yesNo(isHomebrewInstalled))")
        lines.append("")
        lines.append("Optional Tools")
        lines.append("- mas installed: \(Self.yesNo(isMasInstalled))")
        lines.append("- Use mas for App Store updates: \(Self.yesNo(useMasForAppStoreUpdates))")
        lines.append("")
        lines.append("Scan Directories")
        lines.append("- Custom directories: \(additionalDirectoryCount)")
        for directory in scanDirectories {
            lines.append("- \(directory.path)")
        }
        return lines.joined(separator: "\n")
    }

    private var sourceCountsDescription: String {
        UpdateSource.allCases
            .compactMap { source in
                let count = updateSourceCounts[source] ?? 0
                guard count > 0 else { return nil }
                return "\(source.displayName): \(count)"
            }
            .joined(separator: ", ")
            .nilIfEmpty ?? "None"
    }

    private var safeLastRefreshMessage: String? {
        lastRefreshMessage?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func bundleVersionDescription() -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "Unknown"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
