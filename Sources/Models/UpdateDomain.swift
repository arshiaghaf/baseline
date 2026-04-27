import Foundation

enum UpdateSource: String, Codable, CaseIterable, Sendable {
    case appStore
    case sparkle
    case homebrew
    case web
    case unknown

    var displayName: String {
        switch self {
        case .appStore: return "App Store"
        case .sparkle: return "Sparkle"
        case .homebrew: return "Homebrew"
        case .web: return "Web"
        case .unknown: return "Unknown"
        }
    }
}

enum SupportLevel: String, Codable, CaseIterable, Sendable {
    case supported
    case limited
    case unsupported

    var displayName: String {
        switch self {
        case .supported: return "Supported"
        case .limited: return "Limited"
        case .unsupported: return "Unsupported"
        }
    }
}

struct Version: Codable, Hashable, Sendable, Comparable {
    let raw: String
    private let components: [Int]

    init(_ raw: String?) {
        self.raw = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = self.raw.replacingOccurrences(
            of: "[^0-9]+",
            with: ".",
            options: .regularExpression
        )
        self.components = sanitized
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    var isEmpty: Bool {
        raw.isEmpty
    }

    private var normalizedComponents: [Int] {
        var values = components
        while values.last == 0 {
            values.removeLast()
        }
        return values
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let lhsComponents = lhs.normalizedComponents
        let rhsComponents = rhs.normalizedComponents
        let count = max(lhsComponents.count, rhsComponents.count)
        for index in 0..<count {
            let left = lhsComponents[safe: index] ?? 0
            let right = rhsComponents[safe: index] ?? 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: Version, rhs: Version) -> Bool {
        lhs.normalizedComponents == rhs.normalizedComponents
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedComponents)
    }
}

extension Collection {
    fileprivate subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct AppRecord: Codable, Hashable, Identifiable, Sendable {
    let bundleURL: URL
    let displayName: String
    let bundleIdentifier: String?
    let localVersion: Version
    let sourceHint: UpdateSource
    let sparkleFeedURL: URL?

    var id: String {
        bundleURL.path
    }
}

struct AppStoreLookupResult: Codable, Hashable, Sendable {
    let remoteVersion: Version
    let updateURL: URL?
    let releaseNotesSummary: String?
    let releaseDate: Date?
    let appStoreItemID: Int?

    init(
        remoteVersion: Version,
        updateURL: URL?,
        releaseNotesSummary: String?,
        releaseDate: Date?,
        appStoreItemID: Int? = nil
    ) {
        self.remoteVersion = remoteVersion
        self.updateURL = updateURL
        self.releaseNotesSummary = releaseNotesSummary
        self.releaseDate = releaseDate
        self.appStoreItemID = appStoreItemID
    }
}

struct SparkleLookupResult: Codable, Hashable, Sendable {
    let remoteVersion: Version
    let updateURL: URL?
    let releaseNotesURL: URL?
    let releaseDate: Date?
}

struct HomebrewLookupResult: Codable, Hashable, Sendable {
    let remoteVersion: Version
    let token: String
    let homepageURL: URL?
}

struct HomebrewCaskEntry: Codable, Hashable, Sendable {
    let token: String
    let version: Version
    let homepageURL: URL?
    let bundleIdentifiers: [String]
    let appBundleNames: [String]
}

struct HomebrewCaskDiscoveryItem: Codable, Hashable, Identifiable, Sendable {
    let kind: HomebrewManagedItemKind
    let token: String
    let displayName: String
    let version: Version
    let homepageURL: URL?

    var id: String {
        "\(kind.rawValue):\(token.lowercased())"
    }
}

struct HomebrewCaskIndex: Codable, Hashable, Sendable {
    var byBundleIdentifier: [String: HomebrewCaskEntry]
    var byAppBundleName: [String: [HomebrewCaskEntry]]

    static let empty = HomebrewCaskIndex(
        byBundleIdentifier: [:],
        byAppBundleName: [:]
    )
}

struct HomebrewFormulaEntry: Codable, Hashable, Sendable {
    let token: String
    let version: Version
    let homepageURL: URL?
    let description: String?
}

struct HomebrewFormulaIndex: Codable, Hashable, Sendable {
    var byToken: [String: HomebrewFormulaEntry]

    static let empty = HomebrewFormulaIndex(byToken: [:])
}

struct UpdateRecord: Codable, Hashable, Identifiable, Sendable {
    let appID: String
    let source: UpdateSource
    let supportLevel: SupportLevel
    let localVersion: Version
    let remoteVersion: Version
    let updateURL: URL?
    let appStoreItemID: Int?
    let homebrewToken: String?
    let releaseNotesURL: URL?
    let releaseNotesSummary: String?
    let releaseDate: Date?
    let checkedAt: Date

    var id: String {
        appID
    }

