import Foundation
import Testing
@testable import Kept

// MARK: - Scoring

enum FieldOutcome: String, Sendable {
    case correct
    case wrong
    case absent
}

struct FieldScore: Sendable {
    var merchant: FieldOutcome
    var total: FieldOutcome
    var date: FieldOutcome

    var isFullyCorrect: Bool {
        merchant == .correct && total == .correct && date == .correct
    }
}

struct FixtureScore: Sendable {
    var fixtureID: String
    var label: String
    var score: FieldScore
    var extractedMerchant: String
    var extractedTotal: Double
    var extractedDate: String
}

struct FieldTallies: Sendable {
    var correct = 0
    var wrong = 0
    var absent = 0

    mutating func add(_ outcome: FieldOutcome) {
        switch outcome {
        case .correct: correct += 1
        case .wrong: wrong += 1
        case .absent: absent += 1
        }
    }

    var summary: String {
        "\(correct) correct  \(wrong) wrong  \(absent) absent"
    }
}

struct AccuracyReport: Sendable {
    var extractorName: String
    var scores: [FixtureScore]

    var merchant: FieldTallies {
        tallies(\.merchant)
    }

    var total: FieldTallies {
        tallies(\.total)
    }

    var date: FieldTallies {
        tallies(\.date)
    }

    var fullyCorrectCount: Int {
        scores.filter(\.score.isFullyCorrect).count
    }

    private func tallies(_ keyPath: KeyPath<FieldScore, FieldOutcome>) -> FieldTallies {
        var result = FieldTallies()
        for score in scores {
            result.add(score.score[keyPath: keyPath])
        }
        return result
    }

    func printed() -> String {
        var lines: [String] = []
        lines.append("=== Extraction accuracy — \(extractorName) ===")
        lines.append(pad("fixture", 14) + pad("merchant", 10) + pad("total", 10) + pad("date", 10) + "extracted")
        for item in scores {
            let extracted = "m=\(item.extractedMerchant) t=\(item.extractedTotal) d=\(item.extractedDate)"
            lines.append(
                pad(String(item.label.prefix(12)), 14)
                    + pad(item.score.merchant.rawValue, 10)
                    + pad(item.score.total.rawValue, 10)
                    + pad(item.score.date.rawValue, 10)
                    + extracted
            )
        }
        lines.append("---")
        lines.append("merchant  \(merchant.summary)")
        lines.append("total     \(total.summary)")
        lines.append("date      \(date.summary)")
        lines.append(
            "fully correct (merchant+total+date): \(fullyCorrectCount)/\(scores.count)"
        )
        lines.append(
            "type A (absent) = Vision fault · type B (wrong) = parser fault"
        )
        return lines.joined(separator: "\n")
    }

    private func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width - 1)) + " " }
        return text + String(repeating: " ", count: width - text.count)
    }
}

enum ExtractionAccuracyHarness {
    /// Load every `*.json` ReceiptFixture under KeptTests/Fixtures.
    static func loadFixtures() throws -> [ReceiptFixture] {
        let urls = try fixtureURLs()
        let decoder = ReceiptFixture.jsonDecoder
        return try urls.map { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(ReceiptFixture.self, from: data)
        }
        .sorted { $0.id < $1.id }
    }

    static func evaluate(
        fixtures: [ReceiptFixture],
        using extractor: any ExtractionService,
        name: String
    ) async throws -> AccuracyReport {
        var scores: [FixtureScore] = []
        for fixture in fixtures {
            guard let expected = fixture.expected else { continue }
            // Need at least one scored field present in expected.
            guard expected.merchant != nil || expected.total != nil || expected.purchaseDate != nil
            else { continue }

            let result = try await extractor.extract(from: fixture.recognizedLines)
            let score = scoreFixture(fixture: fixture, expected: expected, result: result)
            scores.append(
                FixtureScore(
                    fixtureID: fixture.id,
                    label: fixtureLabel(fixture),
                    score: score,
                    extractedMerchant: result.merchant,
                    extractedTotal: result.price,
                    extractedDate: result.purchaseDate
                )
            )
        }
        return AccuracyReport(extractorName: name, scores: scores)
    }

