import SwiftUI

/// Drains the shared inbox on foreground and presents the extraction
/// confirm sheet for each pending item, one at a time.
///
/// Wraps a child view via `.sheet(item:)` so any parent can adopt the
/// behaviour with a single modifier. The `PendingImport` is removed
/// from the inbox as soon as the sheet is dismissed (whether the user
/// confirmed or swiped away) — resharing from Mail is the way to try
/// again if a scan is abandoned.
///
/// No `Purchase.state` migration required: pending items live as JSON
/// files in the App Group until the user confirms, at which point
/// `ExtractionConfirmView.commitSave` creates the `Purchase` through
/// the same code path as camera capture.
struct PendingImportPresenter: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var current: PendingImport?
    @State private var extraction: ReceiptExtraction?
    @State private var lines: [RecognizedLine] = []
    @State private var renderedImage: UIImage?
    @State private var isPreparing = false

    func body(content: Content) -> some View {
        content
            .task { await drainNext() }
            .onChange(of: scenePhase) { _, new in
                if new == .active { Task { await drainNext() } }
            }
            .sheet(item: $current, onDismiss: {
                // By the time SwiftUI calls onDismiss, `$current` has
                // already been set to nil — so we can't reach the item
                // from here. The item is instead removed from the inbox
                // eagerly in `drainNext()` at present-time, meaning:
                // - Save: nothing extra to do (already removed).
                // - Swipe-dismiss without saving: still removed. If the
                //   user wants to reprocess, they re-share from Mail.
                //   Simpler contract than "if you swipe, we hold on to
                //   it and re-present on every foreground forever".
                extraction = nil
                lines = []
                renderedImage = nil
                Task { await drainNext() }
            }) { _ in
                if let extraction {
                    NavigationStack {
                        ExtractionConfirmView(
                            image: renderedImage,
                            ocrLines: lines,
                            extraction: extraction,
                            onSave: { _ in
                                current = nil
                                self.extraction = nil
                                lines = []
                                renderedImage = nil
                                Task { await drainNext() }
                            }
                        )
                    }
                }
            }
    }

    @MainActor
    private func drainNext() async {
        guard !isPreparing, current == nil else { return }
        guard let next = SharedInbox.peekAll().first else { return }
        isPreparing = true
        defer { isPreparing = false }

        let candidateLines = buildLines(from: next)
        guard !candidateLines.isEmpty else {
            // Nothing usable — drop the item so we don't re-attempt on
            // every foreground.
            SharedInbox.remove(next)
            return
        }

        let service = DefaultExtractionService()
        let extraction: ReceiptExtraction
        if let receipt = try? await service.extract(from: candidateLines) {
            extraction = ReceiptExtraction.from(receipt: receipt, confidences: nil, lineItems: [])
        } else {
            // Extraction failed (network, empty, etc.). Present anyway
            // with empty fields so the user can add manually rather than
            // silently losing the import.
            extraction = ReceiptExtraction.empty
        }

        // Render a receipt-shaped image for every non-URL import so the
        // confirm view + eventual Purchase have a proper visual (library
        // thumbnail, claim pack PDF page 2). Applies equally to emails
        // (from Mail's HTML share) and plain-text shares (from Mail's
        // Select-All → Share, which strips to text) — both benefit
        // from a rendered card. URL-only shares carry no content
        // worth visualising.
        let image: UIImage? = {
            guard next.source != .url else { return nil }
            return EmailReceiptImage.render(
                merchant: extraction.merchant.value,
                lines: candidateLines.map(\.text),
                capturedAt: next.createdAt
            )
        }()

        NSLog("[Kept.email] Presenting confirm sheet with image=\(image == nil ? "nil" : "\(image!.size)"), lines=\(candidateLines.count)")

        // Remove BEFORE presenting. If the user swipes the sheet away
        // without saving, the item is gone — matches the "one-shot
        // review, re-share to retry" contract. If we removed on save
        // only, swipe-dismiss would leave the file in the inbox and
        // every subsequent foreground would re-present it.
        SharedInbox.remove(next)

        self.lines = candidateLines
        self.extraction = extraction
        self.renderedImage = image
        self.current = next
    }

    private func buildLines(from item: PendingImport) -> [RecognizedLine] {
        switch item.source {
        case .email:
            return HTMLReceiptStripper.strip(item.rawContent)
        case .text:
            return item.rawContent
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { RecognizedLine(text: $0, confidence: 1, boundingBox: .zero) }
        case .url:
            // URL-only shares don't carry order content — drop for v1.
            // Follow-up: server-side fetch, or open the URL in an
            // in-app browser and let the user re-share the rendered page.
            return []
        }
    }
}

extension View {
    /// Attach to a top-level view to have any pending Share Extension
    /// imports surface as a confirm sheet on foreground.
    func presentsPendingImports() -> some View {
        modifier(PendingImportPresenter())
    }
}
