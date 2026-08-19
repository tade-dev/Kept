import PDFKit
import SwiftUI
import UIKit

/// Turns a `Purchase` into a multi-page A4 PDF claim pack.
///
/// Page 1: Kept-branded summary (via `ClaimPackDocument`).
/// Page 2+: the receipt image, scaled to fit while preserving aspect ratio.
/// Emits nothing extra when there is no receipt image on file.
enum ClaimPackRenderer {
    /// A4 at 72dpi (the PDF default unit).
    static let pageSize = CGSize(width: 595, height: 842)
    private static let imagePageMargin: CGFloat = 32

    /// Renders the claim pack synchronously on the calling thread. Cheap
    /// enough for main-thread use — a two-page A4 doc renders in a few tens
    /// of milliseconds on-device — but callers are free to hop to a bg task
    /// if they want the UI to stay snappy on older devices.
    @MainActor
    static func render(purchase: Purchase, generatedAt: Date = .now) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: metadataFormat(for: purchase))

        return renderer.pdfData { context in
            drawSummaryPage(purchase: purchase, generatedAt: generatedAt, context: context)
            if let image = receiptImage(for: purchase) {
                drawImagePage(image: image, context: context)
            }
        }
    }

    /// Writes the PDF to a shareable temp file so `ShareLink` / activity
    /// controllers can present it with the intended filename. Returns the
    /// file URL. Overwrites any prior file at the same path.
    @MainActor
    static func renderToTempFile(purchase: Purchase, generatedAt: Date = .now) throws -> URL {
        let data = render(purchase: purchase, generatedAt: generatedAt)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: purchase, at: generatedAt))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Filename shaped for the share sheet: `claim-pack-primark-2026-08-19.pdf`.
    static func filename(for purchase: Purchase, at date: Date) -> String {
        let merchant = purchase.merchant
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let dateString = ISO8601DateFormatter.dateOnly.string(from: date)
        let stem = merchant.isEmpty ? "claim-pack-\(dateString)" : "claim-pack-\(merchant)-\(dateString)"
        return "\(stem).pdf"
    }

    // MARK: - Private drawing

    @MainActor
    private static func drawSummaryPage(purchase: Purchase, generatedAt: Date, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        let view = ClaimPackDocument(purchase: purchase, generatedAt: generatedAt)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(pageSize)
        // 3x = print-quality raster. `render(_:renderer:)` into the PDF's
        // CGContext would leave text as vectors, but the axis flip that
        // UIGraphicsPDFRendererContext applies rotates the result 180° —
        // rasterizing via `uiImage` sidesteps that and works across iOS
        // versions.
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        image.draw(in: CGRect(origin: .zero, size: pageSize))
    }

    private static func drawImagePage(image: UIImage, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        let bounds = context.pdfContextBounds
        let inset = bounds.insetBy(dx: imagePageMargin, dy: imagePageMargin)
        let fit = aspectFit(imageSize: image.size, in: inset.size)
        let origin = CGPoint(
            x: inset.midX - fit.width / 2,
            y: inset.midY - fit.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: fit))
    }

    // MARK: - Helpers

    private static func receiptImage(for purchase: Purchase) -> UIImage? {
        guard let data = purchase.receiptImage else { return nil }
        return UIImage(data: data)
    }

    private static func aspectFit(imageSize: CGSize, in target: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return target }
        let ratio = min(target.width / imageSize.width, target.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    private static func metadataFormat(for purchase: Purchase) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        let title = purchase.itemName.isEmpty
            ? "Kept Claim Pack"
            : "Kept Claim Pack — \(purchase.itemName)"
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: "Kept",
            kCGPDFContextCreator as String: "Kept for iOS"
        ]
        return format
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
