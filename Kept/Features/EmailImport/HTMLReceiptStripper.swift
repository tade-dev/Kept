import CoreGraphics
import Foundation

/// Turns an HTML order-confirmation email into ordered `[RecognizedLine]`
/// ready for `DefaultExtractionService` and the cloud extractor.
///
/// Not a general-purpose HTML → text converter. Tuned specifically for
/// merchant order emails — tables, marketing chrome, tracking pixels,
/// legal footers. Aggressive by design; we'd rather lose an edge case
/// than hand the LLM 40KB of noise.
///
/// Output shape matches Vision OCR: one `RecognizedLine` per non-empty
/// text line, in reading order. Bounding boxes are `.zero` since email
/// has no spatial layout in the way a receipt does — the worker prompt
/// branches on `source == "email"` to skip geometry-dependent heuristics.
enum HTMLReceiptStripper {
    /// Ceiling on the cleaned text length. Amazon-style order emails
    /// hold the order details in the first 2–4KB; everything past that
    /// is legal chrome that hurts extraction. Chosen empirically to
    /// hold Argos + John Lewis + Amazon without truncating the total.
    static let maxCharacters = 8000

    /// Case-insensitive substrings that mark the transition from
    /// order content into legal/marketing footer. When any of these
    /// appears, we drop everything from that point onward.
    ///
    /// Order matters — earliest match wins.
    static let footerMarkers: [String] = [
        "view this email in your browser",
        "view in browser",
        "view online",
        "unsubscribe",
        "manage your email preferences",
        "manage email preferences",
        "you are receiving this email",
        "you're receiving this email",
        "this email was sent to",
        "this is an automated message",
        "do not reply to this email",
        "privacy policy",
        "terms and conditions",
        "terms of service",
        "all rights reserved",
        "registered office",
        "registered in england"
    ]

    static func strip(_ html: String) -> [RecognizedLine] {
        var s = html

        s = remove(s, matching: #"<script\b[^>]*>[\s\S]*?</script>"#)
        s = remove(s, matching: #"<style\b[^>]*>[\s\S]*?</style>"#)
        s = remove(s, matching: #"<!--[\s\S]*?-->"#)

        // Tracking pixels: <img width="1" height="1"> etc. Not worth
        // preserving alt-text on these.
        s = remove(s, matching: #"<img\b[^>]*(?:width\s*=\s*["']?1["']?)[^>]*>"#)

        s = insertNewlinesForBlockLevelTags(s)

        s = remove(s, matching: #"<[^>]+>"#)

        s = decodeEntities(s)

        s = normaliseWhitespaceLines(s)

        s = cutAtFooter(s)

        if s.count > maxCharacters {
            s = String(s.prefix(maxCharacters))
        }

        return s.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { RecognizedLine(text: $0, confidence: 1, boundingBox: .zero) }
    }

    // MARK: - Steps

    /// Replaces closing/self-closing block-level tags with a newline so
    /// the subsequent tag strip leaves visually distinct lines instead
    /// of one giant concatenated string. Table cells (`<td>`, `</td>`)
    /// get spaces so item + price on the same row stay together.
    ///
    /// One tag at a time (no alternation): keeps each pattern short and
    /// removes an ambiguity class of bugs — the earlier alternation
    /// version silently no-op'd on real emails.
    private static func insertNewlinesForBlockLevelTags(_ input: String) -> String {
        var s = input

        // Cell boundaries → single space (row-preserving).
        for cell in ["td", "th"] {
            s = replace(s, matching: #"<"# + cell + #"\b[^>]*>"#, with: " ")
            s = replace(s, matching: #"</"# + cell + #"\s*>"#, with: " ")
        }

        // Row / block boundaries → newline.
        let breakTags = ["br", "p", "div", "tr", "li", "ul", "ol",
                         "h1", "h2", "h3", "h4", "h5", "h6",
                         "table", "section", "article", "header",
                         "footer", "hr", "title"]
        for tag in breakTags {
            s = replace(s, matching: #"<"# + tag + #"\b[^>]*/?>"#, with: "\n")
            s = replace(s, matching: #"</"# + tag + #"\s*>"#, with: "\n")
        }

        return s
    }

    /// Decodes the tiny handful of entities that actually appear in
    /// order emails. A full entity table is unnecessary and heavier
    /// than the extension's memory budget likes.
    private static func decodeEntities(_ input: String) -> String {
        var s = input
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#8217;", "'"),
            ("&#8220;", "\""),
            ("&#8221;", "\""),
            ("&#8211;", "-"),
            ("&#8212;", "-"),
            ("&ndash;", "-"),
            ("&mdash;", "-"),
            ("&middot;", "·"),
            ("&bull;", "•"),
            ("&pound;", "£"),
            ("&euro;", "€"),
            ("&yen;", "¥"),
            ("&cent;", "¢"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
            ("&hellip;", "…")
        ]
        for (from, to) in named {
            s = s.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        // Numeric entities like &#163; → decode via unicode scalar.
        s = decodeNumericEntities(s)
        return s
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else {
            return input
        }
        var result = input
        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: nsRange).reversed()
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let codeRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let code = String(result[codeRange])
            let scalarValue: UInt32?
            if code.hasPrefix("x") || code.hasPrefix("X") {
                scalarValue = UInt32(code.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(code, radix: 10)
            }
            if let value = scalarValue, let scalar = Unicode.Scalar(value) {
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        return result
    }

    /// Collapses runs of horizontal whitespace to one space, and runs
    /// of blank lines to a single newline. Preserves the line structure
    /// the extractor relies on.
    ///
    /// The horizontal-whitespace class deliberately avoids `\s` and `\v`:
    /// ICU's `\s` and `\v` both include `\n`, which would obliterate
    /// the line breaks we just inserted at block boundaries.
    private static func normaliseWhitespaceLines(_ input: String) -> String {
        var s = input
        s = replace(s, matching: #"[ \t\r]+"#, with: " ")
        s = replace(s, matching: #"\n[ \t]+"#, with: "\n")
        s = replace(s, matching: #"[ \t]+\n"#, with: "\n")
        s = replace(s, matching: #"\n{2,}"#, with: "\n")
        return s
    }

    /// Truncates the string at the first footer-marker match.
    /// Line-oriented so we don't chop a marker mid-sentence.
    private static func cutAtFooter(_ input: String) -> String {
        let lower = input.lowercased()
        var cutIndex: String.Index?
        for marker in footerMarkers {
            if let range = lower.range(of: marker) {
                if cutIndex == nil || range.lowerBound < cutIndex! {
                    cutIndex = range.lowerBound
                }
            }
        }
        guard let cutIndex else { return input }
        // Snap to the start of the containing line so we don't leave a
        // half-line above the cut point.
        let prefix = input[..<cutIndex]
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return String(input[..<lastNewline])
        }
        return String(prefix)
    }

    // MARK: - Regex helpers

    private static func remove(_ input: String, matching pattern: String) -> String {
        replace(input, matching: pattern, with: "")
    }

    /// Manual find-and-replace via NSRegularExpression matches so the
    /// replacement string is inserted verbatim — no template escape
    /// interpretation. `stringByReplacingMatches(withTemplate:)` reserves
    /// `$` and `\` for backreferences and silently drops or reinterprets
    /// unfamiliar sequences, which was eating our `\n` inserts and
    /// producing single-line output.
    private static func replace(_ input: String, matching pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return input
        }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }
        var out = ""
        var cursor = 0
        for match in matches {
            let start = match.range.location
            if start > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: start - cursor))
            }
            out += replacement
            cursor = start + match.range.length
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }
}
