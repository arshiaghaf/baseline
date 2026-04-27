import XCTest
@testable import Baseline

final class HomebrewMaintenanceOutputParserTests: XCTestCase {
    func testParsesDownloadInstallCompletionAndFailureEvents() {
        let parser = HomebrewMaintenanceOutputParser(knownTokens: ["fd", "wezterm"])

        XCTAssertEqual(
            parser.parse(
                line: "==> Downloading https://ghcr.io/v2/homebrew/core/fd/blobs/sha256:abc",
                command: ["upgrade"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "fd",
                    kindHint: .formula,
                    kind: .progress(HomebrewMaintenanceProgressStage.downloading.rawValue)
                )
            ]
        )

        XCTAssertEqual(
            parser.parse(
                line: "==> Pouring fd--10.3.0.arm64_bottle.tar.gz",
                command: ["upgrade"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "fd",
                    kindHint: .formula,
                    kind: .progress(HomebrewMaintenanceProgressStage.installing.rawValue)
                )
            ]
        )

        XCTAssertEqual(
            parser.parse(
                line: "==> Purging files for version 1.0.0 of Cask wezterm",
                command: ["upgrade", "--cask", "--greedy"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "wezterm",
                    kindHint: .cask,
                    kind: .completed
                )
            ]
        )

        XCTAssertEqual(
            parser.parse(
                line: "Error: fd: failed to download resource",
                command: ["upgrade"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "fd",
                    kindHint: .formula,
                    kind: .failed
                )
            ]
        )
    }

    func testIgnoresUnknownLinesAndRespectsTokenBoundaries() {
        let parser = HomebrewMaintenanceOutputParser(knownTokens: ["fd", "fd-find"])

        XCTAssertTrue(
            parser.parse(
                line: "Checking if your system is ready...",
                command: ["upgrade"]
            ).isEmpty
        )

        XCTAssertTrue(
            parser.parse(
                line: "prefixfdsuffix",
                command: ["upgrade"]
            ).isEmpty
        )

        XCTAssertEqual(
            parser.parse(
                line: "==> Upgrading fd-find",
                command: ["upgrade"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "fd-find",
                    kindHint: .formula,
                    kind: .progress(HomebrewMaintenanceProgressStage.installing.rawValue)
                )
            ]
        )
    }

    func testParsesSingleCommandCaskStages() {
        let parser = HomebrewMaintenanceOutputParser(knownTokens: ["notion"])

        XCTAssertEqual(
            parser.parse(
                line: "==> Downloading notion",
                command: ["upgrade", "--cask", "notion"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "notion",
                    kindHint: .cask,
                    kind: .progress(HomebrewMaintenanceProgressStage.downloading.rawValue)
                )
            ]
        )

        XCTAssertEqual(
            parser.parse(
                line: "==> Installing Cask notion",
                command: ["upgrade", "--cask", "notion"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "notion",
                    kindHint: .cask,
                    kind: .progress(HomebrewMaintenanceProgressStage.installing.rawValue)
                )
            ]
        )

        XCTAssertEqual(
            parser.parse(
                line: "Error: notion: failed to download resource",
                command: ["upgrade", "--cask", "notion"]
            ),
            [
                HomebrewMaintenanceProgressEvent(
                    token: "notion",
                    kindHint: .cask,
                    kind: .failed
                )
            ]
        )
    }
}
