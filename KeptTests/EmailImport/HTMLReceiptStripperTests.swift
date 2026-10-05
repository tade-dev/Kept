import CoreGraphics
import Foundation
import Testing
@testable import Kept

/// Fixture-driven tests for `HTMLReceiptStripper`. New fixtures should
/// live under `KeptTests/Fixtures/EmailReceipts/` and be added to
/// `Fixture.all` below — the tests iterate automatically.
///
/// Assertions are intentionally conservative: we test that the *right*
/// content survives the strip and that the marketing chrome doesn't,
/// but we don't lock line-by-line output. Real emails vary; the
/// extraction layer downstream tolerates variation, and locking a
/// snapshot would make legitimate stripper improvements read as
/// regressions.
@Suite("HTML receipt stripper")
struct HTMLReceiptStripperTests {

    struct Fixture: Sendable {
        var id: String
        var mustContainSubstrings: [String]
        var mustNotContainSubstrings: [String]

        static let all: [Fixture] = [
            Fixture(
                id: "amazon_synthetic",
                mustContainSubstrings: [
                    "Amazon.co.uk",
                    "Sony WH-1000XM5",
                    "£299.99",
                    "20 August 2026"
                ],
                mustNotContainSubstrings: [
                    "Unsubscribe",
                    "unsubscribe",
                    "All rights reserved",
                    "Registered office",
                    "View this email in your browser",
                    "<img",
                    "<style",
                    "<script",
                    "window.__amzn"
                ]
            )
        ]
    }

    // MARK: - Universal invariants

    @Test("output is non-empty for real inputs", arguments: Fixture.all)
    func outputNonEmpty(_ fixture: Fixture) throws {
        let lines = try strip(fixture: fixture)
        #expect(!lines.isEmpty, "\(fixture.id) stripped to nothing")
    }

    @Test("respects the max-characters cap", arguments: Fixture.all)
    func respectsCap(_ fixture: Fixture) throws {
        let lines = try strip(fixture: fixture)
        let total = lines.map(\.text).joined(separator: "\n").count
        #expect(total <= HTMLReceiptStripper.maxCharacters,
                "\(fixture.id) exceeded cap: \(total) chars")
    }

    @Test("no residual HTML tags", arguments: Fixture.all)
    func noResidualTags(_ fixture: Fixture) throws {
        let lines = try strip(fixture: fixture)
        let joined = lines.map(\.text).joined(separator: "\n")
        #expect(!joined.contains("<"), "\(fixture.id) still contains '<'")
        #expect(!joined.contains(">"), "\(fixture.id) still contains '>'")
    }

    @Test("bounding boxes are zero (email has no geometry)", arguments: Fixture.all)
    func zeroBoundingBoxes(_ fixture: Fixture) throws {
        let lines = try strip(fixture: fixture)
        for line in lines {
            #expect(line.boundingBox == .zero,
                    "\(fixture.id): line '\(line.text)' had a non-zero bbox")
        }
    }

    // MARK: - Per-fixture expectations

    @Test("expected content survives", arguments: Fixture.all)
    func expectedContent(_ fixture: Fixture) throws {
        let joined = try strip(fixture: fixture).map(\.text).joined(separator: "\n")
        for needle in fixture.mustContainSubstrings {
            #expect(joined.contains(needle),
                    "\(fixture.id): missing expected substring '\(needle)'")
        }
    }

    @Test("chrome and trackers are stripped", arguments: Fixture.all)
    func chromeStripped(_ fixture: Fixture) throws {
        let joined = try strip(fixture: fixture).map(\.text).joined(separator: "\n")
        for banned in fixture.mustNotContainSubstrings {
            #expect(!joined.contains(banned),
                    "\(fixture.id): banned substring '\(banned)' survived")
        }
    }

    // MARK: - Isolated pipeline probes

    @Test("block tags become newlines")
    func blockTagsBecomeNewlines() {
        let lines = HTMLReceiptStripper.strip("<h1>Hi</h1><p>There</p>")
        #expect(lines.count == 2)
        #expect(lines.first?.text == "Hi")
        #expect(lines.last?.text == "There")
    }

    @Test("table cells stay together as one row")
    func cellsBecomeSpacesInRow() {
        // Minified HTML (no whitespace between tags) — matches how real
        // email clients ship their HTML. td → space keeps item + price
        // on a single line.
        let lines = HTMLReceiptStripper.strip("<table><tr><td>Item</td><td>£9.99</td></tr></table>")
        #expect(lines.count == 1)
        #expect(lines.first?.text == "Item £9.99")
    }

    // MARK: - Reviewer aid

    /// Prints the stripper output for every fixture. Handy when reviewing
    /// this PR — run this test alone and the log is exactly what the
    /// worker will see for each email.
    @Test("dump for review")
    func dumpForReview() throws {
        for fixture in Fixture.all {
            let lines = try strip(fixture: fixture)
            let banner = String(repeating: "─", count: 60)
            print("\n\(banner)\nSTRIPPED: \(fixture.id) (\(lines.count) lines)\n\(banner)")
            for line in lines {
                print(line.text)
            }
        }
    }

    // MARK: - Helper

    private func strip(fixture: Fixture) throws -> [RecognizedLine] {
        let html = try Self.loadFixture(fixture.id)
        return HTMLReceiptStripper.strip(html)
    }

    private static func loadFixture(_ id: String) throws -> String {
        // The synchronized-groups Xcode project doesn't bundle test
        // resources yet, so read straight off the source tree via
        // #filePath. Portable across CI (same repo layout) and local runs.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("EmailReceipts")
            .appendingPathComponent("\(id).html")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
