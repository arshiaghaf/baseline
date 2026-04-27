import XCTest
@testable import Baseline

final class HomebrewFormulaClientTests: XCTestCase {
    func testParseAndSearchReturnsMatchingFormula() async {
        let client = HomebrewFormulaClient()
        let data = """
        [
          {
            "name": "ripgrep",
            "desc": "Recursively search directories for regex patterns",
            "homepage": "https://github.com/BurntSushi/ripgrep",
            "versions": { "stable": "14.1.0" }
          },
          {
            "name": "fd",
            "desc": "Simple, fast and user-friendly alternative to find",
            "homepage": "https://github.com/sharkdp/fd",
            "versions": { "stable": "10.2.0" }
          }
        ]
        """.data(using: .utf8)!

        let index = await client.parseIndex(data)
        let results = await client.searchFormulae(
            query: "rip",
            in: index,
            excludingTokens: []
        )

        XCTAssertEqual(results.first?.kind, .formula)
        XCTAssertEqual(results.first?.token, "ripgrep")
    }

    func testSearchExcludesInstalledFormulaTokens() async {
        let client = HomebrewFormulaClient()
        let data = """
        [
          { "name": "ripgrep", "versions": { "stable": "14.1.0" } },
          { "name": "fd", "versions": { "stable": "10.2.0" } }
        ]
        """.data(using: .utf8)!

        let index = await client.parseIndex(data)
        let results = await client.searchFormulae(
            query: "f",
            in: index,
            excludingTokens: ["fd"]
        )

        XCTAssertFalse(results.contains(where: { $0.token == "fd" }))
    }

    func testParseIndexRejectsOversizedPayload() async {
        let client = HomebrewFormulaClient()
        let oversized = Data(repeating: 0x61, count: SecurityPolicy.homebrewIndexMaxBytes + 1)

        let index = await client.parseIndex(oversized)

        XCTAssertTrue(index.byToken.isEmpty)
    }
}