    static func compare(
        fixtures: [ReceiptFixture],
        lhs: (any ExtractionService, String),
        rhs: (any ExtractionService, String)
    ) async throws -> String {
        let left = try await evaluate(fixtures: fixtures, using: lhs.0, name: lhs.1)
        let right = try await evaluate(fixtures: fixtures, using: rhs.0, name: rhs.1)

        var lines: [String] = []
        lines.append("=== Comparison: \(lhs.1) vs \(rhs.1) ===")
        lines.append("\(padStatic("fixture", 14))\(padStatic(lhs.1, 22))\(rhs.1)")
        let rightByID = Dictionary(uniqueKeysWithValues: right.scores.map { ($0.fixtureID, $0) })
        for leftScore in left.scores {
            let rightScore = rightByID[leftScore.fixtureID]
            let leftCell = abbreviate(leftScore.score)
            let rightCell = rightScore.map { abbreviate($0.score) } ?? "—/—/—"
            lines.append(
                "\(padStatic(String(leftScore.label.prefix(12)), 14))\(padStatic(leftCell, 22))\(rightCell)"
            )
        }
        lines.append("--- legend: merchant/total/date initials (c=correct w=wrong a=absent)")
        lines.append("\(lhs.1): fully \(left.fullyCorrectCount)/\(left.scores.count)")
        lines.append("\(rhs.1): fully \(right.fullyCorrectCount)/\(right.scores.count)")
        lines.append("")
        lines.append(left.printed())
        lines.append("")
        lines.append(right.printed())
        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private static func scoreFixture(
        fixture: ReceiptFixture,
        expected: ExpectedValues,
        result: ExtractedReceipt
    ) -> FieldScore {
        let blob = fixture.ocrLines.map(\.text).joined(separator: "\n")

        let merchant: FieldOutcome
        if let want = expected.merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !want.isEmpty {
            if merchantsMatch(want, result.merchant) {
                merchant = .correct
            } else if merchantPresent(want, in: blob) {
                merchant = .wrong
            } else {
                merchant = .absent
            }
        } else {
            merchant = .correct // not scored
        }

        let total: FieldOutcome
        if let want = expected.total {
            if totalsMatch(want, result.price) {
                total = .correct
            } else if totalPresent(want, in: blob) {
                total = .wrong
            } else {
                total = .absent
            }
        } else {
            total = .correct
        }

        let date: FieldOutcome
        if let want = expected.purchaseDate?.trimmingCharacters(in: .whitespacesAndNewlines), !want.isEmpty {
            if datesMatch(want, result.purchaseDate) {
                date = .correct
            } else if datePresent(want, in: blob) {
                date = .wrong
            } else {
                date = .absent
            }
        } else {
            date = .correct
        }

        return FieldScore(merchant: merchant, total: total, date: date)
    }

    private static func fixtureLabel(_ fixture: ReceiptFixture) -> String {
        if let merchant = fixture.expected?.merchant, !merchant.isEmpty {
            return merchant
        }
        return String(fixture.id.prefix(8))
    }

    private static func fixtureURLs() throws -> [URL] {
        let bundles: [Bundle] = [Bundle(for: BundleFinder.self), .main]
        for bundle in bundles {
            if let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures"),
               !urls.isEmpty {
                return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
            // Flat copy into test bundle root
            if let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil)?
                .filter({
                    (try? Data(contentsOf: $0)).flatMap {
                        try? ReceiptFixture.jsonDecoder.decode(ReceiptFixture.self, from: $0)
                    } != nil
                }),
               !urls.isEmpty {
                return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
        }

        // Source-tree fallback so ⌘U works before resources are copied.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            throw FixtureLoadError.noFixtures(
                "No JSON fixtures in KeptTests/Fixtures. Export from Debug → Capture OCR fixture."
            )
        }
        return urls
    }

    private final class BundleFinder {}

    enum FixtureLoadError: Error, LocalizedError {
        case noFixtures(String)
        var errorDescription: String? {
            switch self {
            case .noFixtures(let message): message
            }
        }
    }
}

// MARK: - Match helpers

private extension ExtractionAccuracyHarness {
    static func abbreviate(_ score: FieldScore) -> String {
        "\(score.merchant.rawValue.prefix(1))/\(score.total.rawValue.prefix(1))/\(score.date.rawValue.prefix(1))"
    }

