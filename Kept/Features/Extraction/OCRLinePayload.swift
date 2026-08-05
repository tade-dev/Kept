import CoreGraphics
import Foundation

/// Codable OCR line for SwiftData storage and deferred re-extraction.
/// Geometry matches Vision / worker: origin bottom-left, normalised 0...1.
struct OCRLinePayload: Codable, Sendable, Equatable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ line: RecognizedLine) {
        text = line.text
        x = line.boundingBox.origin.x
        y = line.boundingBox.origin.y
        width = line.boundingBox.size.width
        height = line.boundingBox.size.height
    }

    var recognizedLine: RecognizedLine {
        RecognizedLine(
            text: text,
            confidence: 1,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    static func encode(_ lines: [RecognizedLine]) -> Data? {
        try? JSONEncoder().encode(lines.map(OCRLinePayload.init))
    }

    static func decode(_ data: Data) -> [RecognizedLine]? {
        guard let payloads = try? JSONDecoder().decode([OCRLinePayload].self, from: data) else {
            return nil
        }
        return payloads.map(\.recognizedLine)
    }
}
