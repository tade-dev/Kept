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

        let returnWindow = Self.returnWindow(purchaseDate: date, merchant: merchant, lines: texts)
        if !returnWindow.isInferred, returnWindow.days > 0 { confidence += 0.1 }

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: Self.isoDate(date),
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: returnWindow.days,
            returnWindowIsInferred: returnWindow.isInferred,
            confidence: min(confidence, 0.95)
        )
    }

    // MARK: - Return window

    private static func returnWindow(
        purchaseDate: Date,
        merchant: String,
        lines: [String]
    ) -> (days: Int, isInferred: Bool) {
        // 1) Absolute printed deadline beats everything
        //    e.g. "Last day for refund or exchange 04/04/2020"
        if let deadline = explicitReturnDeadline(from: lines) {
            let calendar = Calendar(identifier: .gregorian)
            let start = calendar.startOfDay(for: purchaseDate)
            let end = calendar.startOfDay(for: deadline)
            if let days = calendar.dateComponents([.day], from: start, to: end).day,
               (1...366).contains(days) {
                return (days, false)
            }
        }

        let blob = ([merchant] + lines).joined(separator: "\n").lowercased()

        // 2) Explicit "28 days return" style counts
        if let match = blob.firstMatch(of: #/(\d{1,3})\s*(?:day|days)\s*(?:return|refund|exchange)/#)
            ?? blob.firstMatch(of: #/(?:return|refund|exchange)[^\d]{0,24}(\d{1,3})\s*(?:day|days)/#),
           let days = Int(match.1),
           (1...90).contains(days) {
            return (days, false)
        }

        // 3) Category heuristics (inferred)
        let fashion = [
            "primark", "h&m", "hm ", "zara", "uniqlo", "gap", "old navy",
            "forever 21", "mango", "asos", "shein", "next ", "new look",
            "marks & spencer", "m&s", "tk maxx", "tj maxx", "cotton on",
        ]
        if fashion.contains(where: { blob.contains($0) }) {
            return (28, true)
        }

        let grocery = [
            "woolworths", "coles", "tesco", "sainsbury", "aldi", "lidl",
            "asda", "morrisons", "waitrose", "whole foods",
        ]
        if grocery.contains(where: { blob.contains($0) }) {
            return (0, false)
        }

        return (0, false)
    }

    private static func explicitReturnDeadline(from lines: [String]) -> Date? {
        let cue = RegexPatterns(
            #"last\s+day\s+for\s+(refund|exchange|return)"#,
            #"refund\s+or\s+exchange"#,
            #"(refund|exchange|return).{0,24}(by|until|before)"#,
            #"returns?\s+(by|until|before)"#
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cue.isMatch(trimmed) else { continue }
            if let date = firstDate(in: trimmed, preferDMY: true) {
                return date
            }
        }

        // OCR sometimes splits the cue and the date across adjacent lines.
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard cue.isMatch(trimmed) else { continue }
            let window = lines[index...].prefix(3).joined(separator: " ")
            if let date = firstDate(in: window, preferDMY: true) {
                return date
            }
        }

        return nil
    }

    // MARK: - Merchant

    private static let knownMerchants = [
        "primark", "apple", "woolworths", "tesco", "currys", "best buy",
        "ikea", "target", "harvey norman", "jb hi-fi", "h&m", "zara", "uniqlo",
    ]

    private static func merchant(from lines: [String]) -> String {
        // Prefer a known retailer mentioned anywhere (Primark receipts often put
        // a local place-name above the brand).
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if let known = knownMerchants.first(where: { lower.contains($0) }) {
                if lower == known || lower.hasPrefix(known) || lower.contains("\(known) ") {
                    return trimmed
                }
                // Normalize bare brand hits like "... PRIMARK STORES LTD"
                if let range = lower.range(of: known) {
                    let start = trimmed.index(
                        trimmed.startIndex,
                        offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound)
                    )
                    return String(trimmed[start...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

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
            if amount(in: trimmed, fallbackCurrency: "USD") != nil,
               trimmed.split(whereSeparator: \.isWhitespace).count <= 2 {
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

    private static let priceNoisePattern = RegexPatterns(
        #"\b(auth|authori[sz]ation|approval\s*code|ref(erence)?\.?|rrn|stan)\b"#,
        #"\b(imei|serial|s\/n|part\s*(no|number|#)?|sku|barcode)\b"#,
        #"\b(terminal|tvr|tsi|aid|pan\s*sequence|application)\b"#,
        #"\*{2,}|chip\b|verified by|pin\b|approved\b"#
    )

    private static func priceAndCurrency(from lines: [String]) -> (Double, String) {
        let fallbackCurrency = documentCurrency(from: lines)
            ?? Locale.current.currency?.identifier
            ?? "USD"

        var bestLabeled: (score: Int, value: Double)?
        var amounts: [Double] = []

        for line in lines {
            let lower = line.lowercased()
            // Auth codes, IMEIs, terminal IDs — never price candidates.
            if priceNoisePattern.isMatch(lower) { continue }

            let score: Int
            if lower.contains("grand total") || lower.contains("amount due") {
                score = 3
            } else if lower.range(of: #"\btotal\b"#, options: .regularExpression) != nil,
                      !lower.contains("sub") {
                score = 2
            } else if lower.contains("balance")
                        || lower.range(of: #"\bpaid\b"#, options: .regularExpression) != nil {
                score = 1
            } else {
                score = 0
            }

            // Labeled money lines may recover "$ 284900" → 2849.00; unlabeled stay strict.
            guard let value = amount(
                in: line,
                allowBareInteger: score > 0,
                allowCurrencyIntegerRecovery: score > 0
            ) else { continue }
            amounts.append(value)

            if score > 0 {
                if bestLabeled == nil || score >= bestLabeled!.score {
                    bestLabeled = (score, value)
                }
            }
        }

        let currency = documentCurrency(from: lines) ?? fallbackCurrency
        if let bestLabeled {
            return (bestLabeled.value, currency)
        }
        if let max = amounts.max() {
            return (max, currency)
        }
        return (0, currency)
    }

    /// Currency cue from anywhere on the receipt.
    private static func documentCurrency(from lines: [String]) -> String? {
        for line in lines {
            if let code = explicitCurrencyCode(in: line) { return code }
        }
        let blob = lines.joined(separator: "\n").lowercased()
        if blob.contains("primark")
            || blob.contains("vat number")
            || blob.contains("united kingdom")
            || blob.contains("berkshire")
            || (blob.contains("reading") && blob.contains("rg")) {
            return "GBP"
        }
        // Apple AU / Australian GST receipts use $ but mean AUD.
        if blob.contains("qld")
            || blob.contains("nsw")
            || blob.contains("victoria")
            || blob.contains("australia")
            || blob.contains(".com/au")
            || blob.contains("chermside")
            || blob.contains("abn")
            || (blob.contains("gst") && (blob.contains("apple") || blob.contains("woolworths") || blob.contains("jb hi"))) {
            return "AUD"
        }
        for line in lines where line.contains("$") {
            return "USD"
        }
        return nil
    }

    /// Largest well-formed money token on the line.
    /// Rejects IMEI/barcode bleed (`350.10` carved from `350.108727…`) and prefers full `2.849.00`.
    private static func amount(
        in line: String,
        fallbackCurrency: String = "USD",
        allowBareInteger: Bool = false,
        allowCurrencyIntegerRecovery: Bool = false
    ) -> Double? {
        _ = fallbackCurrency
        // Alternation order matters: multi-dot thousands (`2.849.00`) MUST precede `\d+\.\d{2}`
        // or the engine locks onto `2.84` + leftover `9.00`.
        let pattern = #"([£€$₹₦¥]|A\$|AU\$|C\$|CA\$|NZ\$|US\$|R\$)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d{1,3}(?:\.\d{3})+,\d{2}|\d{1,3}(?:\.\d{3})+\.\d{2}|\d+\.\d{2}|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)

        var best: Double?
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: line),
                  let numberRange = Range(match.range(at: 2), in: line)
            else { continue }

            let hasSymbol = match.range(at: 1).location != NSNotFound
            let token = String(line[numberRange])
            let looksLikeMoney = hasSymbol
                || token.contains(".")
                || token.contains(",")

            // Don't carve `350.10` out of an IMEI like `350.108727082833`.
            if hasTrailingDigits(after: fullRange, in: line) { continue }

            // Skip bare years / short codes mistaken for money.
            if token.count == 4, !token.contains("."), !token.contains(","),
               let year = Int(token), (1900...2100).contains(year) {
                continue
            }

            // Auth / barcode / qty integers are not prices. Only Total/Paid lines
            // may use a bare integer (e.g. "TOTAL 22"); everywhere else needs $ or .00.
            let digitCount = token.filter(\.isNumber).count
            if !looksLikeMoney {
                if !allowBareInteger { continue }
                if digitCount >= 6 { continue } // auth codes, phone fragments
            }
            if !hasSymbol, digitCount >= 7, !token.contains("."), !token.contains(",") {
                continue
            }

            var value = parseNumber(token)
            // OCR sometimes drops the decimal: "$ 284900" on a Total/Paid line → 2849.00
            if allowCurrencyIntegerRecovery, hasSymbol,
               let raw = value, raw >= 1000, token.allSatisfy(\.isNumber), token.count >= 5 {
                let recovered = raw / 100
                if recovered >= 10, recovered <= 1_000_000 {
                    value = recovered
                }
            }

            guard let value, value > 0, value <= 1_000_000 else { continue }
            // Unlabeled bare integers under 10 are usually qty / line noise.
            if !looksLikeMoney, value < 10 { continue }

            if best == nil || value > best! {
                best = value
            }
        }
        return best
    }

    private static func hasTrailingDigits(after range: Range<String.Index>, in line: String) -> Bool {
        var index = range.upperBound
        while index < line.endIndex {
            let character = line[index]
            if character.isNumber { return true }
            if character == "," || character == "." {
                let next = line.index(after: index)
                if next < line.endIndex, line[next].isNumber { return true }
                return false
            }
            // Space between "$ 2" and "849.00" is handled by separate matches; stop on other junk.
            return false
        }
        return false
    }

    private static func parseNumber(_ raw: String) -> Double? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["A$", "AU$", "US$", "CA$", "C$", "NZ$", "R$", "$", "£", "€", "¥", "₹", "₦"]
        for prefix in prefixes {
            if token.hasPrefix(prefix) {
                token = String(token.dropFirst(prefix.count))
                break
            }
        }
        token = token.trimmingCharacters(in: .whitespaces)

        // OCR often turns "2,849.00" into "2.849.00" (dot thousands + dot cents).
        let dotParts = token.split(separator: ".", omittingEmptySubsequences: false)
        if dotParts.count >= 3,
           dotParts.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }),
           dotParts.last?.count == 2 {
            let whole = dotParts.dropLast().joined()
            token = whole + "." + (dotParts.last.map(String.init) ?? "00")
            return Double(token)
        }

        // European decimal comma: 1.234,56 → 1234.56
        if token.contains(","), token.contains(".") {
            if token.lastIndex(of: ",")! > token.lastIndex(of: ".")! {
                token = token.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                token = token.replacingOccurrences(of: ",", with: "")
            }
        } else if token.contains(",") {
            let parts = token.split(separator: ",")
            if parts.last?.count == 2, parts.count == 2, parts[0].count <= 3 {
                // 22,00 style decimals
                token = token.replacingOccurrences(of: ",", with: ".")
            } else {
                // 1,234 or 1,234,567 thousands
                token = token.replacingOccurrences(of: ",", with: "")
            }
        }

        return Double(token)
    }

    private static func explicitCurrencyCode(in line: String) -> String? {
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
        return nil
    }

    private static func currencyCode(in line: String) -> String? {
        explicitCurrencyCode(in: line)
    }

    // MARK: - Date

    private static func purchaseDate(from lines: [String]) -> Date? {
        let returnCue = RegexPatterns(
            #"last\s+day\s+for"#,
            #"refund\s+or\s+exchange"#,
            #"returns?\s+(by|until|before)"#
        )

        // Prefer an explicitly labeled purchase date.
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("date"), !returnCue.isMatch(line),
               let date = firstDate(in: line, preferDMY: true) {
                return date
            }
        }

        // Apple-style "26 November 2024 14:24" near the top — try early lines first.
        for line in lines {
            if returnCue.isMatch(line) { continue }
            if let date = firstDate(in: line, preferDMY: true) {
                return date
            }
        }
        return nil
    }

    private static func firstDate(in line: String, preferDMY: Bool) -> Date? {
        if let written = writtenMonthDate(in: line) {
            return written
        }

        let patterns: [(String, Bool)] = [
            (#"(\d{4})-(\d{2})-(\d{2})"#, true),
            (#"(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#, false),
            (#"(\d{1,2})[/-](\d{1,2})[/-](\d{2})"#, false),
        ]

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
            if preferDMY {
                if let dmy = date(year: year, month: b, day: a) { return dmy }
                if let mdy = date(year: year, month: a, day: b) { return mdy }
            } else {
                if let mdy = date(year: year, month: a, day: b) { return mdy }
                if let dmy = date(year: year, month: b, day: a) { return dmy }
            }
        }
        return nil
    }

    private static let monthIndexes: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    /// "26 November 2024", "28 November 2024 16:24", "Nov 26, 2024"
    private static func writtenMonthDate(in line: String) -> Date? {
        let lower = line.lowercased()

        // 26 November 2024 [time]
        if let match = lower.firstMatch(
            of: #/(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\.?\s+(\d{4})/#
        ),
           let day = Int(match.1),
           let month = monthIndexes[String(match.2)],
           let year = Int(match.3) {
            return date(year: year, month: month, day: day)
        }

        // November 26, 2024 / Nov 26 2024
        if let match = lower.firstMatch(
            of: #/(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\.?\s+(\d{1,2}),?\s+(\d{4})/#
        ),
           let month = monthIndexes[String(match.1)],
           let day = Int(match.2),
           let year = Int(match.3) {
            return date(year: year, month: month, day: day)
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
