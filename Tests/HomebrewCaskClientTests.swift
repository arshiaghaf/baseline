import XCTest
@testable import Baseline

final class HomebrewCaskClientTests: XCTestCase {
    func testParseIndexHandlesSchemaDrift() async throws {
        let client = HomebrewCaskClient()
        let data = try FixtureLoader.data(named: "homebrew_cask_drift", ext: "json")

        let index = await client.parseIndex(data)

        XCTAssertEqual(index.byBundleIdentifier["com.example.app"]?.token, "example-app")
        XCTAssertEqual(index.byBundleIdentifier["com.alt.one"]?.token, "alt-app")
        XCTAssertEqual(index.byBundleIdentifier["com.alt.two"]?.token, "alt-app")
        XCTAssertEqual(index.byAppBundleName["example.app"]?.first?.token, "example-app")
    }

    func testLookupUpdateReturnsNilWhenCurrentVersionIsNewer() async {
        let client = HomebrewCaskClient()
        let entry = HomebrewCaskEntry(
            token: "example-app",
            version: Version("1.0.0"),
            homepageURL: nil,
            bundleIdentifiers: ["com.example.app"],
            appBundleNames: ["example.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: ["com.example.app": entry],
            byAppBundleName: ["example.app": [entry]]
        )

        let result = await client.lookupUpdate(
            bundleIdentifier: "com.example.app",
            appBundleName: "Example.app",
            localVersion: Version("2.0.0"),
            in: index
        )

        XCTAssertNil(result)
    }

    func testLookupUpdateFallsBackToAppBundleNameWhenBundleIdentifierMissing() async {
        let client = HomebrewCaskClient()
        let entry = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: URL(string: "https://www.notion.so"),
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["notion.app": [entry]]
        )

        let result = await client.lookupUpdate(
            bundleIdentifier: nil,
            appBundleName: "Notion.app",
            localVersion: Version("7.7.1"),
            in: index
        )

        XCTAssertEqual(result?.token, "notion")
        XCTAssertEqual(result?.remoteVersion, Version("7.9.0"))
    }

    func testLookupUpdateDoesNotTreatCommaBuildMetadataAsNewerVersion() async {
        let client = HomebrewCaskClient()
        let data = """
        [
          {
            "token": "chatgpt",
            "version": "1.2026.049,1774576178",
            "artifacts": [
              { "app": ["ChatGPT.app"] }
            ]
          }
        ]
        """.data(using: .utf8)!
        let index = await client.parseIndex(data)

        let result = await client.lookupUpdate(
            bundleIdentifier: nil,
            appBundleName: "ChatGPT.app",
            localVersion: Version("1.2026.049"),
            in: index
        )

        XCTAssertNil(result)
    }

    func testLookupUpdatePrefersExactTokenOverVariantTokens() async {
        let client = HomebrewCaskClient()
        let exact = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let nightly = HomebrewCaskEntry(
            token: "notion@nightly",
            version: Version("8.1.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let fork = HomebrewCaskEntry(
            token: "notion-community",
            version: Version("9.0.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["notion.app": [nightly, fork, exact]]
        )

        let result = await client.lookupUpdate(
            bundleIdentifier: nil,
            appBundleName: "Notion.app",
            localVersion: Version("7.7.1"),
            in: index
        )

        XCTAssertEqual(result?.token, "notion")
        XCTAssertEqual(result?.remoteVersion, Version("7.9.0"))
    }

    func testLookupUpdateMatchesChannelTokensAcrossDifferentSeparators() async {
        let client = HomebrewCaskClient()
        let beta = HomebrewCaskEntry(
            token: "figma@beta",
            version: Version("126.3.6"),
            homepageURL: URL(string: "https://formulae.brew.sh/cask/figma@beta"),
            bundleIdentifiers: [],
            appBundleNames: ["figma beta.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["figma beta.app": [beta]]
        )

        let result = await client.lookupUpdate(
            bundleIdentifier: nil,
            appBundleName: "Figma Beta.app",
            localVersion: Version("126.3.4"),
            in: index
        )

        XCTAssertEqual(result?.token, "figma@beta")
        XCTAssertEqual(result?.remoteVersion, Version("126.3.6"))
    }

    func testLookupUpdateFallsBackToAppBundleCandidatesWhenTokenHintHasNoRelatedMatches() async {
        let client = HomebrewCaskClient()
        let entry = HomebrewCaskEntry(
            token: "totally-unrelated-token",
            version: Version("2.0.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["example.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: ["example.app": [entry]]
        )

        let result = await client.lookupUpdate(
            bundleIdentifier: nil,
            appBundleName: "Example.app",
            localVersion: Version("1.0.0"),
            in: index
        )

        XCTAssertEqual(result?.token, "totally-unrelated-token")
        XCTAssertEqual(result?.remoteVersion, Version("2.0.0"))
    }

    func testSearchCasksReturnsMatchingTokenForQuery() async {
        let client = HomebrewCaskClient()
        let notion = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let obsidian = HomebrewCaskEntry(
            token: "obsidian",
            version: Version("1.8.10"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["obsidian.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: [
                "notion.app": [notion],
                "obsidian.app": [obsidian]
            ]
        )

        let results = await client.searchCasks(
            query: "notion",
            in: index,
            excludingTokens: []
        )

        XCTAssertEqual(results.first?.token, "notion")
    }

    func testSearchCasksPrefersTokenPrefixOverContainsMatches() async {
        let client = HomebrewCaskClient()
        let prefix = HomebrewCaskEntry(
            token: "notion-helper",
            version: Version("3.0.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion helper.app"]
        )
        let containsOnly = HomebrewCaskEntry(
            token: "custom-notion-tools",
            version: Version("4.0.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["custom tools.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: [
                "notion helper.app": [prefix],
                "custom tools.app": [containsOnly]
            ]
        )

        let results = await client.searchCasks(
            query: "notion",
            in: index,
            excludingTokens: []
        )

        XCTAssertGreaterThanOrEqual(results.count, 2)
        XCTAssertEqual(results[0].token, "notion-helper")
    }

    func testSearchCasksExcludesInstalledTokens() async {
        let client = HomebrewCaskClient()
        let notion = HomebrewCaskEntry(
            token: "notion",
            version: Version("7.9.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["notion.app"]
        )
        let figma = HomebrewCaskEntry(
            token: "figma",
            version: Version("126.0.0"),
            homepageURL: nil,
            bundleIdentifiers: [],
            appBundleNames: ["figma.app"]
        )
        let index = HomebrewCaskIndex(
            byBundleIdentifier: [:],
            byAppBundleName: [
                "notion.app": [notion],
                "figma.app": [figma]
            ]
        )

        let results = await client.searchCasks(
            query: "i",
            in: index,
            excludingTokens: ["notion"]
        )

        XCTAssertFalse(results.contains(where: { $0.token == "notion" }))
        XCTAssertTrue(results.contains(where: { $0.token == "figma" }))
    }

    func testParseIndexRejectsOversizedPayload() async {
        let client = HomebrewCaskClient()
        let oversized = Data(repeating: 0x61, count: SecurityPolicy.homebrewIndexMaxBytes + 1)

        let index = await client.parseIndex(oversized)

        XCTAssertTrue(index.byBundleIdentifier.isEmpty)
        XCTAssertTrue(index.byAppBundleName.isEmpty)
    }
}
