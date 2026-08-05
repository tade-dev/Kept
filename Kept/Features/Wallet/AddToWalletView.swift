import PassKit
import SwiftData
import SwiftUI
import UIKit

/// Presents Apple's add-pass sheet for a signed `PKPass`.
struct AddToWalletView: UIViewControllerRepresentable {
    let pass: PKPass
    var onFinished: (_ added: Bool) -> Void

    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        let controller = PKAddPassesViewController(pass: pass)!
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(pass: pass, onFinished: onFinished)
    }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let pass: PKPass
        let onFinished: (Bool) -> Void
        private var reported = false

        init(pass: PKPass, onFinished: @escaping (Bool) -> Void) {
            self.pass = pass
            self.onFinished = onFinished
        }

        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            guard !reported else { return }
            reported = true
            let added = PKPassLibrary().containsPass(pass)
            controller.dismiss(animated: true) {
                self.onFinished(added)
            }
        }
    }
}

/// Toolbar / button that requests a signed pass and presents Add to Wallet.
struct AddToWalletButton: View {
    let purchase: Purchase
    var signingService: PassSigningService? = PassSigningService.makeDefault()

    @Environment(\.modelContext) private var modelContext
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var passToAdd: PKPass?
    @State private var pendingSerial: String?
    @State private var isPresentingAddSheet = false

    private var alreadyAdded: Bool {
        !(purchase.passRecords ?? []).isEmpty
    }

    private var hasCoverage: Bool {
        purchase.coverageEndsAt != nil || purchase.nextDeadline != nil
    }

    var body: some View {
        Button {
            Task { await start() }
        } label: {
            if isWorking {
                ProgressView()
            } else {
                Label(
                    alreadyAdded ? "Add Again" : "Add to Wallet",
                    systemImage: "wallet.pass"
                )
            }
        }
        .disabled(isWorking || signingService == nil || !hasCoverage)
        .sheet(isPresented: $isPresentingAddSheet, onDismiss: {
            passToAdd = nil
            pendingSerial = nil
        }) {
            if let passToAdd {
                AddToWalletView(pass: passToAdd) { added in
                    if added, let serial = pendingSerial {
                        savePassRecord(serialNumber: serial)
                    }
                    isPresentingAddSheet = false
                }
                .ignoresSafeArea()
            }
        }
        .alert("Couldn't add pass", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func start() async {
        guard let signingService else {
            errorMessage = PassSigningError.notConfigured.errorDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        let serial = UUID().uuidString
        pendingSerial = serial
        do {
            let pass = try await signingService.fetchPass(for: purchase, serialNumber: serial)
            passToAdd = pass
            isPresentingAddSheet = true
        } catch let error as PassSigningError {
            errorMessage = error.errorDescription
            pendingSerial = nil
        } catch {
            errorMessage = PassSigningError.underlying.errorDescription
            pendingSerial = nil
        }
    }

    private func savePassRecord(serialNumber: String) {
        let record = PassRecord(serialNumber: serialNumber, addedAt: .now)
        record.purchase = purchase
        if purchase.passRecords == nil {
            purchase.passRecords = []
        }
        purchase.passRecords?.append(record)
        modelContext.insert(record)
    }
}
