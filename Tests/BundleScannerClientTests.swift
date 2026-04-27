import Foundation
import XCTest
@testable import Baseline

final class BundleScannerClientTests: XCTestCase {
    func testIncrementalMetadataCacheKeepsOutputEqualToBaselineParser() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BundleScannerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
        try createAppBundle(
            at: appURL,
            infoPlist: [
                "CFBundleDisplayName": "Example",
                "CFBundleIdentifier": "com.example.bundle",
                "CFBundleShortVersionString": "1.0",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )

        let scanner = BundleScannerClient()

        let firstScan = await scanner.scanApplications(in: [root])
        let expectedV1 = baselineRecord(for: appURL)
        XCTAssertEqual(firstScan, [expectedV1])

        let secondScan = await scanner.scanApplications(in: [root])
        XCTAssertEqual(secondScan, [expectedV1])

        try? await Task.sleep(nanoseconds: 50_000_000)

        try writeInfoPlist(
            at: appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist"),
            values: [
                "CFBundleDisplayName": "Example",
                "CFBundleIdentifier": "com.example.bundle",
                "CFBundleShortVersionString": "2.0",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )

        let expectedV2 = baselineRecord(for: appURL)
        let thirdScan = await scanner.scanApplications(in: [root])
        XCTAssertEqual(thirdScan, [expectedV2])
        XCTAssertNotEqual(thirdScan, firstScan)
    }

    func testMetadataCacheInvalidatesWhenMasReceiptStateChanges() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BundleScannerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = root.appendingPathComponent("ReceiptSensitive.app", isDirectory: true)
        try createAppBundle(
            at: appURL,
            infoPlist: [
                "CFBundleDisplayName": "ReceiptSensitive",
                "CFBundleIdentifier": "com.example.receipt-sensitive",
                "CFBundleShortVersionString": "1.0",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )

        let initialBundleModificationDate = try XCTUnwrap(
            appURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        let scanner = BundleScannerClient()
        let firstScan = await scanner.scanApplications(in: [root])
        XCTAssertEqual(firstScan.count, 1)
        XCTAssertEqual(firstScan.first?.sourceHint, .sparkle)

        try writeMasReceipt(for: appURL)
        try fileManager.setAttributes(
            [.modificationDate: initialBundleModificationDate],
            ofItemAtPath: appURL.path
        )

        let secondScan = await scanner.scanApplications(in: [root])
        XCTAssertEqual(secondScan.count, 1)
        XCTAssertEqual(secondScan.first?.sourceHint, .appStore)
    }

    private func createAppBundle(at appURL: URL, infoPlist: [String: Any]) throws {
        let fileManager = FileManager.default
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        try writeInfoPlist(
            at: contentsURL.appendingPathComponent("Info.plist"),
            values: infoPlist
        )
    }

    private func writeInfoPlist(at infoPlistURL: URL, values: [String: Any]) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        try data.write(to: infoPlistURL, options: .atomic)
    }

    private func writeMasReceipt(for appURL: URL) throws {
        let fileManager = FileManager.default
        let receiptDirectoryURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("_MASReceipt", isDirectory: true)
        try fileManager.createDirectory(at: receiptDirectoryURL, withIntermediateDirectories: true)
        let receiptURL = receiptDirectoryURL.appendingPathComponent("receipt")
        try Data("receipt".utf8).write(to: receiptURL, options: .atomic)
    }

    private func baselineRecord(for appURL: URL) -> AppRecord {
        let fileManager = FileManager.default
        let info = (NSDictionary(
            contentsOf: appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
        ) as? [String: Any]) ?? [:]

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let shortVersion = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        let sparkleFeedURL = (info["SUFeedURL"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { url in
                SecurityPolicy.isAllowedFeedURL(url) ? url : nil
            }

        let hasAppStoreReceipt = fileManager.fileExists(
            atPath: appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("_MASReceipt")
                .appendingPathComponent("receipt")
                .path
        )

        let sourceHint: UpdateSource
        if hasAppStoreReceipt {
            sourceHint = .appStore
        } else if sparkleFeedURL != nil {
            sourceHint = .sparkle
        } else {
            sourceHint = .unknown
        }

        return AppRecord(
            bundleURL: appURL,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            localVersion: Version(shortVersion),
            sourceHint: sourceHint,
            sparkleFeedURL: sparkleFeedURL
        )
    }
}
