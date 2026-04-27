import XCTest
@testable import Baseline

final class VersionTests: XCTestCase {
    func testVersionComparisonHandlesMalformedInput() {
        XCTAssertTrue(Version("1.2.10") > Version("1.2.2"))
        XCTAssertTrue(Version("v3-beta") > Version("2"))
        XCTAssertEqual(Version(nil), Version(""))
        XCTAssertTrue(Version("1.0") == Version("1.0.0"))
    }
}
