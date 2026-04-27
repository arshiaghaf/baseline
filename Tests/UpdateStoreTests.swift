import Foundation
import XCTest
@testable import Baseline

@MainActor
final class UpdateStoreTests: XCTestCase {
    final class PhaseBox: @unchecked Sendable {
        var value: Int = 0
    }

    final class DateBox: @unchecked Sendable {
        var value: Date

        init(_ value: Date) {
            self.value = value
        }
    }

    struct VisibleSectionSnapshot: Equatable {
        let availableAppIDs: [String]
        let installedAppIDs: [String]
        let recentlyUpdatedAppIDs: [String]
        let ignoredAppIDs: [String]
        let displayedAvailableAppIDs: [String]
        let displayedInstalledAppIDs: [String]
        let displayedRecentlyUpdatedAppIDs: [String]
        let displayedIgnoredAppIDs: [String]
        let homebrewOutdatedItemIDs: [String]
        let homebrewInstalledItemIDs: [String]
        let homebrewRecentlyUpdatedItemIDs: [String]
        let homebrewIgnoredItemIDs: [String]
        let displayedHomebrewOutdatedItemIDs: [String]
        let displayedHomebrewInstalledItemIDs: [String]
        let displayedHomebrewRecentlyUpdatedItemIDs: [String]
        let displayedHomebrewIgnoredItemIDs: [String]
    }

    actor HomebrewCallsBox {
        private var calls: [(HomebrewManagedItemKind, String)] = []

        func append(_ kind: HomebrewManagedItemKind, _ token: String) {
            calls.append((kind, token))
        }

        func snapshot() -> [(HomebrewManagedItemKind, String)] {
            calls
        }
    }

    actor HomebrewUninstallCallsBox {
        private var tokens: [String] = []

        func append(_ token: String) {
            tokens.append(token)
        }

        func snapshot() -> [String] {
            tokens
        }
    }

    actor HomebrewUpgradeCallsBox {
        private var tokens: [String] = []

        func append(_ token: String) {
            tokens.append(token)
        }

        func snapshot() -> [String] {
            tokens
        }
    }

    final class HomebrewRunBox: @unchecked Sendable {
        var runCount: Int = 0
    }

    final class URLCallsBox: @unchecked Sendable {
        private(set) var urls: [URL] = []

        func append(_ url: URL) {
            urls.append(url)
        }

        func snapshot() -> [URL] {
            urls
        }
    }

    actor AppStoreUpgradeCallsBox {
        private var itemIDs: [Int] = []

        func append(_ itemID: Int) {
            itemIDs.append(itemID)
        }

        func snapshot() -> [Int] {
            itemIDs
        }
    }

    actor CounterBox {
        private var count: Int = 0

        func increment() {
            count += 1
        }

        func snapshot() -> Int {
            count
        }
    }

    struct RefreshTimelineSnapshot {
        let scanFinishedAt: Date?
        let homebrewIndexStartedAt: Date?
        let homebrewFormulaIndexStartedAt: Date?
        let homebrewInventoryStartedAt: Date?
    }

    actor RefreshTimelineBox {
        private var scanFinishedAt: Date?
        private var homebrewIndexStartedAt: Date?
        private var homebrewFormulaIndexStartedAt: Date?
        private var homebrewInventoryStartedAt: Date?

        func markScanFinished() {
            scanFinishedAt = Date()
        }

        func markHomebrewIndexStarted() {
            homebrewIndexStartedAt = Date()
        }

        func markHomebrewFormulaIndexStarted() {
            homebrewFormulaIndexStartedAt = Date()
        }

        func markHomebrewInventoryStarted() {
            homebrewInventoryStartedAt = Date()
        }

        func snapshot() -> RefreshTimelineSnapshot {
            RefreshTimelineSnapshot(
                scanFinishedAt: scanFinishedAt,
                homebrewIndexStartedAt: homebrewIndexStartedAt,
                homebrewFormulaIndexStartedAt: homebrewFormulaIndexStartedAt,
                homebrewInventoryStartedAt: homebrewInventoryStartedAt
            )
        }
    }

    func testRefreshFlowBuildsAvailableAndIgnoredSections() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            displayName: "Example",
            bundleIdentifier: "com.example.app",
            localVersion: Version("1.0.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in
                AppStoreLookupResult(
                    remoteVersion: Version("1.1.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id1"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.availableApps.count, 1)
        XCTAssertEqual(store.installedApps.count, 0)

        store.toggleIgnored(for: app)

        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.ignoredApps.count, 1)
    }

