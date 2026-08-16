#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only: scan → OCR → eyeball lines → label expected → save JSON fixtures.
struct FixtureCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    private let ocr: any OCRService

    @State private var isScannerPresented = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    @State private var ocrLines: [OCRLine] = []
    @State private var fixtureID = UUID().uuidString
    @State private var notes = ""

    @State private var merchant = ""
    @State private var itemName = ""
    @State private var totalText = ""
    @State private var currencyCode = ""
    @State private var purchaseDate = ""

    @State private var savedCount = 0

    init(ocr: any OCRService = VisionOCRService()) {
        self.ocr = ocr
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                actionsSection
                if !ocrLines.isEmpty {
                    expectedSection
                    notesSection
                    linesSection
                }
            }
            .font(.keptBody)  // cascades Bricolage to all Text in the Form
            .navigationTitle("OCR fixtures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save fixture") { saveFixture() }
                        .disabled(ocrLines.isEmpty || isBusy)
                }
            }
            .fullScreenCover(isPresented: $isScannerPresented) {
                DocumentScanner { result in
                    isScannerPresented = false
                    handleScan(result)
                }
                .ignoresSafeArea()
            }
            .alert("Fixture capture", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { refreshSavedCount() }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Saved on device", value: "\(savedCount)")
            if let statusMessage {
                Text(statusMessage)
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
            }
            Text("Image never leaves the phone. Only OCR text is written into the fixture JSON.")
                .font(.keptFootnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        Section("Capture") {
            Button {
                isScannerPresented = true
            } label: {
                Label(ocrLines.isEmpty ? "Scan receipt" : "Rescan", systemImage: "doc.viewfinder")
            }
            .disabled(isBusy)

            Button {
                exportAll()
            } label: {
                Label("Export all", systemImage: "square.and.arrow.up")
            }
            .disabled(savedCount == 0 || isBusy)
        }
    }

    private var expectedSection: some View {
        Section("Expected (fill after eyeballing lines)") {
            TextField("Merchant", text: $merchant)
            TextField("Item name", text: $itemName)
            HStack {
                TextField("Total", text: $totalText)
                    .keyboardType(.decimalPad)
                TextField("CUR", text: $currencyCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
            }
            TextField("Purchase date (yyyy-MM-dd)", text: $purchaseDate)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("e.g. faded total, glare on date", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var linesSection: some View {
        Section("OCR lines (\(ocrLines.count), top → bottom)") {
            ForEach(Array(ocrLines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.text)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Text(
                        String(
                            format: "#%02d  x=%.2f y=%.2f w=%.2f h=%.2f",
                            index + 1, line.x, line.y, line.width, line.height
                        )
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions

    private func handleScan(_ result: Result<[UIImage], DocumentScanner.ScanError>) {
        switch result {
        case .failure(.cancelled):
            return
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let images):
            guard let image = images.first else {
                errorMessage = "Scan produced no pages."
                return
            }
            Task { await runOCR(on: image) }
        }
    }

    @MainActor
    private func runOCR(on image: UIImage) async {
        isBusy = true
        statusMessage = "Running Vision OCR…"
        defer { isBusy = false }
        do {
            let recognized = try await ocr.recognize(in: image)
            ocrLines = recognized.map(OCRLine.init)
            fixtureID = UUID().uuidString
            statusMessage = "OCR returned \(ocrLines.count) lines. Check quality, fill expected, then Save."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func saveFixture() {
        let expected = makeExpected()
        let fixture = ReceiptFixture(
            id: fixtureID,
            capturedAt: .now,
            ocrLines: ocrLines,
            expected: expected,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try ReceiptFixtureStore.save(fixture)
            refreshSavedCount()
            statusMessage = "Saved \(fixture.id).json (\(ocrLines.count) lines)."
            // Ready for the next receipt; keep expected fields so similar shops are faster.
            fixtureID = UUID().uuidString
        } catch {
            errorMessage = "Couldn't save fixture: \(error.localizedDescription)"
        }
    }

    private func makeExpected() -> ExpectedValues? {
        let m = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cur = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let date = purchaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = Decimal(string: totalText.replacingOccurrences(of: ",", with: "."))

        let hasAnything = !m.isEmpty || !item.isEmpty || total != nil || !cur.isEmpty || !date.isEmpty
        guard hasAnything else { return nil }

        return ExpectedValues(
            merchant: m.isEmpty ? nil : m,
            itemName: item.isEmpty ? nil : item,
            total: total,
            currencyCode: cur.isEmpty ? nil : cur,
            purchaseDate: date.isEmpty ? nil : date
        )
    }

    private func exportAll() {
        do {
            let sourceURLs = try ReceiptFixtureStore.allFileURLs()
            guard !sourceURLs.isEmpty else {
                errorMessage = "No fixtures saved yet."
                return
            }
            // Copy into tmp — sharing Documents URLs via SwiftUI sheet often blanks out.
            let exportDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("KeptFixtureExport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            var items: [URL] = []
            for source in sourceURLs {
                let dest = exportDir.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: dest)
                items.append(dest)
            }
            SharePresenter.present(items: items)
            statusMessage = "Sharing \(items.count) fixture file(s)."
        } catch {
            errorMessage = "Couldn't export fixtures: \(error.localizedDescription)"
        }
    }

    private func refreshSavedCount() {
        savedCount = (try? ReceiptFixtureStore.loadAll().count) ?? 0
    }
}

// MARK: - Share (UIKit — SwiftUI .sheet + UIActivityViewController is blank on device)

private enum SharePresenter {
    @MainActor
    static func present(items: [Any]) {
        guard let presenter = topViewController() else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

#Preview {
    FixtureCaptureView(
        ocr: PreviewFixtureOCR()
    )
}

private struct PreviewFixtureOCR: OCRService {
    func recognize(in image: UIImage) async throws -> [RecognizedLine] {
        [
            RecognizedLine(
                text: "Apple Chermside",
                confidence: 0.99,
                boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.04)
            ),
            RecognizedLine(
                text: "Total $ 2,849.00",
                confidence: 0.97,
                boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.04)
            ),
        ]
    }
}
#endif