    init(
        appID: String,
        source: UpdateSource,
        supportLevel: SupportLevel,
        localVersion: Version,
        remoteVersion: Version,
        updateURL: URL?,
        appStoreItemID: Int? = nil,
        homebrewToken: String?,
        releaseNotesURL: URL?,
        releaseNotesSummary: String?,
        releaseDate: Date?,
        checkedAt: Date
    ) {
        self.appID = appID
        self.source = source
        self.supportLevel = supportLevel
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.updateURL = updateURL
        self.appStoreItemID = appStoreItemID
        self.homebrewToken = homebrewToken
        self.releaseNotesURL = releaseNotesURL
        self.releaseNotesSummary = releaseNotesSummary
        self.releaseDate = releaseDate
        self.checkedAt = checkedAt
    }
}

struct RecentlyUpdatedRecord: Codable, Hashable, Identifiable, Sendable {
    let appID: String
    let displayName: String
    let fromVersion: Version
    let toVersion: Version
    let updatedAt: Date

    var id: String {
        appID
    }
}

struct HomebrewRecentlyUpdatedRecord: Codable, Hashable, Identifiable, Sendable {
    let itemID: String
    let token: String
    let kind: HomebrewManagedItemKind
    let displayName: String
    let fromVersion: Version
    let toVersion: Version
    let updatedAt: Date

    var id: String {
        itemID
    }
}

enum MenuTab: String, Codable, CaseIterable, Sendable {
    case apps
    case homebrew

    var displayName: String {
        switch self {
        case .apps: return "Apps"
        case .homebrew: return "Homebrew"
        }
    }
}

enum HomebrewManagedItemKind: String, Codable, CaseIterable, Sendable {
    case formula
    case cask

    var displayName: String {
        switch self {
        case .formula: return "Formula"
        case .cask: return "Cask"
        }
    }
}

struct HomebrewManagedItem: Codable, Hashable, Identifiable, Sendable {
    let token: String
    let name: String
    let kind: HomebrewManagedItemKind
    let installedVersion: Version
    let latestVersion: Version?
    let isOutdated: Bool
    let releaseDate: Date?

    init(
        token: String,
        name: String,
        kind: HomebrewManagedItemKind,
        installedVersion: Version,
        latestVersion: Version?,
        isOutdated: Bool,
        releaseDate: Date? = nil
    ) {
        self.token = token
        self.name = name
        self.kind = kind
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.releaseDate = releaseDate
    }

    var id: String {
        "\(kind.rawValue):\(token.lowercased())"
    }
}

struct PersistedSnapshot: Codable, Sendable {
    var apps: [AppRecord]
    var updates: [UpdateRecord]
    var recentlyUpdated: [RecentlyUpdatedRecord]
    var homebrewItems: [HomebrewManagedItem]
    var homebrewRecentlyUpdated: [HomebrewRecentlyUpdatedRecord]
    var ignoredIDs: [String]
    var ignoredHomebrewItemIDs: [String]
    var additionalDirectories: [URL]
    var selectedTab: MenuTab
    var showInstalledAppsSection: Bool
    var showRecentlyUpdatedAppsSection: Bool
    var showIgnoredAppsSection: Bool
    var showRecentlyUpdatedHomebrewSection: Bool
    var showInstalledHomebrewSection: Bool
    var showIgnoredHomebrewSection: Bool
    var autoRefreshEnabled: Bool
    var refreshIntervalMinutes: Int
    var useMasForAppStoreUpdates: Bool
    var lastRefreshDate: Date?

    init(
        apps: [AppRecord],
        updates: [UpdateRecord],
        recentlyUpdated: [RecentlyUpdatedRecord] = [],
        homebrewItems: [HomebrewManagedItem] = [],
        homebrewRecentlyUpdated: [HomebrewRecentlyUpdatedRecord] = [],
        ignoredIDs: [String],
        ignoredHomebrewItemIDs: [String] = [],
        additionalDirectories: [URL],
        selectedTab: MenuTab,
        showInstalledAppsSection: Bool = true,
        showRecentlyUpdatedAppsSection: Bool = true,
        showIgnoredAppsSection: Bool = true,
        showRecentlyUpdatedHomebrewSection: Bool = true,
        showInstalledHomebrewSection: Bool = true,
        showIgnoredHomebrewSection: Bool = true,
        autoRefreshEnabled: Bool = true,
        refreshIntervalMinutes: Int,
        useMasForAppStoreUpdates: Bool = true,
        lastRefreshDate: Date?
    ) {
        self.apps = apps
        self.updates = updates
        self.recentlyUpdated = recentlyUpdated
        self.homebrewItems = homebrewItems
        self.homebrewRecentlyUpdated = homebrewRecentlyUpdated
        self.ignoredIDs = ignoredIDs
        self.ignoredHomebrewItemIDs = ignoredHomebrewItemIDs
        self.additionalDirectories = additionalDirectories
        self.selectedTab = selectedTab
        self.showInstalledAppsSection = showInstalledAppsSection
        self.showRecentlyUpdatedAppsSection = showRecentlyUpdatedAppsSection
        self.showIgnoredAppsSection = showIgnoredAppsSection
        self.showRecentlyUpdatedHomebrewSection = showRecentlyUpdatedHomebrewSection
        self.showInstalledHomebrewSection = showInstalledHomebrewSection
        self.showIgnoredHomebrewSection = showIgnoredHomebrewSection
        self.autoRefreshEnabled = autoRefreshEnabled
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.useMasForAppStoreUpdates = useMasForAppStoreUpdates
        self.lastRefreshDate = lastRefreshDate
    }

