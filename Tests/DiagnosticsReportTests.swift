import Foundation
import XCTest
@testable import Baseline

@MainActor
final class DiagnosticsReportTests: XCTestCase {
    func testDiagnosticsReportIncludesCountsSourcesAndToolStatus() async {
        let app = AppRecord(
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            displayName: "Example",
            bundleIdentifier: "com.example.app",
            localVersion: Version("1.0.0"),
            sourceHint: .appStore,
            sparkleFeedURL: nil
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = UpdateStore(
            dependencies: UpdateStoreDependencies(
                scanApplications: { _ in [app] },
                lookupAppStore: { _, _ in
                    AppStoreLookupResult(
                        remoteVersion: Version("1.1.0"),
                        updateURL: URL(string: "https://apps.apple.com/app/id1"),
                        releaseNotesSummary: nil,
                        releaseDate: nil,
                        appStoreItemID: 1
                    )
                },
                lookupSparkle: { _, _ in nil },
                fetchHomebrewIndex: { .empty },
                lookupHomebrew: { _, _, _, _ in nil },
                fetchHomebrewInventory: { [] },
                checkMasInstalled: { true },
                checkHomebrewInstalled: { true },
                runHomebrewUpgrade: { _ in true },
                runHomebrewItemUpgrade: { _, _ in true },
                runHomebrewMaintenanceCycle: { true }
            ),
            defaults: UserDefaults(suiteName: "DiagnosticsReportTests-\(UUID().uuidString)") ?? .standard,
            nowProvider: { now }
        )

        store.refreshNow()
        await waitUntil { !store.isRefreshing }
        store.refreshMasSetupStatus()
        await waitUntil { !store.isCheckingMas }

        let report = store.diagnosticsReport()
        let rendered = report.render()

        XCTAssertEqual(report.appCount, 1)
        XCTAssertEqual(report.availableAppCount, 1)
        XCTAssertEqual(report.updateSourceCounts[.appStore], 1)
        XCTAssertTrue(rendered.contains("Baseline Diagnostics"))
        XCTAssertTrue(rendered.contains("App Store: 1"))
        XCTAssertTrue(rendered.contains("mas installed: Yes"))
        XCTAssertTrue(rendered.contains("Homebrew available for helper install: Yes"))
    }

    func testDiagnosticsReportOmitsRawRefreshOutput() {
        let report = BaselineDiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastRefreshDate: nil,
            isRefreshing: false,
            appCount: 0,
            availableAppCount: 0,
            installedAppCount: 0,
            ignoredAppCount: 0,
            recentlyUpdatedAppCount: 0,
            homebrewItemCount: 0,
            homebrewOutdatedCount: 0,
            homebrewInstalledCount: 0,
            homebrewIgnoredCount: 0,
            homebrewRecentlyUpdatedCount: 0,
            updateSourceCounts: [:],
            scanDirectories: [],
            additionalDirectoryCount: 0,
            autoRefreshEnabled: true,
            refreshIntervalMinutes: 60,
            useMasForAppStoreUpdates: true,
            isMasInstalled: false,
            isHomebrewInstalled: false,
            lastRefreshMessage: "Homebrew uninstall failed for ProtonVPN.\n\nError: existing app at /Users/example/Applications/ProtonVPN.app"
        )

        let rendered = report.render()

        XCTAssertTrue(rendered.contains("- Last message: Homebrew uninstall failed for ProtonVPN."))
        XCTAssertFalse(rendered.contains("/Users/example"))
        XCTAssertFalse(rendered.contains("existing app"))
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
