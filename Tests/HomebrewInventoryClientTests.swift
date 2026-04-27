import Foundation
import XCTest
@testable import Baseline

final class HomebrewInventoryClientTests: XCTestCase {
    private final class BrewExecutableURLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: URL?

        init(_ value: URL?) {
            self.value = value
        }

        func get() -> URL? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: URL?) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    func testBuildInventoryParsesInstalledAndOutdatedFormulaeAndCasks() {
        let formulaOutput = """
        wget 1.21.4
        ripgrep 14.0.2 14.1.0
        """

        let caskOutput = """
        notion 4.0.0
        visual-studio-code 1.96.2
        """

        let outdatedJSON = """
        {
          "formulae": [
            { "name": "ripgrep", "current_version": "14.1.0" }
          ],
          "casks": [
            { "name": "notion", "current_version": "4.1.0" }
          ]
        }
        """

        let parser = HomebrewInventoryParser()
        let inventory = parser.buildInventory(
            formulaVersionsOutput: formulaOutput,
            caskVersionsOutput: caskOutput,
            outdatedJSONData: Data(outdatedJSON.utf8)
        )

        XCTAssertEqual(inventory.count, 4)

        let ripgrep = inventory.first { $0.kind == .formula && $0.token == "ripgrep" }
        XCTAssertNotNil(ripgrep)
        XCTAssertEqual(ripgrep?.installedVersion, Version("14.1.0"))
        XCTAssertEqual(ripgrep?.latestVersion, Version("14.1.0"))
        XCTAssertEqual(ripgrep?.isOutdated, true)

        let notion = inventory.first { $0.kind == .cask && $0.token == "notion" }
        XCTAssertNotNil(notion)
        XCTAssertEqual(notion?.installedVersion, Version("4.0.0"))
        XCTAssertEqual(notion?.latestVersion, Version("4.1.0"))
        XCTAssertEqual(notion?.isOutdated, true)

        let wget = inventory.first { $0.kind == .formula && $0.token == "wget" }
        XCTAssertEqual(wget?.isOutdated, false)
        XCTAssertNil(wget?.latestVersion)
    }

    func testParseOutdatedVersionsHandlesInvalidJSON() {
        let parser = HomebrewInventoryParser()
        let versions = parser.parseOutdatedVersions(from: Data("not-json".utf8))
        XCTAssertTrue(versions.isEmpty)
    }

    func testBuildInventoryIgnoresPlaceholderEpochAndUsesPlausibleReleaseDate() {
        let formulaOutput = ""
        let caskOutput = "cursor 0.50.5"
        let outdatedJSON = """
        {
          "formulae": [],
          "casks": [
            {
              "name": "cursor",
              "current_version": "0.50.6",
              "release_date": 0,
              "updated_at": "2026-03-31T10:11:12Z"
            }
          ]
        }
        """

        let parser = HomebrewInventoryParser()
        let inventory = parser.buildInventory(
            formulaVersionsOutput: formulaOutput,
            caskVersionsOutput: caskOutput,
            outdatedJSONData: Data(outdatedJSON.utf8)
        )

        let cursor = inventory.first { $0.kind == .cask && $0.token == "cursor" }
        XCTAssertNotNil(cursor)
        XCTAssertEqual(cursor?.latestVersion, Version("0.50.6"))
        XCTAssertEqual(cursor?.releaseDate, ISO8601DateFormatter().date(from: "2026-03-31T10:11:12Z"))
    }

    func testBuildInventoryMergesFormulaOutdatedAndGreedyCaskOutdatedSources() {
        let formulaOutput = "ripgrep 14.0.2"
        let caskOutput = "cursor 3.0.4,abc123"

        let formulaOutdatedJSON = """
        {
          "formulae": [
            { "name": "ripgrep", "current_version": "14.1.0" }
          ],
          "casks": []
        }
        """

        let caskOutdatedGreedyJSON = """
        {
          "formulae": [],
          "casks": [
            { "name": "cursor", "current_version": "3.0.6,def456" }
          ]
        }
        """

        let parser = HomebrewInventoryParser()
        let inventory = parser.buildInventory(
            formulaVersionsOutput: formulaOutput,
            caskVersionsOutput: caskOutput,
            formulaOutdatedJSONData: Data(formulaOutdatedJSON.utf8),
            caskOutdatedJSONData: Data(caskOutdatedGreedyJSON.utf8)
        )

        let ripgrep = inventory.first { $0.kind == .formula && $0.token == "ripgrep" }
        XCTAssertEqual(ripgrep?.isOutdated, true)
        XCTAssertEqual(ripgrep?.latestVersion, Version("14.1.0"))

        let cursor = inventory.first { $0.kind == .cask && $0.token == "cursor" }
        XCTAssertEqual(cursor?.isOutdated, true)
        XCTAssertEqual(cursor?.latestVersion, Version("3.0.6,def456"))
    }

    func testFetchInventoryResolvesBrewExecutableAtCommandTime() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let brewScriptURL = tempDirectory.appendingPathComponent("brew")
        let script = """
        #!/bin/sh
        if [ "$1" = "list" ] && [ "$2" = "--formula" ] && [ "$3" = "--versions" ]; then
          printf 'ripgrep 14.1.0\\n'
        elif [ "$1" = "list" ] && [ "$2" = "--cask" ] && [ "$3" = "--versions" ]; then
          printf 'notion 4.0.0\\n'
        else
          printf '{"formulae":[],"casks":[]}\\n'
        fi
        """
        try script.write(to: brewScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewScriptURL.path)

        let executableURLBox = BrewExecutableURLBox(nil)
        let client = HomebrewInventoryClient(resolveBrewExecutableURL: {
            executableURLBox.get()
        })

        executableURLBox.set(brewScriptURL)

        let inventory = await client.fetchInventory()

        XCTAssertEqual(Set(inventory.map(\.token)), Set(["ripgrep", "notion"]))
    }
}