    private enum CodingKeys: String, CodingKey {
        case apps
        case updates
        case recentlyUpdated
        case homebrewItems
        case homebrewRecentlyUpdated
        case ignoredIDs
        case ignoredHomebrewItemIDs
        case additionalDirectories
        case selectedTab
        case showInstalledAppsSection
        case showRecentlyUpdatedAppsSection
        case showIgnoredAppsSection
        case showRecentlyUpdatedHomebrewSection
        case showInstalledHomebrewSection
        case showIgnoredHomebrewSection
        case autoRefreshEnabled
        case refreshIntervalMinutes
        case useMasForAppStoreUpdates
        case lastRefreshDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.apps = try container.decode([AppRecord].self, forKey: .apps)
        self.updates = try container.decode([UpdateRecord].self, forKey: .updates)
        self.recentlyUpdated = try container.decodeIfPresent([RecentlyUpdatedRecord].self, forKey: .recentlyUpdated) ?? []
        self.homebrewItems = try container.decodeIfPresent([HomebrewManagedItem].self, forKey: .homebrewItems) ?? []
        self.homebrewRecentlyUpdated = try container.decodeIfPresent([HomebrewRecentlyUpdatedRecord].self, forKey: .homebrewRecentlyUpdated) ?? []
        self.ignoredIDs = try container.decode([String].self, forKey: .ignoredIDs)
        self.ignoredHomebrewItemIDs = try container.decodeIfPresent([String].self, forKey: .ignoredHomebrewItemIDs) ?? []
        self.additionalDirectories = try container.decode([URL].self, forKey: .additionalDirectories)
        self.selectedTab = try container.decodeIfPresent(MenuTab.self, forKey: .selectedTab) ?? .apps
        self.showInstalledAppsSection = try container.decodeIfPresent(Bool.self, forKey: .showInstalledAppsSection) ?? true
        self.showRecentlyUpdatedAppsSection = try container.decodeIfPresent(Bool.self, forKey: .showRecentlyUpdatedAppsSection) ?? true
        self.showIgnoredAppsSection = try container.decodeIfPresent(Bool.self, forKey: .showIgnoredAppsSection) ?? true
        self.showRecentlyUpdatedHomebrewSection = try container.decodeIfPresent(Bool.self, forKey: .showRecentlyUpdatedHomebrewSection) ?? true
        self.showInstalledHomebrewSection = try container.decodeIfPresent(Bool.self, forKey: .showInstalledHomebrewSection) ?? true
        self.showIgnoredHomebrewSection = try container.decodeIfPresent(Bool.self, forKey: .showIgnoredHomebrewSection) ?? true
        self.autoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? true
        self.refreshIntervalMinutes = try container.decode(Int.self, forKey: .refreshIntervalMinutes)
        self.useMasForAppStoreUpdates = try container.decodeIfPresent(Bool.self, forKey: .useMasForAppStoreUpdates) ?? true
        self.lastRefreshDate = try container.decodeIfPresent(Date.self, forKey: .lastRefreshDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apps, forKey: .apps)
        try container.encode(updates, forKey: .updates)
        try container.encode(recentlyUpdated, forKey: .recentlyUpdated)
        try container.encode(homebrewItems, forKey: .homebrewItems)
        try container.encode(homebrewRecentlyUpdated, forKey: .homebrewRecentlyUpdated)
        try container.encode(ignoredIDs, forKey: .ignoredIDs)
        try container.encode(ignoredHomebrewItemIDs, forKey: .ignoredHomebrewItemIDs)
        try container.encode(additionalDirectories, forKey: .additionalDirectories)
        try container.encode(selectedTab, forKey: .selectedTab)
        try container.encode(showInstalledAppsSection, forKey: .showInstalledAppsSection)
        try container.encode(showRecentlyUpdatedAppsSection, forKey: .showRecentlyUpdatedAppsSection)
        try container.encode(showIgnoredAppsSection, forKey: .showIgnoredAppsSection)
        try container.encode(showRecentlyUpdatedHomebrewSection, forKey: .showRecentlyUpdatedHomebrewSection)
        try container.encode(showInstalledHomebrewSection, forKey: .showInstalledHomebrewSection)
        try container.encode(showIgnoredHomebrewSection, forKey: .showIgnoredHomebrewSection)
        try container.encode(autoRefreshEnabled, forKey: .autoRefreshEnabled)
        try container.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
        try container.encode(useMasForAppStoreUpdates, forKey: .useMasForAppStoreUpdates)
        try container.encodeIfPresent(lastRefreshDate, forKey: .lastRefreshDate)
    }
}

enum PersistenceKeys {
    static let suiteName = "com.arshia.baseline.store"
    static let snapshot = "snapshot"
    static let recentlyUpdatedRecords = "recentlyUpdatedRecords"
    static let homebrewRecentlyUpdatedRecords = "homebrewRecentlyUpdatedRecords"
}
