import XCTest
@testable import Baseline

final class AppStoreLookupClientTests: XCTestCase {
    func testParseLookupResponseReturnsUpdateWhenRemoteIsNewer() async throws {
        let client = AppStoreLookupClient()
        let data = try FixtureLoader.data(named: "app_store_lookup", ext: "json")

        let result = try await client.parseLookupResponse(data, localVersion: Version("2.0.0"))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.remoteVersion, Version("2.3.1"))
        XCTAssertEqual(result?.updateURL?.absoluteString, "https://apps.apple.com/app/id123456789")
        XCTAssertEqual(result?.appStoreItemID, 123456789)
    }

    func testParseLookupResponseReturnsNilWhenNotNewer() async throws {
        let client = AppStoreLookupClient()
        let data = try FixtureLoader.data(named: "app_store_lookup", ext: "json")

        let result = try await client.parseLookupResponse(data, localVersion: Version("9.0.0"))

        XCTAssertNil(result)
    }

    func testParseLookupResponsePrefersMacCandidateOverIOSCandidate() async throws {
        let client = AppStoreLookupClient()
        let data = """
        {
          "resultCount": 2,
          "results": [
            {
              "kind": "software",
              "trackId": 987654321,
              "version": "10.124.1",
              "trackViewUrl": "https://apps.apple.com/app/id-ios"
            },
            {
              "kind": "mac-software",
              "trackId": 123123123,
              "version": "10.120.1",
              "trackViewUrl": "https://apps.apple.com/app/id-mac"
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try await client.parseLookupResponse(data, localVersion: Version("10.119.0"))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.remoteVersion, Version("10.120.1"))
        XCTAssertEqual(result?.updateURL?.absoluteString, "https://apps.apple.com/app/id-mac")
        XCTAssertEqual(result?.appStoreItemID, 123123123)
    }

    func testParseLookupResponseReturnsNilForIOSOnlyCandidate() async throws {
        let client = AppStoreLookupClient()
        let data = """
        {
          "resultCount": 1,
          "results": [
            {
              "kind": "software",
              "version": "10.124.1",
              "trackViewUrl": "https://apps.apple.com/app/id-ios"
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try await client.parseLookupResponse(data, localVersion: Version("10.120.1"))

        XCTAssertNil(result)
    }

    func testParseLookupResponseRejectsOversizedPayload() async throws {
        let client = AppStoreLookupClient()
        let oversized = Data(repeating: 0x61, count: SecurityPolicy.appStoreLookupMaxBytes + 1)

        let result = try await client.parseLookupResponse(oversized, localVersion: Version("1.0.0"))

        XCTAssertNil(result)
    }
}
