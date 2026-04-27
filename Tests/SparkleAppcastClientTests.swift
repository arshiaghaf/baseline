import XCTest
@testable import Baseline

final class SparkleAppcastClientTests: XCTestCase {
    func testParseAppcastUsesLatestVersion() async throws {
        let client = SparkleAppcastClient()
        let data = try FixtureLoader.data(named: "sparkle_appcast", ext: "xml")

        let result = await client.parseAppcast(data, localVersion: Version("1.0.0"))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.remoteVersion, Version("2.0.0"))
        XCTAssertEqual(result?.updateURL?.absoluteString, "https://example.com/download/2.0.0.zip")
    }

    func testParseAppcastReturnsNilWhenNoNewVersion() async throws {
        let client = SparkleAppcastClient()
        let data = try FixtureLoader.data(named: "sparkle_appcast", ext: "xml")

        let result = await client.parseAppcast(data, localVersion: Version("2.0.0"))

        XCTAssertNil(result)
    }

    func testParseAppcastRejectsOversizedPayload() async {
        let client = SparkleAppcastClient()
        let oversized = Data(repeating: 0x61, count: SecurityPolicy.sparkleAppcastMaxBytes + 1)

        let result = await client.parseAppcast(oversized, localVersion: Version("1.0.0"))

        XCTAssertNil(result)
    }

    func testSecureXMLParserDisablesExternalEntityResolution() {
        let parser = SparkleAppcastClient.secureXMLParser(data: Data())
        XCTAssertFalse(parser.shouldResolveExternalEntities)
    }
}