    static func padStatic(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width - 1)) + " " }
        return text + String(repeating: " ", count: width - text.count)
    }

    static func normalizeMerchant(_ raw: String) -> String {
        let folded = raw
            .lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "`", with: "")
        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!"))
    }

    static func merchantsMatch(_ expected: String, _ got: String) -> Bool {
        let a = normalizeMerchant(expected)
        let b = normalizeMerchant(got)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        // "ASDA Stores Ltd" ↔ "ASDA STORES LTD" / "ASDA"
        if a.contains(b) || b.contains(a) { return true }
        return false
    }

    static func merchantPresent(_ expected: String, in blob: String) -> Bool {
        let needle = normalizeMerchant(expected)
        let hay = normalizeMerchant(blob)
        if hay.contains(needle) { return true }
        // Also try significant tokens (length ≥ 4) so "ASDA Stores Ltd" hits "ASDA STORES LTD"
        let tokens = needle.split(separator: " ").map(String.init).filter { $0.count >= 4 }
        return !tokens.isEmpty && tokens.allSatisfy { hay.contains($0) }
    }

    static func totalsMatch(_ expected: Decimal, _ got: Double) -> Bool {
        let gotDecimal = Decimal(got)
        let delta = abs(expected - gotDecimal)
        return delta < Decimal(string: "0.005")!
    }

    static func totalPresent(_ expected: Decimal, in blob: String) -> Bool {
        // Look for the expected amount as a money-like token somewhere in OCR.
        let expectedDouble = NSDecimalNumber(decimal: expected).doubleValue
        let pattern = #"([£€$]|GBP|USD|AUD|EUR)?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\d+\.\d{2}|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(blob.startIndex..., in: blob)
        for match in regex.matches(in: blob, range: range) {
            guard match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 2), in: blob)
            else { continue }
            let token = String(blob[numberRange]).replacingOccurrences(of: ",", with: "")
            guard let value = Double(token) else { continue }
            if abs(value - expectedDouble) < 0.005 { return true }
        }
        return false
    }

    static func datesMatch(_ expectedRaw: String, _ gotISO: String) -> Bool {
        guard let expected = parseFlexibleDate(expectedRaw),
              let got = parseFlexibleDate(gotISO)
        else { return false }
        return isoDay(expected) == isoDay(got)
    }

    static func datePresent(_ expectedRaw: String, in blob: String) -> Bool {
        guard let expected = parseFlexibleDate(expectedRaw) else { return false }
        let day = Calendar(identifier: .gregorian).component(.day, from: expected)
        let month = Calendar(identifier: .gregorian).component(.month, from: expected)
        let year = Calendar(identifier: .gregorian).component(.year, from: expected)
        let yy = year % 100

        let candidates = [
            String(format: "%02d/%02d/%04d", day, month, year),
            String(format: "%02d/%02d/%02d", day, month, yy),
            String(format: "%d/%d/%04d", day, month, year),
            String(format: "%04d-%02d-%02d", year, month, day),
            String(format: "%02d-%02d-%04d", day, month, year),
        ]
        let lower = blob.lowercased()
        if candidates.contains(where: { lower.contains($0.lowercased()) }) {
            return true
        }

        // Written month forms: "16 June 2026", "16 Jun 2026"
        let months = [
            "", "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
        ]
        let shorts = [
            "", "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "oct", "nov", "dec",
        ]
        if month >= 1, month <= 12 {
            let forms = [
                "\(day) \(months[month]) \(year)",
                "\(day) \(shorts[month]) \(year)",
                "\(day) \(months[month])",
                "\(day) \(shorts[month])",
            ]
            if forms.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        return false
    }

    static func parseFlexibleDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = DateFormatter()
        iso.calendar = Calendar(identifier: .gregorian)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        if let date = iso.date(from: trimmed) { return date }

        let formats = ["dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "d/M/yy", "dd-MM-yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Tests

@Suite("Extraction accuracy")
struct ExtractionAccuracyTests {
    @Test("rules baseline report (type A vs type B)")
    func rulesBaselineReport() async throws {
        let fixtures = try ExtractionAccuracyHarness.loadFixtures()
        #expect(!fixtures.isEmpty, "Drop ReceiptFixture JSON into KeptTests/Fixtures")

        let report = try await ExtractionAccuracyHarness.evaluate(
            fixtures: fixtures,
            using: RulesExtractionService(),
            name: "RulesExtractor"
        )
        let text = report.printed()
        print("\n\(text)\n")
        try writeReport(text, name: "kept-accuracy-rules.txt")

        // Baseline bar from the plan. Expected to fail until extraction improves
        // (and until ~10 labelled fixtures are in the bundle).
        #expect(
            report.fullyCorrectCount >= 8,
            "merchant+total+date all correct on ≥8 fixtures (have \(report.fullyCorrectCount)/\(report.scores.count); type A absent / type B wrong — see printed table)"
        )
    }

    @Test("comparison mode: RulesExtractor vs CloudExtractor")
    func comparisonMode() async throws {
        let fixtures = try ExtractionAccuracyHarness.loadFixtures()
        #expect(!fixtures.isEmpty)

        let cloudConfig = CloudExtractConfiguration.fromEnvironment()
            ?? CloudExtractConfiguration.fromBundle()
        try #require(
            cloudConfig != nil,
            "Set KEPT_EXTRACT_BASE_URL + KEPT_EXTRACT_SECRET (and run wrangler dev) for cloud comparison"
        )

        let text = try await ExtractionAccuracyHarness.compare(
            fixtures: fixtures,
            lhs: (RulesExtractionService(), "Rules"),
            rhs: (CloudExtractor(configuration: cloudConfig!), "Cloud")
        )
        print("\n\(text)\n")
        try writeReport(text, name: "kept-accuracy-compare.txt")
        // Informational — read /tmp/kept-accuracy-compare.txt for the worth-it number.
        #expect(true)
    }

    private func writeReport(_ text: String, name: String) throws {
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
