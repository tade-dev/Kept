import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Kept

@Suite("Receipt image import")
struct ReceiptImageImportTests {
    @Test("a camera request opens the scanner and an imported image does not")
    func captureRequestRouting() {
        let camera = ReceiptCaptureRequest.camera()
        #expect(camera.usesCameraScanner)
        #expect(camera.image == nil)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let imported = ReceiptCaptureRequest.imported(image)
        #expect(imported.usesCameraScanner == false)
        #expect(imported.image === image)
    }

    @Test("PDF scale stays at 3× until the long edge would pass 3000 pixels")
    func renderScale() {
        #expect(ReceiptImageImport.renderScale(for: CGSize(width: 595, height: 842)) == 3)
        let capped = ReceiptImageImport.renderScale(for: CGSize(width: 2000, height: 4000))
        #expect(abs(capped - (3000.0 / 4000.0)) < 0.0001)
        #expect(ReceiptImageImport.renderScale(for: .zero) == 1)
        #expect(ReceiptImageImport.renderScale(for: CGSize(width: -10, height: 20)) == 1)
    }

    @Test("PDF import renders the first page only, at the OCR pixel size")
    func firstPDFPage() throws {
        let data = twoPagePDF(pageSize: CGSize(width: 200, height: 100))
        guard case .success(let image) = ReceiptImageImport.image(fromPDFData: data) else {
            Issue.record("Expected a rendered first page")
            return
        }
        #expect(image.cgImage?.width == 600)
        #expect(image.cgImage?.height == 300)
        let pixel = try #require(rgba(of: image, at: CGPoint(x: 300, y: 150)))
        #expect(pixel.red > 200)
        #expect(pixel.blue < 40)
    }

    @Test("empty, garbage, and non-image bytes fail closed")
    func unreadableInputs() {
        #expect(failure(ReceiptImageImport.image(fromPDFData: Data())) == .unreadablePDF)
        #expect(failure(ReceiptImageImport.image(fromPDFData: Data("not a pdf".utf8))) == .unreadablePDF)
        #expect(failure(ReceiptImageImport.image(fromImageData: Data())) == .unreadableImage)
        #expect(failure(ReceiptImageImport.image(fromImageData: Data("%PDF-1.4".utf8))) == .unreadableImage)
    }

    @Test("photo bytes decode back into an image")
    func imageBytes() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        }
        let data = try #require(source.pngData())
        guard case .success(let image) = ReceiptImageImport.image(fromImageData: data) else {
            Issue.record("Expected a decoded image")
            return
        }
        #expect(image.size.width == 8)
        #expect(image.size.height == 6)
    }

    @Test("a file-importer cancel is ignored and other read errors are not")
    func cancellation() {
        let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        #expect(ReceiptImageImport.isCancellation(cancelled))
        #expect(ReceiptImageImport.isCancellation(CancellationError()))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: cancelled]
        )
        #expect(ReceiptImageImport.isCancellation(wrapped))
        let corrupt = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        #expect(ReceiptImageImport.isCancellation(corrupt) == false)
    }

    private func failure<T>(_ result: Result<T, ReceiptImageImport.Failure>) -> ReceiptImageImport.Failure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    private func twoPagePDF(pageSize: CGSize) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(bounds)
            context.beginPage()
            UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
            context.fill(bounds)
        }
    }

    private func rgba(of image: UIImage, at point: CGPoint) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Bitmap origin is bottom-left. The page is a solid colour, so the
        // sample only checks that the first page was red rather than blue.
        let flippedY = height - 1 - y
        let offset = (flippedY * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }
}
