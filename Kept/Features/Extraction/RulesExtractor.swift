import Foundation

/// Regex / heuristic extractor. Runs on every device and is the product floor.
struct RulesExtractor: Sendable {
    func extract(from lines: [RecognizedLine]) -> ExtractedReceipt {
        let texts = lines.map(\.text)
        let merchant = Self.merchant(from: texts)
        let (price, currency) = Self.priceAndCurrency(from: texts)
        let date = Self.purchaseDate(from: texts) ?? .now
        let itemName = Self.itemName(from: texts, merchant: merchant)

        var confidence = 0.35
        if !merchant.isEmpty { confidence += 0.2 }
        if price > 0 { confidence += 0.25 }
        if Self.purchaseDate(from: texts) != nil { confidence += 0.15 }
        if !itemName.isEmpty { confidence += 0.05 }

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: Self.isoDate(date),
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            confidence: min(confidence, 0.95)
        )
    }

    // MARK: - Merchant

    private static func merchant(from lines: [String]) -> String {
        let skip = merchantSkipPattern
        for line in lines.prefix(8) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 48 else { continue }
            if skip.isMatch(trimmed) { continue }
            if trimmed.contains(where: \.isNumber), digitRatio(trimmed) > 0.4 { continue }
            return trimmed
        }
        return lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static let merchantSkipPattern = RegexPatterns(
        #"^(tel|phone|fax|www\.|http|vat|tax|abn|gst|receipt|invoice|tax\s*invoice)"#,
        #"^\d+$"#,
        #"^[\d\s\-\+\(\)]+$"#
    )

    // MARK: - Item

    private static func itemName(from lines: [String], merchant: String) -> String {
        let skip = itemSkipPattern
        for line in lines.dropFirst().prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 60 else { continue }
            if trimmed.caseInsensitiveCompare(merchant) == .orderedSame { continue }
            if skip.isMatch(trimmed) { continue }
            if amount(in: trimmed) != nil, trimmed.split(whereSeparator: \.isWhitespace).count <= 2 {
                continue
            }
            return cleanItemName(trimmed)
        }
        return ""
    }

    private static func cleanItemName(_ raw: String) -> String {
        var text = raw
        // Strip leading SKU / stock codes.
        if let match = text.prefixMatch(of: #/^\d{4,}\s+/#) {
            text = String(text[match.range.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let itemSkipPattern = RegexPatterns(
        #"^(total|subtotal|sub\s*total|amount\s*due|balance|change|cash|card|visa|mastercard|amex|gst|vat|tax|thank|welcome|www\.|http)"#,
        #"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#,
        #"^(qty|quantity|items?)\b"#
    )

    // MARK: - Price / currency

    private static func priceAndCurrency(from lines: [String]) -> (Double, String) {
        var labeledTotal: (Double, String)?
        var amounts: [(Double, String)] = []

        for line in lines {
            let lower = line.lowercased()
            if let parsed = amount(in: line) {
                amounts.append(parsed)
                if lower.contains("total")
                    || lower.contains("amount due")
                    || lower.contains("balance")
                    || lower.contains("grand") {
                    labeledTotal = parsed
                }
            }
        }

        if let labeledTotal { return labeledTotal }
        if let max = amounts.max(by: { $0.0 < $1.0 }) { return max }
        return (0, Locale.current.currency?.identifier ?? "USD")
    }

    private static func amount(in line: String) -> (Double, String)? {
        let currency = currencyCode(in: line) ?? Locale.current.currency?.identifier ?? "USD"

        // 1,234.56 or 1.234,56 or 1234.56
        let patterns: [String] = [
            #"([£€$₹₦¥]|A\$|AU\$|C\$|NZ\$|US\$)?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2}|\d{1,3}(?:\.\d{3})*(?:,\d{2}))"#,
            #"(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})\s*([A-Z]{3})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            guard let match = matches.last else { continue }

            for index in 1..<match.numberOfRanges {
                guard let swiftRange = Range(match.range(at: index), in: line) else { continue }
                let token = String(line[swiftRange])
                if let value = parseNumber(token) {
                    let code = currencyCode(in: line) ?? currency
                    return (value, code)
                }
            }
        }
        return nil
    }

    private static func parseNumber(_ raw: String) -> Double? {
        var token = raw
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "₦", with: "")
            .replacingOccurrences(of: "A", with: "")
            .replacingOccurrences(of: "U", with: "")
            .replacingOccurrences(of: "C", with: "")
            .replacingOccurrences(of: "N", with: "")
            .replacingOccurrences(of: "Z", with: "")
            .trimmingCharacters(in: .whitespaces)

        // European decimal comma: 1.234,56 → 1234.56
        if token.contains(","), token.contains(".") {
            if token.lastIndex(of: ",")! > token.lastIndex(of: ".")! {
                token = token.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                token = token.replacingOccurrences(of: ",", with: "")
            }
        } else if token.contains(",") {
            let parts = token.split(separator: ",")
            if parts.last?.count == 2 {
                token = token.replacingOccurrences(of: ",", with: ".")
            } else {
                token = token.replacingOccurrences(of: ",", with: "")
            }
        }

        return Double(token)
    }

    private static func currencyCode(in line: String) -> String? {
        let upper = line.uppercased()
        let iso = ["USD", "GBP", "EUR", "AUD", "NZD", "CAD", "NGN", "INR", "JPY", "BRL"]
        for code in iso where upper.contains(code) { return code }

        if line.contains("£") { return "GBP" }
        if line.contains("€") { return "EUR" }
        if line.contains("¥") { return "JPY" }
        if line.contains("₹") { return "INR" }
        if line.contains("₦") { return "NGN" }
        if line.contains("A$") || line.contains("AU$") { return "AUD" }
        if line.contains("C$") || line.contains("CA$") { return "CAD" }
        if line.contains("NZ$") { return "NZD" }
        if line.contains("R$") { return "BRL" }
        if line.contains("$") { return "USD" }
        return nil
    }

    // MARK: - Date

    private static func purchaseDate(from lines: [String]) -> Date? {
        let patterns: [(String, Bool)] = [
            (#"(\d{4})-(\d{2})-(\d{2})"#, true),          // yyyy-MM-dd
            (#"(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#, false), // d/M/yyyy or M/d/yyyy
            (#"(\d{1,2})[/-](\d{1,2})[/-](\d{2})"#, false), // d/M/yy
        ]

        for line in lines {
            for (pattern, isISO) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      match.numberOfRanges >= 4,
                      let r1 = Range(match.range(at: 1), in: line),
                      let r2 = Range(match.range(at: 2), in: line),
                      let r3 = Range(match.range(at: 3), in: line)
                else { continue }

                let a = Int(line[r1]) ?? 0
                let b = Int(line[r2]) ?? 0
                let c = Int(line[r3]) ?? 0

                if isISO {
                    return date(year: a, month: b, day: c)
                }

                let year = c < 100 ? 2000 + c : c
                // Prefer DMY (UK/AU/EU). Fall back to MDY if day would be invalid.
                if let dmy = date(year: year, month: b, day: a) { return dmy }
                if let mdy = date(year: year, month: a, day: b) { return mdy }
            }
        }
        return nil
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func digitRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let digits = text.filter(\.isNumber).count
        return Double(digits) / Double(text.count)
    }
}

private struct RegexPatterns {
    private let regexes: [NSRegularExpression]

    init(_ patterns: String...) {
        regexes = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }

    func isMatch(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
