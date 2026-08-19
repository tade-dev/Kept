import PDFKit
import SwiftUI
import UIKit

/// Sheet that renders the claim-pack PDF at full fidelity via `PDFKit.PDFView`
/// and lets the user hit an Export button in the toolbar to fire the native
/// iOS share sheet. Users can scroll and pinch-zoom the preview before sharing.
struct ClaimPackPreviewSheet: View {
    let url: URL
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingShare = false

    var body: some View {
        NavigationStack {
            PDFPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Claim pack")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(KeptFont.sans(15, weight: .semibold, relativeTo: .body))
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            isPresentingShare = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(isPresented: $isPresentingShare) {
                    ShareSheet(url: url)
                        .presentationDetents([.medium, .large])
                }
        }
    }
}

// MARK: - PDFView wrapper

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
