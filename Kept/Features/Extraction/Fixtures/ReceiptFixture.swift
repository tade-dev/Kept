import CoreGraphics
import Foundation

/// One OCR line as stored in a fixture / sent to the cloud extractor.
/// Bounding box matches Vision: origin bottom-left, normalised 0…1.
struct OCRLine: Codable, Equatable, Sendable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var boundingBox: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(text: String, boundingBox: CGRect) {
        self.text = text
        self.x = boundingBox.origin.x
        self.y = boundingBox.origin.y
        self.width = boundingBox.size.width
        self.height = boundingBox.size.height
    }

    init(_ line: RecognizedLine) {
        self.init(text: line.text, boundingBox: line.boundingBox)
    }
}

/// Ground-truth fields for accuracy scoring. Nil until filled in by hand.
struct ExpectedValues: Codable, Equatable, Sendable {
    var merchant: String?
    var itemName: String?
    var total: Decimal?
    /// ISO 4217, e.g. "AUD", "GBP".
    var currencyCode: String?
    /// Purchase date only, `yyyy-MM-dd`.
    var purchaseDate: String?
}

/// Offline OCR snapshot of one receipt scan. Image is never stored — text only.
struct ReceiptFixture: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var capturedAt: Date
    /// Top-to-bottom reading order (same sort VisionOCRService returns).
    var ocrLines: [OCRLine]
    var expected: ExpectedValues?
    var notes: String

    init(
        id: String = UUID().uuidString,
        capturedAt: Date = .now,
        ocrLines: [OCRLine],
        expected: ExpectedValues? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.ocrLines = ocrLines
        self.expected = expected
        self.notes = notes
    }

    /// Bridge back into the live extraction pipeline.
    var recognizedLines: [RecognizedLine] {
        ocrLines.map {
            RecognizedLine(
                text: $0.text,
                confidence: 1,
                boundingBox: $0.boundingBox
            )
        }
    }
}

extension ReceiptFixture {
    static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