    func testAppStoreWinsFallbackPrecedence() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Precedence.app"),
            displayName: "Precedence",
            bundleIdentifier: "com.example.precedence",
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml")
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in
                AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id2"),
                    releaseNotesSummary: "Store",
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in
                SparkleLookupResult(
                    remoteVersion: Version("3.0"),
                    updateURL: URL(string: "https://example.com/sparkle"),
                    releaseNotesURL: nil,
                    releaseDate: nil
                )
            },
            fetchHomebrewIndex: {
                let entry = HomebrewCaskEntry(
                        token: "precedence",
                        version: Version("4.0"),
                        homepageURL: URL(string: "https://formulae.brew.sh/cask/precedence"),
                        bundleIdentifiers: ["com.example.precedence"],
                        appBundleNames: ["precedence.app"]
                    )
                return HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.precedence": entry],
                    byAppBundleName: ["precedence.app": [entry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, _, localVersion in
                guard let bundleIdentifier, let entry = index.byBundleIdentifier[bundleIdentifier] else { return nil }
                guard entry.version > localVersion else { return nil }
                return HomebrewLookupResult(
                    remoteVersion: entry.version,
                    token: entry.token,
                    homepageURL: entry.homepageURL
                )
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let update = store.update(for: app)
        XCTAssertEqual(update?.source, .appStore)
        XCTAssertEqual(update?.remoteVersion, Version("2.0"))
    }

    func testHomebrewFallbackMatchesByAppBundleNameWhenBundleIdentifierMisses() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["notion.app": [homebrewEntry]]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { index },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let update = store.update(for: app)
        XCTAssertEqual(store.availableApps.count, 1)
        XCTAssertEqual(update?.source, .homebrew)
        XCTAssertEqual(update?.remoteVersion, Version("7.9.0"))
        XCTAssertNil(update?.updateURL)
        XCTAssertEqual(update?.homebrewToken, "notion")
    }

    func testHomebrewFallbackDetectsFigmaBetaFromAtChannelToken() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Figma Beta.app"),
            displayName: "Figma Beta",
            bundleIdentifier: "com.figma.DesktopBeta",
            localVersion: Version("126.3.4"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "figma@beta",
            version: Version("126.3.6"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/figma@beta"),
            bundleIdentifiers: [],
            appBundleNames: ["figma beta.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["figma beta.app": [homebrewEntry]]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { index },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let update = store.update(for: app)
        XCTAssertEqual(store.availableApps.count, 1)
        XCTAssertEqual(update?.source, .homebrew)
        XCTAssertEqual(update?.remoteVersion, Version("126.3.6"))
        XCTAssertNil(update?.updateURL)
        XCTAssertEqual(update?.homebrewToken, "figma@beta")
    }

    func testRecentlyUpdatedAppsAreTrackedWithNewestFirst() async {
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("2.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let betaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Beta.app"),
            displayName: "Beta",
            bundleIdentifier: "com.example.beta",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let betaV3 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Beta.app"),
            displayName: "Beta",
            bundleIdentifier: "com.example.beta",
            localVersion: Version("3.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                switch phase.value {
                case 0:
                    return [alphaV1, betaV1]
                case 1:
                    return [alphaV2, betaV1]
                default:
                    return [alphaV2, betaV3]
                }
            },
            lookupAppStore: { bundleIdentifier, _ in
                switch bundleIdentifier {
                case "com.example.alpha":
                    guard phase.value == 0 else { return nil }
                    return AppStoreLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                        releaseNotesSummary: nil,
                        releaseDate: nil
                    )
                case "com.example.beta":
                    guard phase.value <= 1 else { return nil }
                    return AppStoreLookupResult(
                        remoteVersion: Version("3.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-beta"),
                        releaseNotesSummary: nil,
                        releaseDate: nil
                    )
                default:
                    return nil
                }
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(Set(store.availableApps.map(\.displayName)), Set(["Alpha", "Beta"]))
        XCTAssertEqual(store.recentlyUpdatedApps.count, 0)

        phase.value = 1
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Beta"])
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])

        try? await Task.sleep(nanoseconds: 30_000_000)
        phase.value = 2
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Beta", "Alpha"])
    }

    func testRecentlyUpdatedAppsSurviveTransientEmptyScanResults() async {
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: alphaV1.bundleURL,
            displayName: alphaV1.displayName,
            bundleIdentifier: alphaV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: alphaV1.sourceHint,
            sparkleFeedURL: alphaV1.sparkleFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                switch phase.value {
                case 0:
                    return [alphaV1]
                case 1:
                    return [alphaV2]
                case 2:
                    return []
                default:
                    return [alphaV2]
                }
            },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha", phase.value == 0 else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Alpha"])
        XCTAssertEqual(store.recentlyUpdatedApps.count, 0)

        phase.value = 1
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])

        phase.value = 2
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.recentlyUpdatedApps.count, 0)

        phase.value = 3
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
    }

    func testRecentlyUpdatedFallbackLoadsWhenSnapshotDecodeFails() async {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let alpha = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("2.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let recentRecord = RecentlyUpdatedRecord(
            appID: alpha.id,
            displayName: alpha.displayName,
            fromVersion: Version("1.0"),
            toVersion: alpha.localVersion,
            updatedAt: Date()
        )

        defaults.set(Data("corrupted".utf8), forKey: PersistenceKeys.snapshot)
        defaults.set(
            try? JSONEncoder().encode([recentRecord]),
            forKey: PersistenceKeys.recentlyUpdatedRecords
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [alpha] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(dependencies: deps, defaults: defaults)
        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
    }

    func testHydrationDoesNotClearRecentlyUpdatedWhenDedicatedKeysAreMissing() {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let alpha = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("2.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let recentRecord = RecentlyUpdatedRecord(
            appID: alpha.id,
            displayName: alpha.displayName,
            fromVersion: Version("1.0"),
            toVersion: alpha.localVersion,
            updatedAt: Date()
        )
        let snapshot = PersistedSnapshot(
            apps: [alpha],
            updates: [],
            recentlyUpdated: [recentRecord],
            homebrewItems: [],
            homebrewRecentlyUpdated: [],
            ignoredIDs: [],
            additionalDirectories: [],
            selectedTab: .apps,
            refreshIntervalMinutes: 60,
            lastRefreshDate: Date()
        )

        defaults.set(try? JSONEncoder().encode(snapshot), forKey: PersistenceKeys.snapshot)
        defaults.removeObject(forKey: PersistenceKeys.recentlyUpdatedRecords)
        defaults.removeObject(forKey: PersistenceKeys.homebrewRecentlyUpdatedRecords)

        let store = UpdateStore(dependencies: .live, defaults: defaults)

        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
        XCTAssertNil(defaults.data(forKey: PersistenceKeys.recentlyUpdatedRecords))
    }

    func testSectionVisibilityPreferencesPersistAcrossRelaunch() {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let store = UpdateStore(dependencies: .live, defaults: defaults)

        store.showInstalledAppsSection = false
        store.showRecentlyUpdatedAppsSection = false
        store.showIgnoredAppsSection = false
        store.showRecentlyUpdatedHomebrewSection = false
        store.showInstalledHomebrewSection = false
        store.showIgnoredHomebrewSection = false
        store.flushPendingPersistenceForTesting()

        let rehydrated = UpdateStore(dependencies: .live, defaults: defaults)

        XCTAssertFalse(rehydrated.showInstalledAppsSection)
        XCTAssertFalse(rehydrated.showRecentlyUpdatedAppsSection)
        XCTAssertFalse(rehydrated.showIgnoredAppsSection)
        XCTAssertFalse(rehydrated.showRecentlyUpdatedHomebrewSection)
        XCTAssertFalse(rehydrated.showInstalledHomebrewSection)
        XCTAssertFalse(rehydrated.showIgnoredHomebrewSection)
    }

    func testSectionVisibilityPreferencesDefaultToEnabledForLegacySnapshots() throws {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let legacySnapshot: [String: Any] = [
            "apps": [],
            "updates": [],
            "recentlyUpdated": [],
            "homebrewItems": [],
            "homebrewRecentlyUpdated": [],
            "ignoredIDs": [],
            "additionalDirectories": [],
            "selectedTab": MenuTab.apps.rawValue,
            "refreshIntervalMinutes": 60
        ]

        let data = try JSONSerialization.data(withJSONObject: legacySnapshot)
        defaults.set(data, forKey: PersistenceKeys.snapshot)

        let store = UpdateStore(dependencies: .live, defaults: defaults)

        XCTAssertTrue(store.showInstalledAppsSection)
        XCTAssertTrue(store.showRecentlyUpdatedAppsSection)
        XCTAssertTrue(store.showIgnoredAppsSection)
        XCTAssertTrue(store.showRecentlyUpdatedHomebrewSection)
        XCTAssertTrue(store.showInstalledHomebrewSection)
        XCTAssertTrue(store.showIgnoredHomebrewSection)
    }

    func testPerformUpdateUsesMasForAppStoreWhenItemIDIsAvailable() async {
        let appStoreCalls = AppStoreUpgradeCallsBox()
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: alphaV1.bundleURL,
            displayName: alphaV1.displayName,
            bundleIdentifier: alphaV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: alphaV1.sourceHint,
            sparkleFeedURL: alphaV1.sparkleFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [alphaV1] : [alphaV2]
            },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha", phase.value == 0 else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil,
                    appStoreItemID: 123456789
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runAppStoreUpgrade: { itemID in
                await appStoreCalls.append(itemID)
                return true
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Alpha"])

        phase.value = 1
        store.performUpdate(for: alphaV1)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "Alpha" })
        })
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
        let masCalls = await appStoreCalls.snapshot()
        XCTAssertEqual(masCalls, [123456789])
    }

    func testPerformUpdateFallsBackToExternalRouteWhenMasUpgradeFails() async {
        let appStoreCalls = AppStoreUpgradeCallsBox()
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: alphaV1.bundleURL,
            displayName: alphaV1.displayName,
            bundleIdentifier: alphaV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: alphaV1.sourceHint,
            sparkleFeedURL: alphaV1.sparkleFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [alphaV1] : [alphaV2]
            },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha", phase.value == 0 else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil,
                    appStoreItemID: 123456789
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runAppStoreUpgrade: { itemID in
                await appStoreCalls.append(itemID)
                return false
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            externalUpdateRefreshDelaySeconds: [0]
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Alpha"])

        phase.value = 1
        store.performUpdate(for: alphaV1)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "Alpha" })
        })
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
        let masCalls = await appStoreCalls.snapshot()
        XCTAssertEqual(masCalls, [123456789])
        XCTAssertEqual(
            externalOpenCalls.snapshot().map(\.absoluteString),
            ["https://apps.apple.com/app/id-alpha"]
        )
        XCTAssertTrue(appOpenCalls.snapshot().isEmpty)
    }

    func testPerformUpdateSchedulesAutomaticRefreshForExternalUpdateFlowWhenAppStoreItemIDIsMissing() async {
        let appStoreCalls = AppStoreUpgradeCallsBox()
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: alphaV1.bundleURL,
            displayName: alphaV1.displayName,
            bundleIdentifier: alphaV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: alphaV1.sourceHint,
            sparkleFeedURL: alphaV1.sparkleFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [alphaV1] : [alphaV2]
            },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha", phase.value == 0 else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runAppStoreUpgrade: { itemID in
                await appStoreCalls.append(itemID)
                return false
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            externalUpdateRefreshDelaySeconds: [0]
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Alpha"])

        phase.value = 1
        store.performUpdate(for: alphaV1)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "Alpha" })
        })
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
        let masCalls = await appStoreCalls.snapshot()
        XCTAssertTrue(masCalls.isEmpty)
        XCTAssertEqual(
            externalOpenCalls.snapshot().map(\.absoluteString),
            ["https://apps.apple.com/app/id-alpha"]
        )
        XCTAssertTrue(appOpenCalls.snapshot().isEmpty)
    }

    func testPerformUpdateSkipsMasWhenPreferenceIsDisabled() async {
        let appStoreCalls = AppStoreUpgradeCallsBox()
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let phase = PhaseBox()
        let alphaV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaV2 = AppRecord(
            bundleURL: alphaV1.bundleURL,
            displayName: alphaV1.displayName,
            bundleIdentifier: alphaV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: alphaV1.sourceHint,
            sparkleFeedURL: alphaV1.sparkleFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [alphaV1] : [alphaV2]
            },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha", phase.value == 0 else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil,
                    appStoreItemID: 123456789
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runAppStoreUpgrade: { itemID in
                await appStoreCalls.append(itemID)
                return true
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            externalUpdateRefreshDelaySeconds: [0]
        )
        store.useMasForAppStoreUpdates = false

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.availableApps.map(\.displayName), ["Alpha"])

        phase.value = 1
        store.performUpdate(for: alphaV1)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "Alpha" })
        })
        XCTAssertEqual(store.availableApps.count, 0)
        XCTAssertEqual(store.recentlyUpdatedApps.map(\.displayName), ["Alpha"])
        let masCalls = await appStoreCalls.snapshot()
        XCTAssertTrue(masCalls.isEmpty)
        XCTAssertEqual(
            externalOpenCalls.snapshot().map(\.absoluteString),
            ["https://apps.apple.com/app/id-alpha"]
        )
        XCTAssertTrue(appOpenCalls.snapshot().isEmpty)
    }

    func testPerformUpdateUsesHomebrewItemFlowForHomebrewSourcedAppRows() async {
        let homebrewItemCalls = HomebrewCallsBox()
        let homebrewTokenCalls = HomebrewUpgradeCallsBox()
        let phase = PhaseBox()
        let notionApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [notionApp] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "notion",
                            name: "notion",
                            kind: .cask,
                            installedVersion: Version("7.7.1"),
                            latestVersion: Version("7.9.0"),
                            isOutdated: true
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("7.9.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { token in
                await homebrewTokenCalls.append(token)
                return true
            },
            runHomebrewItemUpgrade: { kind, token in
                await homebrewItemCalls.append(kind, token)
                try? await Task.sleep(nanoseconds: 120_000_000)
                phase.value = 1
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: notionApp)?.source, .homebrew)

        store.performUpdate(for: notionApp)
        XCTAssertTrue(store.isUpdatingApp(notionApp))

        await waitUntil({
            !store.isUpdatingApp(notionApp) && !store.isRefreshing
        })

        let itemCalls = await homebrewItemCalls.snapshot()
        let tokenCalls = await homebrewTokenCalls.snapshot()
        XCTAssertEqual(itemCalls.count, 1)
        XCTAssertEqual(itemCalls[0].0, .cask)
        XCTAssertEqual(itemCalls[0].1, "notion")
        XCTAssertTrue(tokenCalls.isEmpty)
    }

    func testPerformUpdateFallsBackToTokenUpgradeWhenMappedHomebrewItemIsNotOutdated() async {
        let homebrewItemCalls = HomebrewCallsBox()
        let homebrewTokenCalls = HomebrewUpgradeCallsBox()
        let notionApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "notion-beta",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion-beta"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [notionApp] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("7.7.1"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { token in
                await homebrewTokenCalls.append(token)
                try? await Task.sleep(nanoseconds: 80_000_000)
                return true
            },
            runHomebrewItemUpgrade: { kind, token in
                await homebrewItemCalls.append(kind, token)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: notionApp)?.source, .homebrew)
        XCTAssertEqual(store.update(for: notionApp)?.homebrewToken, "notion-beta")
        XCTAssertEqual(store.uninstallableHomebrewItem(for: notionApp)?.token, "notion")

        store.performUpdate(for: notionApp)

        for _ in 0..<40 {
            if (await homebrewTokenCalls.snapshot()).count == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        await waitUntilRefreshFinishes(store)

        let itemCalls = await homebrewItemCalls.snapshot()
        let tokenCalls = await homebrewTokenCalls.snapshot()
        XCTAssertTrue(itemCalls.isEmpty)
        XCTAssertEqual(tokenCalls, ["notion-beta"])
    }

    func testPerformUpdateForLaggingHomebrewCaskRoutesExternalAndSkipsHomebrewCommands() async {
        let homebrewItemCalls = HomebrewCallsBox()
        let homebrewTokenCalls = HomebrewUpgradeCallsBox()
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let phase = PhaseBox()
        let samplesuiteV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.6.15"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let samplesuiteV2 = AppRecord(
            bundleURL: samplesuiteV1.bundleURL,
            displayName: samplesuiteV1.displayName,
            bundleIdentifier: samplesuiteV1.bundleIdentifier,
            localVersion: Version("1.7.0"),
            sourceHint: samplesuiteV1.sourceHint,
            sparkleFeedURL: samplesuiteV1.sparkleFeedURL
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.samplesuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [samplesuiteV1] : [samplesuiteV2]
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "samplesuite",
                            name: "samplesuite",
                            kind: .cask,
                            installedVersion: Version("1.6.15"),
                            latestVersion: nil,
                            isOutdated: false
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.7.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { token in
                await homebrewTokenCalls.append(token)
                return true
            },
            runHomebrewItemUpgrade: { kind, token in
                await homebrewItemCalls.append(kind, token)
                return true
            },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            externalUpdateRefreshDelaySeconds: [0]
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: samplesuiteV1)?.source, .homebrew)
        XCTAssertEqual(store.homebrewOutdatedItems.map(\.token), ["samplesuite"])

        phase.value = 1
        store.performUpdate(for: samplesuiteV1)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "SampleSuite" })
        })

        let itemCalls = await homebrewItemCalls.snapshot()
        let tokenCalls = await homebrewTokenCalls.snapshot()
        XCTAssertTrue(itemCalls.isEmpty)
        XCTAssertTrue(tokenCalls.isEmpty)
        XCTAssertTrue(externalOpenCalls.snapshot().isEmpty)
        XCTAssertEqual(appOpenCalls.snapshot().map(\.path), ["/Applications/SampleSuite.app"])
    }

    func testPerformHomebrewUpdateForLaggingCaskRoutesExternalAndSkipsHomebrewCommands() async {
        let homebrewItemCalls = HomebrewCallsBox()
        let homebrewTokenCalls = HomebrewUpgradeCallsBox()
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let phase = PhaseBox()
        let samplesuiteV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.6.15"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let samplesuiteV2 = AppRecord(
            bundleURL: samplesuiteV1.bundleURL,
            displayName: samplesuiteV1.displayName,
            bundleIdentifier: samplesuiteV1.bundleIdentifier,
            localVersion: Version("1.7.0"),
            sourceHint: samplesuiteV1.sourceHint,
            sparkleFeedURL: samplesuiteV1.sparkleFeedURL
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.samplesuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [samplesuiteV1] : [samplesuiteV2]
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "samplesuite",
                            name: "samplesuite",
                            kind: .cask,
                            installedVersion: Version("1.6.15"),
                            latestVersion: nil,
                            isOutdated: false
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.7.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { token in
                await homebrewTokenCalls.append(token)
                return true
            },
            runHomebrewItemUpgrade: { kind, token in
                await homebrewItemCalls.append(kind, token)
                return true
            },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            externalUpdateRefreshDelaySeconds: [0]
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        guard let laggingItem = store.homebrewOutdatedItems.first(where: { $0.token == "samplesuite" }) else {
            XCTFail("Expected reconciled lagging cask item for samplesuite.")
            return
        }

        phase.value = 1
        store.performHomebrewUpdate(for: laggingItem)

        await waitUntil({
            store.recentlyUpdatedApps.contains(where: { $0.displayName == "SampleSuite" })
        })

        let itemCalls = await homebrewItemCalls.snapshot()
        let tokenCalls = await homebrewTokenCalls.snapshot()
        XCTAssertTrue(itemCalls.isEmpty)
        XCTAssertTrue(tokenCalls.isEmpty)
        XCTAssertTrue(externalOpenCalls.snapshot().isEmpty)
        XCTAssertEqual(appOpenCalls.snapshot().map(\.path), ["/Applications/SampleSuite.app"])
    }

    func testRefreshMasSetupStatusTracksMasAndHomebrewAvailability() async {
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { true },
            checkMasSignedIn: { false },
            checkHomebrewInstalled: { true },
            installMasUsingHomebrew: { false },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshMasSetupStatus()
        await waitUntil({ !store.isCheckingMas })

        XCTAssertTrue(store.isMasInstalled)
        XCTAssertTrue(store.isHomebrewInstalledForMasInstall)
    }

    func testMasSetupReportsSuccessWhenInstalledAndSignedIn() async {
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { true },
            checkMasSignedIn: { true },
            checkHomebrewInstalled: { true },
            installMasUsingHomebrew: { false },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshMasSetupStatus()
        await waitUntil({ !store.isCheckingMas })

        store.testMasSetup()
        await waitUntil({ !store.isTestingMas && store.masTestSucceeded != nil })

        XCTAssertEqual(store.masTestSucceeded, true)
        XCTAssertTrue((store.masTestMessage ?? "").localizedCaseInsensitiveContains("ready"))
    }

    func testMasSetupReportsActionableMessageWhenNotSignedIn() async {
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { true },
            checkMasSignedIn: { false },
            checkHomebrewInstalled: { true },
            installMasUsingHomebrew: { false },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshMasSetupStatus()
        await waitUntil({ !store.isCheckingMas })

        store.testMasSetup()
        await waitUntil({ !store.isTestingMas && store.masTestSucceeded != nil })

        XCTAssertEqual(store.masTestSucceeded, false)
        XCTAssertTrue((store.masTestMessage ?? "").localizedCaseInsensitiveContains("sign in"))
    }

    func testMasSetupReportsInstallNeededWhenMasMissing() async {
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { false },
            checkMasSignedIn: { false },
            checkHomebrewInstalled: { true },
            installMasUsingHomebrew: { false },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshMasSetupStatus()
        await waitUntil({ !store.isCheckingMas })
        store.testMasSetup()

        XCTAssertEqual(store.masTestSucceeded, false)
        XCTAssertTrue((store.masTestMessage ?? "").localizedCaseInsensitiveContains("not installed"))
    }

    func testInstallMasWithHomebrewMarksMasInstalledOnSuccess() async {
        let phase = PhaseBox()
        let installCalls = CounterBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { phase.value == 1 },
            checkMasSignedIn: { false },
            checkHomebrewInstalled: { true },
            installMasUsingHomebrew: {
                await installCalls.increment()
                phase.value = 1
                return true
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshMasSetupStatus()
        await waitUntil({ !store.isCheckingMas })
        XCTAssertFalse(store.isMasInstalled)

        store.installMasWithHomebrew()
        await waitUntil({ !store.isInstallingMas && store.masTestSucceeded != nil })

        XCTAssertTrue(store.isMasInstalled)
        XCTAssertEqual(store.masTestSucceeded, true)
        XCTAssertTrue((store.masTestMessage ?? "").localizedCaseInsensitiveContains("installed"))
        let count = await installCalls.snapshot()
        XCTAssertEqual(count, 1)
    }

    func testInstallMasWithHomebrewShowsGuidanceWhenHomebrewMissing() async {
        let installCalls = CounterBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkMasInstalled: { false },
            checkMasSignedIn: { false },
            checkHomebrewInstalled: { false },
            installMasUsingHomebrew: {
                await installCalls.increment()
                return true
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.installMasWithHomebrew()
        await waitUntil({ !store.isInstallingMas && store.masTestSucceeded != nil })

        XCTAssertFalse(store.isMasInstalled)
        XCTAssertEqual(store.masTestSucceeded, false)
        XCTAssertTrue((store.masTestMessage ?? "").localizedCaseInsensitiveContains("homebrew"))
        let count = await installCalls.snapshot()
        XCTAssertEqual(count, 0)
    }

    func testAvailableAppsAreOrderedByNewestReleaseDateFirst() async {
        let olderApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Older.app"),
            displayName: "Older",
            bundleIdentifier: "com.example.older",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let newerApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Newer.app"),
            displayName: "Newer",
            bundleIdentifier: "com.example.newer",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [olderApp, newerApp] },
            lookupAppStore: { bundleIdentifier, _ in
                switch bundleIdentifier {
                case "com.example.older":
                    return AppStoreLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-older"),
                        releaseNotesSummary: nil,
                        releaseDate: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                case "com.example.newer":
                    return AppStoreLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-newer"),
                        releaseNotesSummary: nil,
                        releaseDate: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                default:
                    return nil
                }
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.availableApps.map(\.displayName), ["Newer", "Older"])
    }

    func testDisplayedAvailableAppsFilterBySearchText() async {
        let alphaApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let betaApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Beta.app"),
            displayName: "Beta",
            bundleIdentifier: "com.example.beta",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [alphaApp, betaApp] },
            lookupAppStore: { bundleIdentifier, _ in
                switch bundleIdentifier {
                case "com.example.alpha":
                    return AppStoreLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                        releaseNotesSummary: nil,
                        releaseDate: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                case "com.example.beta":
                    return AppStoreLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id-beta"),
                        releaseNotesSummary: nil,
                        releaseDate: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                default:
                    return nil
                }
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        store.searchText = "beta"

        XCTAssertEqual(store.displayedAvailableApps.map(\.displayName), ["Beta"])
    }

    func testReleaseDateForAppFallsBackWhenBundleTimestampIsLegacy() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BaselineTests-\(UUID().uuidString)", isDirectory: true)
        let appBundleURL = tempRoot.appendingPathComponent("Cursor.app", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appBundleURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let legacyDate = Date(timeIntervalSince1970: 315_532_800) // 1980-01-01
        try FileManager.default.setAttributes(
            [
                .creationDate: legacyDate,
                .modificationDate: legacyDate
            ],
            ofItemAtPath: appBundleURL.path
        )

        let app = AppRecord(
            bundleURL: appBundleURL,
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            localVersion: Version("0.50.5"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        let before = Date()
        let displayedReleaseDate = store.releaseDate(for: app)
        let after = Date()

        XCTAssertGreaterThan(displayedReleaseDate.timeIntervalSince1970, 946_684_800)
        XCTAssertGreaterThanOrEqual(displayedReleaseDate, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(displayedReleaseDate, after.addingTimeInterval(1))
    }

    func testHomebrewSourcedAppReleaseDateMatchesHomebrewItemReleaseDate() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/tmp/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.6.15"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let expectedReleaseDate = Date(timeIntervalSince1970: 1_775_001_600) // 2026-03-31T00:00:00Z
        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.SampleSuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.6.15"),
                        latestVersion: Version("1.7.0"),
                        isOutdated: true,
                        releaseDate: expectedReleaseDate
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        guard let homebrewItem = store.homebrewOutdatedItems.first else {
            XCTFail("Expected Homebrew outdated item for samplesuite.")
            return
        }

        XCTAssertEqual(homebrewItem.token, "samplesuite")
        XCTAssertEqual(store.releaseDate(for: homebrewItem), expectedReleaseDate)
        XCTAssertEqual(store.releaseDate(for: app), expectedReleaseDate)
    }

    func testHomebrewCasksAppearInAppsAndHomebrewTabData() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "ripgrep",
                        name: "ripgrep",
                        kind: .formula,
                        installedVersion: Version("14.0.2"),
                        latestVersion: Version("14.1.0"),
                        isOutdated: true
                    ),
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("7.7.1"),
                        latestVersion: Version("7.9.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.availableApps.map(\.displayName), ["Notion"])
        XCTAssertEqual(Set(store.homebrewOutdatedItems.map(\.token)), Set(["ripgrep", "notion"]))
        XCTAssertEqual(store.homebrewInstalledItems.count, 0)
    }

    func testHomebrewInventoryReconciliationShowsLaggingCaskAsOutdatedAcrossTabs() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.6.15"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.SampleSuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.6.15"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.availableApps.map(\.displayName), ["SampleSuite"])
        XCTAssertEqual(store.update(for: app)?.source, .homebrew)
        XCTAssertEqual(store.homebrewOutdatedItems.map(\.token), ["samplesuite"])
        XCTAssertEqual(store.homebrewOutdatedItems.first?.latestVersion, Version("1.7.0"))
        XCTAssertTrue(store.homebrewInstalledItems.isEmpty)
    }

    func testHomebrewInventorySanitizationClearsStaleOutdatedAfterExternalAppUpdate() async {
        let phase = PhaseBox()
        let samplesuiteV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.6.15"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let samplesuiteV2 = AppRecord(
            bundleURL: samplesuiteV1.bundleURL,
            displayName: samplesuiteV1.displayName,
            bundleIdentifier: samplesuiteV1.bundleIdentifier,
            localVersion: Version("1.7.0"),
            sourceHint: samplesuiteV1.sourceHint,
            sparkleFeedURL: samplesuiteV1.sparkleFeedURL
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.SampleSuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                phase.value == 0 ? [samplesuiteV1] : [samplesuiteV2]
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.6.15"),
                        latestVersion: Version("1.7.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.homebrewOutdatedItems.map(\.token), ["samplesuite"])
        XCTAssertEqual(store.homebrewOutdatedItems.first?.installedVersion, Version("1.6.15"))

        phase.value = 1
        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertTrue(store.homebrewOutdatedItems.isEmpty)
        XCTAssertEqual(store.homebrewInstalledItems.map(\.token), ["samplesuite"])
        XCTAssertEqual(store.homebrewInstalledItems.first?.installedVersion, Version("1.7.0"))
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.map(\.token), ["samplesuite"])
    }

    func testHomebrewInventorySanitizationInfersRecentlyUpdatedWhenAppAlreadyExternalUpdated() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SampleSuite.app"),
            displayName: "SampleSuite",
            bundleIdentifier: "com.example.SampleSuite",
            localVersion: Version("1.7.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "samplesuite",
            version: Version("1.7.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/samplesuite"),
            bundleIdentifiers: ["com.example.SampleSuite"],
            appBundleNames: ["samplesuite.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [app] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: ["com.example.samplesuite": homebrewEntry],
                    byAppBundleName: ["samplesuite.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "samplesuite",
                        name: "samplesuite",
                        kind: .cask,
                        installedVersion: Version("1.6.15"),
                        latestVersion: Version("1.7.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertTrue(store.homebrewOutdatedItems.isEmpty)
        XCTAssertEqual(store.homebrewInstalledItems.map(\.token), ["samplesuite"])
        XCTAssertEqual(store.homebrewInstalledItems.first?.installedVersion, Version("1.7.0"))
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.map(\.token), ["samplesuite"])
    }

    func testHomebrewOutdatedItemsAreOrderedByNewestReleaseDateFirst() async {
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "older",
                        name: "older",
                        kind: .formula,
                        installedVersion: Version("1.0"),
                        latestVersion: Version("1.1"),
                        isOutdated: true,
                        releaseDate: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                    HomebrewManagedItem(
                        token: "newer",
                        name: "newer",
                        kind: .cask,
                        installedVersion: Version("1.0"),
                        latestVersion: Version("1.1"),
                        isOutdated: true,
                        releaseDate: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.homebrewOutdatedItems.map(\.token), ["newer", "older"])
    }

    func testHomebrewIgnoreMovesItemsOutOfPrimarySections() async {
        let formulaOutdated = HomebrewManagedItem(
            token: "ripgrep",
            name: "ripgrep",
            kind: .formula,
            installedVersion: Version("14.0.2"),
            latestVersion: Version("14.1.0"),
            isOutdated: true
        )
        let caskInstalled = HomebrewManagedItem(
            token: "notion",
            name: "notion",
            kind: .cask,
            installedVersion: Version("7.7.1"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [formulaOutdated, caskInstalled] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(Set(store.homebrewOutdatedItems.map(\.token)), Set(["ripgrep"]))
        XCTAssertEqual(Set(store.homebrewInstalledItems.map(\.token)), Set(["notion"]))
        XCTAssertEqual(store.homebrewIgnoredItems.count, 0)

        store.toggleIgnored(for: formulaOutdated)

        XCTAssertEqual(store.homebrewOutdatedItems.count, 0)
        XCTAssertEqual(Set(store.homebrewIgnoredItems.map(\.token)), Set(["ripgrep"]))

        store.toggleIgnored(for: formulaOutdated)

        XCTAssertEqual(Set(store.homebrewOutdatedItems.map(\.token)), Set(["ripgrep"]))
        XCTAssertEqual(store.homebrewIgnoredItems.count, 0)
    }

    func testIgnoredHomebrewItemsPersistAcrossRelaunch() {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let item = HomebrewManagedItem(
            token: "wezterm",
            name: "wezterm",
            kind: .cask,
            installedVersion: Version("1.0"),
            latestVersion: Version("1.1"),
            isOutdated: true
        )

        let store = UpdateStore(dependencies: .live, defaults: defaults)
        store.toggleIgnored(for: item)
        store.showIgnoredHomebrewSection = false
        store.flushPendingPersistenceForTesting()

        let rehydrated = UpdateStore(dependencies: .live, defaults: defaults)
        XCTAssertTrue(rehydrated.ignoredHomebrewItemIDs.contains(item.id))
        XCTAssertFalse(rehydrated.showIgnoredHomebrewSection)
    }

    func testHomebrewRecentlyUpdatedItemsTrackTransitionsAndDropWhenInvalid() async {
        let phase = PhaseBox()

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                switch phase.value {
                case 0:
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("1.1"),
                            isOutdated: true
                        ),
                        HomebrewManagedItem(
                            token: "wezterm",
                            name: "wezterm",
                            kind: .cask,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("1.1"),
                            isOutdated: true
                        )
                    ]
                case 1:
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("1.1"),
                            latestVersion: nil,
                            isOutdated: false
                        ),
                        HomebrewManagedItem(
                            token: "wezterm",
                            name: "wezterm",
                            kind: .cask,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("1.1"),
                            isOutdated: true
                        )
                    ]
                case 2:
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("1.1"),
                            latestVersion: nil,
                            isOutdated: false
                        ),
                        HomebrewManagedItem(
                            token: "wezterm",
                            name: "wezterm",
                            kind: .cask,
                            installedVersion: Version("1.1"),
                            latestVersion: nil,
                            isOutdated: false
                        )
                    ]
                default:
                    return [
                        HomebrewManagedItem(
                            token: "wezterm",
                            name: "wezterm",
                            kind: .cask,
                            installedVersion: Version("1.1"),
                            latestVersion: Version("1.2"),
                            isOutdated: true
                        )
                    ]
                }
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.count, 0)

        phase.value = 1
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.map(\.token), ["fd"])
        XCTAssertNotNil(store.recentlyUpdatedDate(for: store.homebrewRecentlyUpdatedItems[0]))

        try? await Task.sleep(nanoseconds: 30_000_000)
        phase.value = 2
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.map(\.token), ["wezterm", "fd"])

        phase.value = 3
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.homebrewRecentlyUpdatedItems.count, 0)
    }

    func testPerformHomebrewUpdateDispatchesKindAndToken() async {
        let calls = HomebrewCallsBox()

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { kind, token in
                await calls.append(kind, token)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUpdate(
            for: HomebrewManagedItem(
                token: "fd",
                name: "fd",
                kind: .formula,
                installedVersion: Version("1.0"),
                latestVersion: Version("1.1"),
                isOutdated: true
            )
        )

        store.performHomebrewUpdate(
            for: HomebrewManagedItem(
                token: "wezterm",
                name: "wezterm",
                kind: .cask,
                installedVersion: Version("1.0"),
                latestVersion: Version("1.1"),
                isOutdated: true
            )
        )

        let timeout = Date().addingTimeInterval(1.0)
        while await calls.snapshot().count < 2, Date() < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let capturedCalls = await calls.snapshot()
        XCTAssertEqual(capturedCalls.count, 2)
        XCTAssertEqual(capturedCalls[0].0, .formula)
        XCTAssertEqual(capturedCalls[0].1, "fd")
        XCTAssertEqual(capturedCalls[1].0, .cask)
        XCTAssertEqual(capturedCalls[1].1, "wezterm")
    }

    func testPerformHomebrewUninstallCallsDependencyForCaskAndTracksRunningState() async {
        let uninstallCalls = HomebrewUninstallCallsBox()
        let item = HomebrewManagedItem(
            token: "wezterm",
            name: "WezTerm",
            kind: .cask,
            installedVersion: Version("1.0"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { token in
                await uninstallCalls.append(token)
                try? await Task.sleep(nanoseconds: 80_000_000)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUninstall(for: item)
        XCTAssertTrue(store.isUninstallingHomebrewItem(item))

        await waitUntil({
            !store.isUninstallingHomebrewItem(item)
        })

        let tokens = await uninstallCalls.snapshot()
        XCTAssertEqual(tokens, ["wezterm"])
    }

    func testPerformHomebrewUninstallIgnoresFormulaItems() async {
        let uninstallCalls = HomebrewUninstallCallsBox()
        let formula = HomebrewManagedItem(
            token: "fd",
            name: "fd",
            kind: .formula,
            installedVersion: Version("1.0"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { token in
                await uninstallCalls.append(token)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUninstall(for: formula)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let tokens = await uninstallCalls.snapshot()
        XCTAssertEqual(tokens.count, 0)
        XCTAssertFalse(store.isUninstallingHomebrewItem(formula))
    }

    func testPerformHomebrewUninstallSuppressesDuplicateTapsWhileRunning() async {
        let uninstallCalls = HomebrewUninstallCallsBox()
        let item = HomebrewManagedItem(
            token: "wezterm",
            name: "WezTerm",
            kind: .cask,
            installedVersion: Version("1.0"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { token in
                await uninstallCalls.append(token)
                try? await Task.sleep(nanoseconds: 180_000_000)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUninstall(for: item)
        store.performHomebrewUninstall(for: item)
        XCTAssertTrue(store.isUninstallingHomebrewItem(item))

        await waitUntil({
            !store.isUninstallingHomebrewItem(item)
        })

        let tokens = await uninstallCalls.snapshot()
        XCTAssertEqual(tokens, ["wezterm"])
    }

    func testPerformHomebrewUninstallFailureSetsErrorAndClearsRunningState() async {
        let uninstallCalls = HomebrewUninstallCallsBox()
        let item = HomebrewManagedItem(
            token: "wezterm",
            name: "WezTerm",
            kind: .cask,
            installedVersion: Version("1.0"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { token in
                await uninstallCalls.append(token)
                return false
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUninstall(for: item)

        await waitUntil({
            !store.isUninstallingHomebrewItem(item)
                && !store.isRefreshing
                && (store.refreshErrorMessage?.localizedCaseInsensitiveContains("failed") ?? false)
        })

        let tokens = await uninstallCalls.snapshot()
        XCTAssertEqual(tokens, ["wezterm"])
        XCTAssertFalse(store.isUninstallingHomebrewItem(item))
        XCTAssertTrue((store.refreshErrorMessage ?? "").localizedCaseInsensitiveContains("failed"))
    }

    func testPerformHomebrewUninstallFailureIncludesHomebrewOutputWhenAvailable() async {
        let item = HomebrewManagedItem(
            token: "protonvpn",
            name: "protonvpn",
            kind: .cask,
            installedVersion: Version("6.4.0.upgrading"),
            latestVersion: Version("6.5.0"),
            isOutdated: true
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { _ in false },
            runHomebrewCaskUninstallWithOutput: { _ in
                HomebrewCommandResult(
                    didComplete: false,
                    output: "Error: It seems there is already an App at '/opt/homebrew/Caskroom/protonvpn/6.4.0/ProtonVPN.app'."
                )
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUninstall(for: item)

        await waitUntil({
            !store.isUninstallingHomebrewItem(item)
                && !store.isRefreshing
                && ((store.refreshErrorMessage ?? "").contains("already an App"))
        })

        let message = store.refreshErrorMessage ?? ""
        XCTAssertTrue(message.contains("Homebrew uninstall failed for protonvpn."))
        XCTAssertTrue(message.contains("already an App"))
    }

    func testPerformHomebrewUninstallForAppUsesMappedCaskItem() async {
        let uninstallCalls = HomebrewUninstallCallsBox()
        let notionApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [notionApp] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "Notion",
                        kind: .cask,
                        installedVersion: Version("7.7.1"),
                        latestVersion: Version("7.9.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskUninstall: { token in
                await uninstallCalls.append(token)
                try? await Task.sleep(nanoseconds: 80_000_000)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.uninstallableHomebrewItem(for: notionApp)?.token, "notion")

        store.performHomebrewUninstall(for: notionApp)
        XCTAssertTrue(store.isUninstallingHomebrewItem(for: notionApp))

        await waitUntil({
            !store.isUninstallingHomebrewItem(for: notionApp)
        })

        let tokens = await uninstallCalls.snapshot()
        XCTAssertEqual(tokens, ["notion"])
    }

    func testUninstallableHomebrewItemForAppReturnsNilWhenMappedItemIsFormula() async {
        let notionApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("7.7.1"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let homebrewEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [notionApp] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [homebrewEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .formula,
                        installedVersion: Version("7.7.1"),
                        latestVersion: Version("7.9.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        XCTAssertNil(store.uninstallableHomebrewItem(for: notionApp))
        XCTAssertFalse(store.isUninstallingHomebrewItem(for: notionApp))
    }

    func testPerformHomebrewUpdateAllUsesMaintenanceDependencyAndDoneStateFlow() async {
        let runBox = HomebrewRunBox()

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 120_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: {
                runBox.runCount += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
                return true
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUpdateAll()
        XCTAssertTrue(store.isRunningHomebrewMaintenance)
        XCTAssertFalse(store.isHomebrewUpdateAllUpdatedPendingRefresh)

        await waitUntil { store.isRefreshing }
        XCTAssertTrue(store.isHomebrewUpdateAllUpdatedPendingRefresh)

        let timeout = Date().addingTimeInterval(1.0)
        while store.isRunningHomebrewMaintenance, Date() < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        await waitUntil { !store.isRefreshing }
        XCTAssertFalse(store.isRunningHomebrewMaintenance)
        XCTAssertFalse(store.isHomebrewUpdateAllUpdatedPendingRefresh)
        XCTAssertEqual(runBox.runCount, 1)
    }

    func testPerformHomebrewUpdateAllFailureDoesNotSetDoneState() async {
        let runBox = HomebrewRunBox()

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 120_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: {
                runBox.runCount += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
                return false
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUpdateAll()
        XCTAssertTrue(store.isRunningHomebrewMaintenance)
        XCTAssertFalse(store.isHomebrewUpdateAllUpdatedPendingRefresh)

        await waitUntil { store.isRefreshing }
        XCTAssertFalse(store.isHomebrewUpdateAllUpdatedPendingRefresh)

        await waitUntil { !store.isRefreshing }
        XCTAssertFalse(store.isRunningHomebrewMaintenance)
        XCTAssertFalse(store.isHomebrewUpdateAllUpdatedPendingRefresh)
        XCTAssertEqual(runBox.runCount, 1)
    }

    func testPerformHomebrewUpdateAllTracksOnlyAffectedRowsAndProgress() async {
        let phase = PhaseBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 140_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("9.0"),
                            latestVersion: Version("10.0"),
                            isOutdated: true
                        ),
                        HomebrewManagedItem(
                            token: "wezterm",
                            name: "wezterm",
                            kind: .cask,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("2.0"),
                            isOutdated: true
                        ),
                        HomebrewManagedItem(
                            token: "git",
                            name: "git",
                            kind: .formula,
                            installedVersion: Version("2.47"),
                            latestVersion: nil,
                            isOutdated: false
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "fd",
                        name: "fd",
                        kind: .formula,
                        installedVersion: Version("10.0"),
                        latestVersion: nil,
                        isOutdated: false
                    ),
                    HomebrewManagedItem(
                        token: "wezterm",
                        name: "wezterm",
                        kind: .cask,
                        installedVersion: Version("2.0"),
                        latestVersion: nil,
                        isOutdated: false
                    ),
                    HomebrewManagedItem(
                        token: "git",
                        name: "git",
                        kind: .formula,
                        installedVersion: Version("2.47"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            runHomebrewMaintenanceCycleWithEvents: { onEvent in
                onEvent(.commandStarted(["upgrade"]))
                onEvent(.outputLine(command: ["upgrade"], line: "==> Downloading fd"))
                onEvent(.outputLine(command: ["upgrade"], line: "==> Pouring fd--10.0.bottle.tar.gz"))
                onEvent(.outputLine(command: ["upgrade"], line: "🍺  /opt/homebrew/Cellar/fd/10.0"))
                onEvent(.commandFinished(command: ["upgrade"], success: true))
                onEvent(.commandStarted(["upgrade", "--cask", "--greedy"]))
                onEvent(.outputLine(command: ["upgrade", "--cask", "--greedy"], line: "==> Downloading wezterm"))
                onEvent(.outputLine(command: ["upgrade", "--cask", "--greedy"], line: "==> Installing Cask wezterm"))
                onEvent(.outputLine(command: ["upgrade", "--cask", "--greedy"], line: "==> Purging files for version 1.0 of Cask wezterm"))
                onEvent(.commandFinished(command: ["upgrade", "--cask", "--greedy"], success: true))
                phase.value = 1
                return true
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        guard
            let fdItem = store.homebrewOutdatedItems.first(where: { $0.token == "fd" }),
            let weztermItem = store.homebrewOutdatedItems.first(where: { $0.token == "wezterm" }),
            let gitItem = store.homebrewInstalledItems.first(where: { $0.token == "git" })
        else {
            XCTFail("Expected initial homebrew inventory items.")
            return
        }

        store.performHomebrewUpdateAll()

        XCTAssertTrue(store.isUpdatingHomebrewItem(fdItem))
        XCTAssertTrue(store.isUpdatingHomebrewItem(weztermItem))
        XCTAssertFalse(store.isUpdatingHomebrewItem(gitItem))

        await waitUntil({
            (store.homebrewUpdateProgress(for: fdItem) ?? 0) > 0
                && (store.homebrewUpdateProgress(for: weztermItem) ?? 0) > 0
        })

        await waitUntil { store.isRefreshing }
        XCTAssertTrue(store.isHomebrewItemUpdatedPendingRefresh(fdItem))
        XCTAssertTrue(store.isHomebrewItemUpdatedPendingRefresh(weztermItem))
        XCTAssertFalse(store.isHomebrewItemUpdateFailed(fdItem))
        XCTAssertFalse(store.isHomebrewItemUpdateFailed(weztermItem))

        await waitUntil { !store.isRefreshing && !store.isRunningHomebrewMaintenance }
        XCTAssertTrue(store.homebrewOutdatedItems.isEmpty)
    }

    func testPerformHomebrewUpdateAllSyncsHomebrewProgressToAppsTabRows() async {
        let phase = PhaseBox()
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let caskEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("2.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 140_000_000)
                return [app]
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [caskEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "notion",
                            name: "notion",
                            kind: .cask,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("2.0"),
                            isOutdated: true
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("2.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            runHomebrewMaintenanceCycleWithEvents: { onEvent in
                onEvent(.commandStarted(["upgrade", "--cask", "--greedy"]))
                onEvent(.outputLine(command: ["upgrade", "--cask", "--greedy"], line: "==> Downloading notion"))
                onEvent(.outputLine(command: ["upgrade", "--cask", "--greedy"], line: "==> Installing Cask notion"))
                phase.value = 1
                return true
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: app)?.source, .homebrew)

        store.performHomebrewUpdateAll()
        XCTAssertTrue(store.isUpdatingApp(app))

        await waitUntil({
            (store.appUpdateProgress(for: app) ?? 0) > 0
        })

        await waitUntil { !store.isRefreshing && !store.isRunningHomebrewMaintenance }
        XCTAssertFalse(store.isUpdatingApp(app))
    }

    func testPerformHomebrewUpdateAllMarksFailedRowsAndPreservesGlobalError() async {
        let phase = PhaseBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 140_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("9.0"),
                            latestVersion: Version("10.0"),
                            isOutdated: true
                        )
                    ]
                }

                return [
                    HomebrewManagedItem(
                        token: "fd",
                        name: "fd",
                        kind: .formula,
                        installedVersion: Version("9.0"),
                        latestVersion: Version("10.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            runHomebrewMaintenanceCycleWithEvents: { onEvent in
                onEvent(.commandStarted(["upgrade"]))
                onEvent(.outputLine(command: ["upgrade"], line: "Error: fd: failed to download resource"))
                phase.value = 1
                return false
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        guard let fdItem = store.homebrewOutdatedItems.first(where: { $0.token == "fd" }) else {
            XCTFail("Expected fd outdated item.")
            return
        }

        store.performHomebrewUpdateAll()

        await waitUntil { store.isRefreshing }
        XCTAssertTrue(store.isHomebrewItemUpdateFailed(fdItem))
        XCTAssertFalse(store.isUpdatingHomebrewItem(fdItem))

        await waitUntil {
            store.refreshErrorMessage == "Homebrew maintenance cycle failed."
        }
    }

    func testPerformHomebrewUpdateSingleRowShowsLiveProgressAndClearsAfterRefresh() async {
        let phase = PhaseBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 120_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("9.0"),
                            latestVersion: Version("10.0"),
                            isOutdated: true
                        )
                    ]
                }
                return [
                    HomebrewManagedItem(
                        token: "fd",
                        name: "fd",
                        kind: .formula,
                        installedVersion: Version("10.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewItemUpgradeWithEvents: { kind, token, onEvent in
                let command = kind == .cask
                    ? ["upgrade", "--cask", token]
                    : ["upgrade", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "==> Downloading \(token)"))
                try? await Task.sleep(nanoseconds: 50_000_000)
                onEvent(.outputLine(command: command, line: "==> Pouring \(token)--10.0.bottle.tar.gz"))
                try? await Task.sleep(nanoseconds: 50_000_000)
                onEvent(.outputLine(command: command, line: "🍺  /opt/homebrew/Cellar/\(token)/10.0"))
                onEvent(.commandFinished(command: command, success: true))
                phase.value = 1
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        guard let fdItem = store.homebrewOutdatedItems.first(where: { $0.token == "fd" }) else {
            XCTFail("Expected outdated fd item.")
            return
        }

        store.performHomebrewUpdate(for: fdItem)
        XCTAssertTrue(store.isUpdatingHomebrewItem(fdItem))

        await waitUntil({
            (store.homebrewUpdateProgress(for: fdItem) ?? 0) > 0
        })

        await waitUntil {
            store.isHomebrewItemUpdatedPendingRefresh(fdItem)
        }
        XCTAssertTrue(store.isHomebrewItemUpdatedPendingRefresh(fdItem))
        XCTAssertFalse(store.isHomebrewItemUpdateFailed(fdItem))

        await waitUntil {
            !store.isUpdatingHomebrewItem(fdItem) && !store.isRefreshing
        }
        XCTAssertFalse(store.isUpdatingHomebrewItem(fdItem))
        XCTAssertTrue(store.homebrewOutdatedItems.isEmpty)
    }

    func testPerformUpdateForHomebrewBackedAppShowsSingleRowLiveProgress() async {
        let phase = PhaseBox()
        let appV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let appV2 = AppRecord(
            bundleURL: appV1.bundleURL,
            displayName: appV1.displayName,
            bundleIdentifier: appV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: appV1.sourceHint,
            sparkleFeedURL: appV1.sparkleFeedURL
        )
        let caskEntry = HomebrewCaskEntry(
            token: "notion",
            version: Version("2.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in phase.value == 0 ? [appV1] : [appV2] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [caskEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "notion",
                            name: "notion",
                            kind: .cask,
                            installedVersion: Version("1.0"),
                            latestVersion: Version("2.0"),
                            isOutdated: true
                        )
                    ]
                }
                return [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("2.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewItemUpgradeWithEvents: { kind, token, onEvent in
                let command = kind == .cask
                    ? ["upgrade", "--cask", token]
                    : ["upgrade", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "==> Downloading \(token)"))
                try? await Task.sleep(nanoseconds: 40_000_000)
                onEvent(.outputLine(command: command, line: "==> Installing Cask \(token)"))
                try? await Task.sleep(nanoseconds: 40_000_000)
                onEvent(.outputLine(command: command, line: "==> Purging files for version 1.0 of Cask \(token)"))
                onEvent(.commandFinished(command: command, success: true))
                phase.value = 1
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: appV1)?.source, .homebrew)

        store.performUpdate(for: appV1)
        XCTAssertTrue(store.isUpdatingApp(appV1))

        await waitUntil({
            (store.appUpdateProgress(for: appV1) ?? 0) > 0
        })

        await waitUntil {
            !store.isUpdatingApp(appV1) && !store.isRefreshing
        }
        XCTAssertFalse(store.isUpdatingApp(appV1))
        XCTAssertFalse(store.isAppUpdateFailed(appV1))
    }

    func testPerformHomebrewUpdateSingleRowFailureMarksRowAndRestoresGlobalError() async {
        let phase = PhaseBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 120_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return [
                        HomebrewManagedItem(
                            token: "fd",
                            name: "fd",
                            kind: .formula,
                            installedVersion: Version("9.0"),
                            latestVersion: Version("10.0"),
                            isOutdated: true
                        )
                    ]
                }
                return [
                    HomebrewManagedItem(
                        token: "fd",
                        name: "fd",
                        kind: .formula,
                        installedVersion: Version("9.0"),
                        latestVersion: Version("10.0"),
                        isOutdated: true
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in false },
            runHomebrewItemUpgradeWithEvents: { kind, token, onEvent in
                let command = kind == .cask
                    ? ["upgrade", "--cask", token]
                    : ["upgrade", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "Error: \(token): failed to download resource"))
                onEvent(.commandFinished(command: command, success: false))
                phase.value = 1
                return false
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        guard let fdItem = store.homebrewOutdatedItems.first(where: { $0.token == "fd" }) else {
            XCTFail("Expected outdated fd item.")
            return
        }

        store.performHomebrewUpdate(for: fdItem)

        await waitUntil {
            store.isHomebrewItemUpdateFailed(fdItem)
        }
        XCTAssertTrue(store.isHomebrewItemUpdateFailed(fdItem))
        XCTAssertFalse(store.isUpdatingHomebrewItem(fdItem))

        await waitUntil {
            store.refreshErrorMessage == "Homebrew update failed for fd."
        }
    }

    func testPerformUpdateHomebrewFallbackWithoutMatchingItemShowsLiveProgressRing() async {
        let phase = PhaseBox()
        let appV1 = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Notion.app"),
            displayName: "Notion",
            bundleIdentifier: "notion.id",
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let appV2 = AppRecord(
            bundleURL: appV1.bundleURL,
            displayName: appV1.displayName,
            bundleIdentifier: appV1.bundleIdentifier,
            localVersion: Version("2.0"),
            sourceHint: appV1.sourceHint,
            sparkleFeedURL: appV1.sparkleFeedURL
        )
        let caskEntry = HomebrewCaskEntry(
            token: "notion-beta",
            version: Version("2.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion-beta"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in phase.value == 0 ? [appV1] : [appV2] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                HomebrewCaskIndex(
                    byBundleIdentifier: [:],
                    byAppBundleName: ["notion.app": [caskEntry]]
                )
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                let client = HomebrewCaskClient()
                return await client.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewUpgradeWithEvents: { token, onEvent in
                let command = ["upgrade", "--cask", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "==> Downloading \(token)"))
                try? await Task.sleep(nanoseconds: 40_000_000)
                onEvent(.outputLine(command: command, line: "==> Installing Cask \(token)"))
                try? await Task.sleep(nanoseconds: 40_000_000)
                onEvent(.outputLine(command: command, line: "==> Purging files for version 1.0 of Cask \(token)"))
                onEvent(.commandFinished(command: command, success: true))
                phase.value = 1
                return true
            },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertEqual(store.update(for: appV1)?.source, .homebrew)
        XCTAssertEqual(store.update(for: appV1)?.homebrewToken, "notion-beta")
        XCTAssertNil(store.uninstallableHomebrewItem(for: appV1))

        store.performUpdate(for: appV1)
        XCTAssertTrue(store.isUpdatingApp(appV1))

        await waitUntil({
            (store.appUpdateProgress(for: appV1) ?? 0) > 0
        })

        await waitUntil {
            !store.isUpdatingApp(appV1) && !store.isRefreshing
        }
        XCTAssertFalse(store.isUpdatingApp(appV1))
        XCTAssertFalse(store.isAppUpdateFailed(appV1))
    }

    func testHomebrewDiscoverItemsAppearWhenSearchIsNonEmpty() async {
        let entry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["notion.app": [entry]]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { index },
            lookupHomebrew: { _, _, _, _ in nil },
            searchHomebrewCasks: { index, query, excluded in
                let client = HomebrewCaskClient()
                return await client.searchCasks(query: query, in: index, excludingTokens: excluded)
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertTrue(store.displayedHomebrewDiscoverItems.isEmpty)

        store.searchText = "notion"
        await waitUntil({ !store.displayedHomebrewDiscoverItems.isEmpty })
        XCTAssertEqual(store.displayedHomebrewDiscoverItems.first?.token, "notion")
    }

    func testHomebrewDiscoverIncludesFormulaMatches() async {
        let formula = HomebrewFormulaEntry(
            token: "ripgrep",
            version: Version("14.1.0"),
            homepageURL: URL(string: "https://github.com/BurntSushi/ripgrep"),
            description: "Recursively search directories for regex patterns"
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { HomebrewFormulaIndex(byToken: ["ripgrep": formula]) },
            lookupHomebrew: { _, _, _, _ in nil },
            searchHomebrewFormulae: { index, query, excluded in
                let client = HomebrewFormulaClient()
                return await client.searchFormulae(query: query, in: index, excludingTokens: excluded)
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        store.searchText = "rip"
        await waitUntil({
            store.displayedHomebrewDiscoverItems.contains(where: { $0.token == "ripgrep" && $0.kind == .formula })
        })
    }

    func testOpenHomebrewDiscoverItemOpensHomepageURL() {
        let externalOpenCalls = URLCallsBox()
        let entryURL = URL(string: "https://formulae.brew.sh/cask/notion")
        let entry = HomebrewCaskDiscoveryItem(
            kind: .cask,
            token: "notion",
            displayName: "notion",
            version: Version("7.9.0"),
            homepageURL: entryURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        XCTAssertTrue(store.canOpenHomebrewDiscoverItem(entry))
        store.openHomebrewDiscoverItem(entry)
        XCTAssertEqual(
            externalOpenCalls.snapshot().map(\.absoluteString),
            ["https://formulae.brew.sh/cask/notion"]
        )
    }

    func testOpenHomebrewDiscoverItemWithoutHomepageURLDoesNothing() {
        let externalOpenCalls = URLCallsBox()
        let entry = HomebrewCaskDiscoveryItem(
            kind: .formula,
            token: "ripgrep",
            displayName: "ripgrep",
            version: Version("14.1.0"),
            homepageURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        XCTAssertFalse(store.canOpenHomebrewDiscoverItem(entry))
        store.openHomebrewDiscoverItem(entry)
        XCTAssertTrue(externalOpenCalls.snapshot().isEmpty)
    }

    func testInstalledFormulaRemainsNonOpenableFromIconAction() async {
        let externalOpenCalls = URLCallsBox()
        let appOpenCalls = URLCallsBox()
        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                [
                    HomebrewManagedItem(
                        token: "ripgrep",
                        name: "ripgrep",
                        kind: .formula,
                        installedVersion: Version("14.1.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            },
            openAppBundle: { bundleURL in
                appOpenCalls.append(bundleURL)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        guard let formula = store.homebrewInstalledItems.first(where: { $0.kind == .formula }) else {
            XCTFail("Expected installed formula item.")
            return
        }

        XCTAssertFalse(store.canOpenHomebrewItem(formula))
        store.openHomebrewItem(formula)
        XCTAssertTrue(externalOpenCalls.snapshot().isEmpty)
        XCTAssertTrue(appOpenCalls.snapshot().isEmpty)
    }

    func testPerformHomebrewInstallRunsInstallAndRefreshesDiscovery() async {
        let installCalls = HomebrewUpgradeCallsBox()
        let phase = PhaseBox()
        let entry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["notion.app": [entry]]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 120_000_000)
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { index },
            lookupHomebrew: { _, _, _, _ in nil },
            searchHomebrewCasks: { index, query, excluded in
                let client = HomebrewCaskClient()
                return await client.searchCasks(query: query, in: index, excludingTokens: excluded)
            },
            fetchHomebrewInventory: {
                if phase.value == 0 {
                    return []
                }
                return [
                    HomebrewManagedItem(
                        token: "notion",
                        name: "notion",
                        kind: .cask,
                        installedVersion: Version("7.9.0"),
                        latestVersion: nil,
                        isOutdated: false
                    )
                ]
            },
            checkHomebrewInstalled: { true },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskInstallWithEvents: { token, onEvent in
                await installCalls.append(token)
                let command = ["install", "--cask", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "==> Downloading \(token)"))
                onEvent(.outputLine(command: command, line: "==> Installing Cask \(token)"))
                onEvent(.commandFinished(command: command, success: true))
                phase.value = 1
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        store.searchText = "notion"
        await waitUntil({ !store.displayedHomebrewDiscoverItems.isEmpty })
        guard let item = store.displayedHomebrewDiscoverItems.first else {
            XCTFail("Expected discover item for notion.")
            return
        }

        store.performHomebrewInstall(for: item)
        await waitUntil({ store.isHomebrewDiscoverItemInstalledPendingRefresh(item) })
        await waitUntilRefreshFinishes(store)
        await waitUntil({ store.displayedHomebrewDiscoverItems.isEmpty })

        let calls = await installCalls.snapshot()
        XCTAssertEqual(calls, ["notion"])
    }

    func testPerformHomebrewInstallFailureSetsFailedStateAndErrorMessage() async {
        let installCalls = HomebrewUpgradeCallsBox()
        let entry = HomebrewCaskDiscoveryItem(
            kind: .cask,
            token: "notion",
            displayName: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion")
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkHomebrewInstalled: { true },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskInstallWithEvents: { token, onEvent in
                await installCalls.append(token)
                let command = ["install", "--cask", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "Error: \(token): failed to download resource"))
                onEvent(.commandFinished(command: command, success: false))
                return false
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewInstall(for: entry)
        await waitUntil({ store.isHomebrewDiscoverItemInstallFailed(entry) })

        let calls = await installCalls.snapshot()
        XCTAssertEqual(calls, ["notion"])
        XCTAssertTrue((store.refreshErrorMessage ?? "").contains("Homebrew install failed for notion."))
    }

    func testPerformHomebrewInstallRequiresHomebrewAndSkipsInstallCommand() async {
        let installCalls = HomebrewUpgradeCallsBox()
        let entry = HomebrewCaskDiscoveryItem(
            kind: .cask,
            token: "notion",
            displayName: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/notion")
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkHomebrewInstalled: { false },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskInstallWithEvents: { token, _ in
                await installCalls.append(token)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewInstall(for: entry)
        await waitUntil({ store.isHomebrewDiscoverItemInstallFailed(entry) })

        let calls = await installCalls.snapshot()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue((store.refreshErrorMessage ?? "").contains("Homebrew is not installed."))
    }

    func testPerformHomebrewInstallForFormulaUsesFormulaInstallCommand() async {
        let caskInstallCalls = HomebrewUpgradeCallsBox()
        let formulaInstallCalls = HomebrewUpgradeCallsBox()
        let entry = HomebrewCaskDiscoveryItem(
            kind: .formula,
            token: "ripgrep",
            displayName: "ripgrep",
            version: Version("14.1.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/formula/ripgrep")
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            checkHomebrewInstalled: { true },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewCaskInstallWithEvents: { token, _ in
                await caskInstallCalls.append(token)
                return true
            },
            runHomebrewFormulaInstallWithEvents: { token, onEvent in
                await formulaInstallCalls.append(token)
                let command = ["install", token]
                onEvent(.commandStarted(command))
                onEvent(.outputLine(command: command, line: "==> Installing \(token)"))
                onEvent(.commandFinished(command: command, success: true))
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewInstall(for: entry)
        for _ in 0..<60 {
            if (await formulaInstallCalls.snapshot()).count == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        await waitUntilRefreshFinishes(store)

        let caskCalls = await caskInstallCalls.snapshot()
        let formulaCalls = await formulaInstallCalls.snapshot()
        XCTAssertTrue(caskCalls.isEmpty)
        XCTAssertEqual(formulaCalls, ["ripgrep"])
    }

    func testOpenHomebrewDiscoverItemRejectsUnsafeURL() {
        let externalOpenCalls = URLCallsBox()
        let item = HomebrewCaskDiscoveryItem(
            kind: .cask,
            token: "notion",
            displayName: "notion",
            version: Version("1.0.0"),
            homepageURL: URL(string: "http://example.com/notion")
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true },
            openExternalURL: { url in
                externalOpenCalls.append(url)
            }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.openHomebrewDiscoverItem(item)

        XCTAssertTrue(externalOpenCalls.snapshot().isEmpty)
        XCTAssertTrue((store.refreshErrorMessage ?? "").localizedCaseInsensitiveContains("blocked"))
    }

    func testPerformHomebrewUpdateRejectsInvalidTokenBeforeDispatch() async {
        let homebrewItemCalls = HomebrewCallsBox()
        let item = HomebrewManagedItem(
            token: "--bad-token",
            name: "bad",
            kind: .cask,
            installedVersion: Version("1.0.0"),
            latestVersion: Version("1.1.0"),
            isOutdated: true
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [item] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { kind, token in
                await homebrewItemCalls.append(kind, token)
                return true
            },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.performHomebrewUpdate(for: item)

        let calls = await homebrewItemCalls.snapshot()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue((store.refreshErrorMessage ?? "").localizedCaseInsensitiveContains("unsafe homebrew token"))
    }

    func testAutoRefreshPreferencePersistsAcrossRelaunch() {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let store = UpdateStore(dependencies: .live, defaults: defaults)
        store.autoRefreshEnabled = false
        store.flushPendingPersistenceForTesting()

        let rehydrated = UpdateStore(dependencies: .live, defaults: defaults)

        XCTAssertFalse(rehydrated.autoRefreshEnabled)
    }

    func testHomebrewMaintenanceCommandSequenceMatchesExpectedOrder() {
        XCTAssertEqual(
            UpdateStoreDependencies.homebrewMaintenanceCommandSequence,
            [
                ["update"],
                ["upgrade"],
                ["upgrade", "--cask", "--greedy"],
                ["autoremove"],
                ["cleanup"]
            ]
        )
    }

    func testLightweightRefreshUsesFreshCachesAndSkipsExpensiveDependencies() async {
        let scanCalls = CounterBox()
        let fetchHomebrewIndexCalls = CounterBox()
        let fetchHomebrewFormulaIndexCalls = CounterBox()
        let fetchHomebrewInventoryCalls = CounterBox()
        let appStoreLookupCalls = CounterBox()
        let sparkleLookupCalls = CounterBox()
        let homebrewLookupCalls = CounterBox()
        let now = DateBox(Date(timeIntervalSince1970: 1_700_000_000))

        let appStoreApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Store.app"),
            displayName: "Store",
            bundleIdentifier: "com.example.store",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let sparkleApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Sparkle.app"),
            displayName: "Sparkle",
            bundleIdentifier: "com.example.sparkle",
            localVersion: Version("1.0"),
            sourceHint: .sparkle,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml")
        )
        let homebrewApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/HomebrewOnly.app"),
            displayName: "HomebrewOnly",
            bundleIdentifier: nil,
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let homebrewEntry = HomebrewCaskEntry(
            token: "homebrew-only",
            version: Version("2.0"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/homebrew-only"),
            bundleIdentifiers: [],
            appBundleNames: ["homebrewonly.app"]
        )
        let homebrewIndex = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["homebrewonly.app": [homebrewEntry]]
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                await scanCalls.increment()
                return [appStoreApp, sparkleApp, homebrewApp]
            },
            lookupAppStore: { bundleIdentifier, _ in
                await appStoreLookupCalls.increment()
                guard bundleIdentifier == "com.example.store" else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-store"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in
                await sparkleLookupCalls.increment()
                return SparkleLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://example.com/sparkle-download"),
                    releaseNotesURL: nil,
                    releaseDate: nil
                )
            },
            fetchHomebrewIndex: {
                await fetchHomebrewIndexCalls.increment()
                return homebrewIndex
            },
            fetchHomebrewFormulaIndex: {
                await fetchHomebrewFormulaIndexCalls.increment()
                return HomebrewFormulaIndex(byToken: [:])
            },
            lookupHomebrew: { _, _, appBundleName, _ in
                await homebrewLookupCalls.increment()
                guard appBundleName.lowercased() == "homebrewonly.app" else { return nil }
                return HomebrewLookupResult(
                    remoteVersion: Version("2.0"),
                    token: "homebrew-only",
                    homepageURL: URL(string: "https://formulae.brew.sh/cask/homebrew-only")
                )
            },
            fetchHomebrewInventory: {
                await fetchHomebrewInventoryCalls.increment()
                return []
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        now.value = now.value.addingTimeInterval(60)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        let scanCallCount = await scanCalls.snapshot()
        let homebrewIndexCallCount = await fetchHomebrewIndexCalls.snapshot()
        let homebrewFormulaIndexCallCount = await fetchHomebrewFormulaIndexCalls.snapshot()
        let homebrewInventoryCallCount = await fetchHomebrewInventoryCalls.snapshot()
        let appStoreLookupCallCount = await appStoreLookupCalls.snapshot()
        let sparkleLookupCallCount = await sparkleLookupCalls.snapshot()
        let homebrewLookupCallCount = await homebrewLookupCalls.snapshot()

        XCTAssertEqual(scanCallCount, 2)
        XCTAssertEqual(homebrewIndexCallCount, 1)
        XCTAssertEqual(homebrewFormulaIndexCallCount, 1)
        XCTAssertEqual(homebrewInventoryCallCount, 1)
        XCTAssertEqual(appStoreLookupCallCount, 2)
        XCTAssertEqual(sparkleLookupCallCount, 1)
        XCTAssertEqual(homebrewLookupCallCount, 1)
    }

    func testSparkleCacheTreatsCaseDistinctFeedURLsAsSeparateEntries() async {
        let now = DateBox(Date(timeIntervalSince1970: 1_700_025_000))
        let sparkleLookupCalls = CounterBox()
        let upperFeedURL = URL(string: "https://example.com/Stable.xml?channel=Beta")!
        let lowerFeedURL = URL(string: "https://example.com/stable.xml?channel=Beta")!

        let upperApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SparkleUpper.app"),
            displayName: "Sparkle Upper",
            bundleIdentifier: nil,
            localVersion: Version("1.0"),
            sourceHint: .sparkle,
            sparkleFeedURL: upperFeedURL
        )
        let lowerApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/SparkleLower.app"),
            displayName: "Sparkle Lower",
            bundleIdentifier: nil,
            localVersion: Version("1.0"),
            sourceHint: .sparkle,
            sparkleFeedURL: lowerFeedURL
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                [upperApp, lowerApp]
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            lookupSparkleOutcome: { feedURL, _ in
                await sparkleLookupCalls.increment()
                switch feedURL.absoluteString {
                case upperFeedURL.absoluteString:
                    return .completed(value: SparkleLookupResult(
                        remoteVersion: Version("2.0"),
                        updateURL: URL(string: "https://example.com/download-upper"),
                        releaseNotesURL: nil,
                        releaseDate: nil
                    ))
                case lowerFeedURL.absoluteString:
                    return .completed(value: SparkleLookupResult(
                        remoteVersion: Version("3.0"),
                        updateURL: URL(string: "https://example.com/download-lower"),
                        releaseNotesURL: nil,
                        releaseDate: nil
                    ))
                default:
                    return .completed(value: nil)
                }
            },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let sparkleCallsAfterFullRefresh = await sparkleLookupCalls.snapshot()
        XCTAssertEqual(sparkleCallsAfterFullRefresh, 2)
        XCTAssertEqual(store.updatesByAppID[upperApp.id]?.source, .sparkle)
        XCTAssertEqual(store.updatesByAppID[lowerApp.id]?.source, .sparkle)
        XCTAssertEqual(store.updatesByAppID[upperApp.id]?.remoteVersion, Version("2.0"))
        XCTAssertEqual(store.updatesByAppID[lowerApp.id]?.remoteVersion, Version("3.0"))

        now.value = now.value.addingTimeInterval(60)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        let sparkleCallsAfterLightweightRefresh = await sparkleLookupCalls.snapshot()
        XCTAssertEqual(sparkleCallsAfterLightweightRefresh, 2)
    }

    func testLightweightRefreshRetriesTransientLookupFailuresWithoutCachingNil() async {
        let phase = PhaseBox()
        let now = DateBox(Date(timeIntervalSince1970: 1_700_050_000))
        let appStoreLookupCalls = CounterBox()
        let sparkleLookupCalls = CounterBox()
        let homebrewLookupCalls = CounterBox()

        let appStoreApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Store.app"),
            displayName: "Store",
            bundleIdentifier: "com.example.store",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let sparkleApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Sparkle.app"),
            displayName: "Sparkle",
            bundleIdentifier: nil,
            localVersion: Version("1.0"),
            sourceHint: .sparkle,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml")
        )
        let homebrewApp = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/BrewTool.app"),
            displayName: "BrewTool",
            bundleIdentifier: nil,
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                [appStoreApp, sparkleApp, homebrewApp]
            },
            lookupAppStore: { _, _ in nil },
            lookupAppStoreOutcome: { bundleIdentifier, _ in
                await appStoreLookupCalls.increment()
                guard bundleIdentifier == "com.example.store" else {
                    return .completed(value: nil)
                }
                guard phase.value > 0 else {
                    return .transientFailure
                }
                return .completed(value: AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-store"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                ))
            },
            lookupSparkle: { _, _ in nil },
            lookupSparkleOutcome: { _, _ in
                await sparkleLookupCalls.increment()
                guard phase.value > 0 else {
                    return .transientFailure
                }
                return .completed(value: SparkleLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://example.com/sparkle-download"),
                    releaseNotesURL: nil,
                    releaseDate: nil
                ))
            },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            lookupHomebrewOutcome: { _, _, appBundleName, _ in
                await homebrewLookupCalls.increment()
                guard appBundleName.lowercased() == "brewtool.app" else {
                    return .completed(value: nil)
                }
                guard phase.value > 0 else {
                    return .transientFailure
                }
                return .completed(value: HomebrewLookupResult(
                    remoteVersion: Version("2.0"),
                    token: "brew-tool",
                    homepageURL: URL(string: "https://formulae.brew.sh/cask/brew-tool")
                ))
            },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        phase.value = 0
        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        XCTAssertTrue(store.availableApps.isEmpty)

        let appStoreCallsAfterFailure = await appStoreLookupCalls.snapshot()
        let sparkleCallsAfterFailure = await sparkleLookupCalls.snapshot()
        let homebrewCallsAfterFailure = await homebrewLookupCalls.snapshot()
        XCTAssertEqual(appStoreCallsAfterFailure, 1)
        XCTAssertEqual(sparkleCallsAfterFailure, 1)
        XCTAssertEqual(homebrewCallsAfterFailure, 3)

        phase.value = 1
        now.value = now.value.addingTimeInterval(60)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        XCTAssertEqual(store.updatesByAppID[appStoreApp.id]?.source, .appStore)
        XCTAssertEqual(store.updatesByAppID[sparkleApp.id]?.source, .sparkle)
        XCTAssertEqual(store.updatesByAppID[homebrewApp.id]?.source, .homebrew)
        XCTAssertEqual(Set(store.availableApps.map(\.displayName)), Set(["Store", "Sparkle", "BrewTool"]))

        let appStoreCalls = await appStoreLookupCalls.snapshot()
        let sparkleCalls = await sparkleLookupCalls.snapshot()
        let homebrewCalls = await homebrewLookupCalls.snapshot()
        XCTAssertEqual(appStoreCalls, 2)
        XCTAssertEqual(sparkleCalls, 2)
        XCTAssertEqual(homebrewCalls, 4)
    }

    func testFullRefreshBypassesFreshCachesAndRefetchesAllSources() async {
        let scanCalls = CounterBox()
        let fetchHomebrewIndexCalls = CounterBox()
        let fetchHomebrewFormulaIndexCalls = CounterBox()
        let fetchHomebrewInventoryCalls = CounterBox()
        let appStoreLookupCalls = CounterBox()
        let now = DateBox(Date(timeIntervalSince1970: 1_700_100_000))

        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Store.app"),
            displayName: "Store",
            bundleIdentifier: "com.example.store",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                await scanCalls.increment()
                return [app]
            },
            lookupAppStore: { _, _ in
                await appStoreLookupCalls.increment()
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-store"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                await fetchHomebrewIndexCalls.increment()
                return .empty
            },
            fetchHomebrewFormulaIndex: {
                await fetchHomebrewFormulaIndexCalls.increment()
                return .empty
            },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                await fetchHomebrewInventoryCalls.increment()
                return []
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let scanCallCount = await scanCalls.snapshot()
        let homebrewIndexCallCount = await fetchHomebrewIndexCalls.snapshot()
        let homebrewFormulaIndexCallCount = await fetchHomebrewFormulaIndexCalls.snapshot()
        let homebrewInventoryCallCount = await fetchHomebrewInventoryCalls.snapshot()
        let appStoreLookupCallCount = await appStoreLookupCalls.snapshot()

        XCTAssertEqual(scanCallCount, 2)
        XCTAssertEqual(homebrewIndexCallCount, 2)
        XCTAssertEqual(homebrewFormulaIndexCallCount, 2)
        XCTAssertEqual(homebrewInventoryCallCount, 2)
        XCTAssertEqual(appStoreLookupCallCount, 2)
    }

    func testFullRefreshStartsIndependentFetchesBeforeScanCompletes() async throws {
        let timeline = RefreshTimelineBox()

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                try? await Task.sleep(nanoseconds: 250_000_000)
                await timeline.markScanFinished()
                return []
            },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                await timeline.markHomebrewIndexStarted()
                return .empty
            },
            fetchHomebrewFormulaIndex: {
                await timeline.markHomebrewFormulaIndexStarted()
                return .empty
            },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                await timeline.markHomebrewInventoryStarted()
                return []
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let snapshot = await timeline.snapshot()
        let scanFinishedAt = try XCTUnwrap(snapshot.scanFinishedAt)
        let homebrewIndexStartedAt = try XCTUnwrap(snapshot.homebrewIndexStartedAt)
        let homebrewFormulaIndexStartedAt = try XCTUnwrap(snapshot.homebrewFormulaIndexStartedAt)
        let homebrewInventoryStartedAt = try XCTUnwrap(snapshot.homebrewInventoryStartedAt)

        XCTAssertLessThan(homebrewIndexStartedAt, scanFinishedAt)
        XCTAssertLessThan(homebrewFormulaIndexStartedAt, scanFinishedAt)
        XCTAssertLessThan(homebrewInventoryStartedAt, scanFinishedAt)
    }

    func testRefreshCacheTTLExpiresAfterFifteenMinutes() async {
        let scanCalls = CounterBox()
        let fetchHomebrewIndexCalls = CounterBox()
        let fetchHomebrewFormulaIndexCalls = CounterBox()
        let fetchHomebrewInventoryCalls = CounterBox()
        let appStoreLookupCalls = CounterBox()
        let now = DateBox(Date(timeIntervalSince1970: 1_700_200_000))

        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Store.app"),
            displayName: "Store",
            bundleIdentifier: "com.example.store",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in
                await scanCalls.increment()
                return [app]
            },
            lookupAppStore: { _, _ in
                await appStoreLookupCalls.increment()
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-store"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                await fetchHomebrewIndexCalls.increment()
                return .empty
            },
            fetchHomebrewFormulaIndex: {
                await fetchHomebrewFormulaIndexCalls.increment()
                return .empty
            },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                await fetchHomebrewInventoryCalls.increment()
                return []
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        now.value = now.value.addingTimeInterval((15 * 60) - 1)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        let indexCallsBeforeExpiry = await fetchHomebrewIndexCalls.snapshot()
        let formulaCallsBeforeExpiry = await fetchHomebrewFormulaIndexCalls.snapshot()
        let inventoryCallsBeforeExpiry = await fetchHomebrewInventoryCalls.snapshot()
        let appStoreCallsBeforeExpiry = await appStoreLookupCalls.snapshot()

        XCTAssertEqual(indexCallsBeforeExpiry, 1)
        XCTAssertEqual(formulaCallsBeforeExpiry, 1)
        XCTAssertEqual(inventoryCallsBeforeExpiry, 1)
        XCTAssertEqual(appStoreCallsBeforeExpiry, 1)

        now.value = now.value.addingTimeInterval((15 * 60) + 1)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        let scanCallCount = await scanCalls.snapshot()
        let homebrewIndexCallCount = await fetchHomebrewIndexCalls.snapshot()
        let homebrewFormulaIndexCallCount = await fetchHomebrewFormulaIndexCalls.snapshot()
        let homebrewInventoryCallCount = await fetchHomebrewInventoryCalls.snapshot()
        let appStoreLookupCallCount = await appStoreLookupCalls.snapshot()

        XCTAssertEqual(scanCallCount, 3)
        XCTAssertEqual(homebrewIndexCallCount, 2)
        XCTAssertEqual(homebrewFormulaIndexCallCount, 2)
        XCTAssertEqual(homebrewInventoryCallCount, 2)
        XCTAssertEqual(appStoreLookupCallCount, 2)
    }

    func testLightweightRefreshDoesNotExtendTTLWhenUsingCachedHomebrewData() async {
        let fetchHomebrewIndexCalls = CounterBox()
        let fetchHomebrewFormulaIndexCalls = CounterBox()
        let fetchHomebrewInventoryCalls = CounterBox()
        let now = DateBox(Date(timeIntervalSince1970: 1_700_400_000))

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [] },
            lookupAppStore: { _, _ in nil },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: {
                await fetchHomebrewIndexCalls.increment()
                return .empty
            },
            fetchHomebrewFormulaIndex: {
                await fetchHomebrewFormulaIndexCalls.increment()
                return .empty
            },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: {
                await fetchHomebrewInventoryCalls.increment()
                return []
            },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        for _ in 0..<16 {
            now.value = now.value.addingTimeInterval(60)
            store.refreshNow(lightweight: true)
            await waitUntilRefreshFinishes(store)
        }

        let homebrewIndexCallCount = await fetchHomebrewIndexCalls.snapshot()
        let homebrewFormulaIndexCallCount = await fetchHomebrewFormulaIndexCalls.snapshot()
        let homebrewInventoryCallCount = await fetchHomebrewInventoryCalls.snapshot()

        XCTAssertEqual(homebrewIndexCallCount, 2)
        XCTAssertEqual(homebrewFormulaIndexCallCount, 2)
        XCTAssertEqual(homebrewInventoryCallCount, 2)
    }

    func testCachedLightweightRefreshKeepsVisibleSectionOutputParity() async {
        let now = DateBox(Date(timeIntervalSince1970: 1_700_300_000))
        let alpha = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
            displayName: "Alpha",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let beta = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Beta.app"),
            displayName: "Beta",
            bundleIdentifier: "com.example.beta",
            localVersion: Version("1.0"),
            sourceHint: .unknown,
            sparkleFeedURL: nil
        )
        let gamma = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Gamma.app"),
            displayName: "Gamma",
            bundleIdentifier: "com.example.gamma",
            localVersion: Version("1.0"),
            sourceHint: .sparkle,
            sparkleFeedURL: URL(string: "https://example.com/gamma-appcast.xml")
        )
        let outdatedFormula = HomebrewManagedItem(
            token: "ripgrep",
            name: "ripgrep",
            kind: .formula,
            installedVersion: Version("14.0.0"),
            latestVersion: Version("14.1.0"),
            isOutdated: true
        )
        let installedCask = HomebrewManagedItem(
            token: "notion",
            name: "notion",
            kind: .cask,
            installedVersion: Version("1.0"),
            latestVersion: nil,
            isOutdated: false
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [alpha, beta, gamma] },
            lookupAppStore: { bundleIdentifier, _ in
                guard bundleIdentifier == "com.example.alpha" else { return nil }
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in
                SparkleLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://example.com/gamma-download"),
                    releaseNotesURL: nil,
                    releaseDate: nil
                )
            },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [outdatedFormula, installedCask] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now.value }
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)
        store.toggleIgnored(for: alpha)
        store.toggleIgnored(for: installedCask)
        store.searchText = "a"

        let before = visibleSectionSnapshot(for: store)

        now.value = now.value.addingTimeInterval(60)
        store.refreshNow(lightweight: true)
        await waitUntilRefreshFinishes(store)

        let after = visibleSectionSnapshot(for: store)
        XCTAssertEqual(after, before)
    }

    func testSnapshotPersistenceCoalescesWritesAndSkipsUnchangedPayloads() async {
        let defaults = UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        let persistCalls = HomebrewRunBox()
        let store = UpdateStore(
            dependencies: .live,
            defaults: defaults,
            onSnapshotPersist: { _ in
                persistCalls.runCount += 1
            }
        )

        store.showInstalledAppsSection = false
        store.showIgnoredAppsSection = false
        store.autoRefreshEnabled = false

        try? await Task.sleep(nanoseconds: 350_000_000)
        store.flushPendingPersistenceForTesting()
        let writesAfterBurst = persistCalls.runCount
        XCTAssertGreaterThanOrEqual(writesAfterBurst, 1)
        XCTAssertLessThan(writesAfterBurst, 3)

        store.flushPendingPersistenceForTesting()
        XCTAssertEqual(persistCalls.runCount, writesAfterBurst)

        let rehydrated = UpdateStore(dependencies: .live, defaults: defaults)
        XCTAssertFalse(rehydrated.showInstalledAppsSection)
        XCTAssertFalse(rehydrated.showIgnoredAppsSection)
        XCTAssertFalse(rehydrated.autoRefreshEnabled)

        store.flushPendingPersistenceForTesting()
        XCTAssertEqual(persistCalls.runCount, writesAfterBurst)

        store.showIgnoredHomebrewSection = false
        store.flushPendingPersistenceForTesting()
        XCTAssertEqual(persistCalls.runCount, writesAfterBurst + 1)
    }

    func testRefreshMemoizesEquivalentAppStoreLookupsWithinSingleCycle() async {
        let appStoreLookupCalls = CounterBox()
        let alphaA = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha A.app"),
            displayName: "Alpha A",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let alphaB = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Alpha B.app"),
            displayName: "Alpha B",
            bundleIdentifier: "com.example.alpha",
            localVersion: Version("1.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )

        let deps = UpdateStoreDependencies(
            scanApplications: { _ in [alphaA, alphaB] },
            lookupAppStore: { _, _ in
                await appStoreLookupCalls.increment()
                return AppStoreLookupResult(
                    remoteVersion: Version("2.0"),
                    updateURL: URL(string: "https://apps.apple.com/app/id-alpha"),
                    releaseNotesSummary: nil,
                    releaseDate: nil
                )
            },
            lookupSparkle: { _, _ in nil },
            fetchHomebrewIndex: { .empty },
            fetchHomebrewFormulaIndex: { .empty },
            lookupHomebrew: { _, _, _, _ in nil },
            fetchHomebrewInventory: { [] },
            runHomebrewUpgrade: { _ in true },
            runHomebrewItemUpgrade: { _, _ in true },
            runHomebrewMaintenanceCycle: { true }
        )

        let store = UpdateStore(
            dependencies: deps,
            defaults: UserDefaults(suiteName: "UpdateStoreTests-\(UUID().uuidString)") ?? .standard
        )

        store.refreshNow()
        await waitUntilRefreshFinishes(store)

        let appStoreLookupCallCount = await appStoreLookupCalls.snapshot()
        XCTAssertEqual(appStoreLookupCallCount, 1)
        XCTAssertEqual(store.availableApps.count, 2)
    }

    private func visibleSectionSnapshot(for store: UpdateStore) -> VisibleSectionSnapshot {
        VisibleSectionSnapshot(
            availableAppIDs: store.availableApps.map(\.id),
            installedAppIDs: store.installedApps.map(\.id),
            recentlyUpdatedAppIDs: store.recentlyUpdatedApps.map(\.id),
            ignoredAppIDs: store.ignoredApps.map(\.id),
            displayedAvailableAppIDs: store.displayedAvailableApps.map(\.id),
            displayedInstalledAppIDs: store.displayedInstalledApps.map(\.id),
            displayedRecentlyUpdatedAppIDs: store.displayedRecentlyUpdatedApps.map(\.id),
            displayedIgnoredAppIDs: store.displayedIgnoredApps.map(\.id),
            homebrewOutdatedItemIDs: store.homebrewOutdatedItems.map(\.id),
            homebrewInstalledItemIDs: store.homebrewInstalledItems.map(\.id),
            homebrewRecentlyUpdatedItemIDs: store.homebrewRecentlyUpdatedItems.map(\.id),
            homebrewIgnoredItemIDs: store.homebrewIgnoredItems.map(\.id),
            displayedHomebrewOutdatedItemIDs: store.displayedHomebrewOutdatedItems.map(\.id),
            displayedHomebrewInstalledItemIDs: store.displayedHomebrewInstalledItems.map(\.id),
            displayedHomebrewRecentlyUpdatedItemIDs: store.displayedHomebrewRecentlyUpdatedItems.map(\.id),
            displayedHomebrewIgnoredItemIDs: store.displayedHomebrewIgnoredItems.map(\.id)
        )
    }

    private func waitUntilRefreshFinishes(_ store: UpdateStore) async {
        let timeout = Date().addingTimeInterval(2.0)
        while store.isRefreshing && Date() < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isRefreshing)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 2.0
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate())
    }
}
