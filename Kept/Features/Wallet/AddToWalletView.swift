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

/// System `PKAddPassButton` — required for in-app Add to Apple Wallet CTAs.
private struct PKAddPassButtonView: UIViewRepresentable {
    var style: PKAddPassButtonStyle
    var isEnabled: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: style)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        button.isEnabled = isEnabled
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        if button.addPassButtonStyle != style {
            button.addPassButtonStyle = style
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}

/// Requests a signed pass and presents Add to Apple Wallet via the system badge.
struct AddToWalletButton: View {
    let purchase: Purchase
    var signingService: PassSigningService? = PassSigningService.makeDefault()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var passToAdd: PKPass?
    @State private var pendingSerial: String?
    @State private var isPresentingAddSheet = false

    private var hasCoverage: Bool {
        purchase.coverageEndsAt != nil || purchase.nextDeadline != nil
    }

    private var buttonStyle: PKAddPassButtonStyle {
        // Outline on dark surfaces per Apple Wallet badge guidelines.
        colorScheme == .dark ? .blackOutline : .black
    }

    var body: some View {
        Group {
            if hasCoverage {
                badge
            }
        }
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

    private var badge: some View {
        ZStack {
            PKAddPassButtonView(
                style: buttonStyle,
                isEnabled: !isWorking && signingService != nil
            ) {
                Task { await start() }
            }
            .fixedSize()
            .opacity(isWorking ? 0 : 1)
            .accessibilityLabel("Add to Apple Wallet")

            if isWorking {
                ProgressView()
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 48)
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
