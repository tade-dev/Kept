import Foundation
import UIKit
import Vision

struct RecognizedLine: Sendable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let confidence: Float
    /// Normalized Vision coordinates (origin bottom-left, 0...1).
    let boundingBox: CGRect

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: CGRect
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

protocol OCRService: Sendable {
    /// Recognizes text and returns lines ordered top-to-bottom on the page.
    func recognize(in image: UIImage) async throws -> [RecognizedLine]
}

enum OCRServiceError: Error, LocalizedError {
    case invalidImage
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Couldn't read that image."
        case .underlying(let error): error.localizedDescription
        }
    }
}

struct VisionOCRService: OCRService {
    var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    var usesLanguageCorrection: Bool = true
    var recognitionLanguages: [String] = ["en-US"]

    func recognize(in image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else { throw OCRServiceError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let level = recognitionLevel
        let correction = usesLanguageCorrection
        let languages = recognitionLanguages

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = correction
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                throw OCRServiceError.underlying(error)
            }

            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> RecognizedLine? in
                guard let best = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(
                    text: best.string,
                    confidence: best.confidence,
                    boundingBox: observation.boundingBox
                )
            }

            // Vision origin is bottom-left; higher maxY is nearer the top of the page.
            return lines.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Back-compat alias while call sites migrate.
typealias TextRecognizing = OCRService
typealias VisionTextRecognizer = VisionOCRService
typealias TextRecognitionError = OCRServiceError
