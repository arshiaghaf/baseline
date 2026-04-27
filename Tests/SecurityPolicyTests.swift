import XCTest
@testable import Baseline

final class SecurityPolicyTests: XCTestCase {
    func testExternalURLPolicyAllowsHTTPSOnly() {
        XCTAssertTrue(SecurityPolicy.isAllowedExternalURL(URL(string: "https://example.com")!))
        XCTAssertFalse(SecurityPolicy.isAllowedExternalURL(URL(string: "http://example.com")!))
        XCTAssertFalse(SecurityPolicy.isAllowedExternalURL(URL(string: "file:///tmp/test")!))
        XCTAssertFalse(SecurityPolicy.isAllowedExternalURL(URL(string: "custom-scheme://example.com")!))
    }

    func testFeedURLPolicyRejectsLocalAndPrivateHosts() {
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://localhost/feed.xml")!))
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://127.0.0.1/feed.xml")!))
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://10.0.0.4/feed.xml")!))
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://192.168.1.10/feed.xml")!))
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://[::1]/feed.xml")!))
        XCTAssertFalse(SecurityPolicy.isAllowedFeedURL(URL(string: "https://[fe80::1]/feed.xml")!))
        XCTAssertTrue(SecurityPolicy.isAllowedFeedURL(URL(string: "https://updates.example.com/appcast.xml")!))
    }

    func testHomebrewTokenValidation() {
        XCTAssertTrue(SecurityPolicy.isValidHomebrewToken("notion"))
        XCTAssertTrue(SecurityPolicy.isValidHomebrewToken("figma@beta"))
        XCTAssertTrue(SecurityPolicy.isValidHomebrewToken("python@3.12"))
        XCTAssertTrue(SecurityPolicy.isValidHomebrewToken("owner/repo/formula"))
        XCTAssertTrue(SecurityPolicy.isValidHomebrewToken("homebrew/cask/google-chrome"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("--notion"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("bad token"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("Notion"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("owner//formula"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("/owner/repo/formula"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("owner/repo/formula/"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("Owner/repo/formula"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken("homebrew/cask"))
        XCTAssertFalse(SecurityPolicy.isValidHomebrewToken(" notion"))
    }

    func testResolveExecutableURLRejectsEnvAndResolvesAbsoluteExecutable() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let executableURL = tempDirectory.appendingPathComponent("brew")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolved = SecurityPolicy.resolveExecutableURL(
            candidates: ["/usr/bin/env", executableURL.path]
        )

        XCTAssertEqual(resolved, executableURL)

        let envOnly = SecurityPolicy.resolveExecutableURL(candidates: ["/usr/bin/env"])
        XCTAssertNil(envOnly)
    }
}
