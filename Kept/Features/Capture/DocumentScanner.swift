import SwiftUI
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    enum ScanError: Error, LocalizedError {
        case cancelled
        case scannerUnavailable
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Scan cancelled."
            case .scannerUnavailable: "This device can't scan documents."
            case .underlying(let error): error.localizedDescription
            }
        }
    }

    let onFinish: (Result<[UIImage], ScanError>) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Result<[UIImage], ScanError>) -> Void

        init(onFinish: @escaping (Result<[UIImage], ScanError>) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(.success(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.failure(.cancelled))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFinish(.failure(.underlying(error)))
        }
    }
}
