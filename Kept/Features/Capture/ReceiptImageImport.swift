import CoreTransferable
import Foundation
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// How a capture sheet should start. A camera request presents
/// `DocumentScanner`. An imported image is handed to `CaptureView(image:)`,
/// which skips the scanner and runs the same OCR → extraction → review path.
struct ReceiptCaptureRequest: Identifiable {
    let id: UUID
    /// Nil opens the camera. Non-nil is a photo, or the first page of a PDF.
    let image: UIImage?

    init(id: UUID = UUID(), image: UIImage?) {
        self.id = id
        self.image = image
    }

    static func camera() -> ReceiptCaptureRequest {
        ReceiptCaptureRequest(image: nil)
    }

    static func imported(_ image: UIImage) -> ReceiptCaptureRequest {
        ReceiptCaptureRequest(image: image)
    }

    var usesCameraScanner: Bool { image == nil }
}

/// Turns a picked photo or a PDF file into the `UIImage` the scan pipeline
/// already accepts. PDFKit is already linked for claim packs, so the first
/// page is rendered here instead of adding a second import path.
enum ReceiptImageImport {
    /// PDF user space is 72 pt per inch. 3× is about 216 DPI, enough for OCR.
    static let preferredPDFScale: CGFloat = 3
    /// Longest edge, in pixels, so a huge page does not allocate a giant bitmap.
    static let maxPixelDimension: CGFloat = 3000

    enum Failure: Error, Equatable, LocalizedError {
        case unreadableImage
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .unreadableImage, .unreadablePDF:
                // Same wording as `OCRServiceError.invalidImage`.
                String(localized: "Couldn't read that image.")
            }
        }
    }

    enum Outcome {
        case ready(UIImage)
        case cancelled
        case failed(Failure)
    }

    /// Scale that keeps the long edge at or under `maxPixelDimension`.
    static func renderScale(
        for pageSize: CGSize,
        preferredScale: CGFloat = preferredPDFScale,
        maxPixelDimension: CGFloat = maxPixelDimension
    ) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0, preferredScale > 0 else { return 1 }
        let longest = max(pageSize.width, pageSize.height)
        return min(preferredScale, maxPixelDimension / longest)
    }

    static func image(fromImageData data: Data) -> Result<UIImage, Failure> {
        guard let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            return .failure(.unreadableImage)
        }
        return .success(image)
    }

    /// Renders page 0 only. Later pages are ignored — a receipt is one page
    /// for the scan pipeline, which already keeps the first camera page.
    static func image(fromPDFData data: Data) -> Result<UIImage, Failure> {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0)
        else {
            return .failure(.unreadablePDF)
        }
        return .success(render(page))
    }

    static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = renderScale(for: bounds.size)
        let pixelSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            let cgContext = context.cgContext
            cgContext.saveGState()
            // PDF origin is bottom-left. Flip into that space, then draw in points.
            cgContext.translateBy(x: 0, y: pixelSize.height)
            cgContext.scaleBy(x: scale, y: -scale)
            cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            // Draws the media box as stored. A page with /Rotate 90 or 270
            // can come out sideways; receipt PDFs are usually upright.
            page.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
        }
    }

    static func loadPhoto(_ item: PhotosPickerItem) async -> Outcome {
        do {
            guard let transferred = try await item.loadTransferable(type: ImportedReceiptImage.self) else {
                return .failed(.unreadableImage)
            }
            switch image(fromImageData: transferred.data) {
            case .success(let image):
                return .ready(image)
            case .failure(let failure):
                return .failed(failure)
            }
        } catch {
            if isCancellation(error) { return .cancelled }
            return .failed(.unreadableImage)
        }
    }

    /// `fileImporter` reports a cancel as `NSUserCancelledError`, sometimes wrapped.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSCocoaErrorDomain,
           underlying.code == NSUserCancelledError {
            return true
        }
        return false
    }
}

/// Still image bytes from Photos. `matching: .images` plus this representation
/// avoids a photo-library permission prompt.
nonisolated struct ImportedReceiptImage: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedReceiptImage(data: data)
        }
    }
}
