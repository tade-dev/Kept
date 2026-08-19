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
    @Environment(SubscriptionAccess.self) private var subscription
    /// Sticky flag: after a free user's first-ever successful Wallet-pass add,
    /// we show the paywall exactly once as a soft prompt. See AGENTS.md.
    @AppStorage("kept.hasShownPaywallAfterFirstPass") private var hasShownPaywallAfterFirstPass = false

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var passToAdd: PKPass?
    @State private var pendingSerial: String?
    @State private var isPresentingAddSheet = false
    @State private var addedTick = 0
    @State private var isPresentingPaywall = false

    private var hasCoverage: Bool {
        purchase.coverageEndsAt != nil || purchase.nextDeadline != nil
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
                        addedTick &+= 1
                        maybeShowFirstPassPaywall()
                    }
                    isPresentingAddSheet = false
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isPresentingPaywall) {
            PaywallView(reason: .firstPassAdded)
                .presentationDetents([.large])
        }
        .sensoryFeedback(.success, trigger: addedTick)
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
        Button {
            Task { await start() }
        } label: {
            ZStack {
                Image("AddToAppleWallet")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .opacity(isWorking ? 0 : 1)

                if isWorking {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking || signingService == nil)
        .accessibilityLabel("Add to Apple Wallet")
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

    /// Shows the paywall once — after a free user's very first Wallet-pass
    /// add. Soft prompt with a "Not now" option, dismissed = no penalty.
    /// See AGENTS.md / Monetisation.
    private func maybeShowFirstPassPaywall() {
        guard !subscription.isPro, !hasShownPaywallAfterFirstPass else { return }
        hasShownPaywallAfterFirstPass = true
        // Small delay so the Wallet add sheet fully dismisses first — stacking
        // sheets on the same run loop tick is visually jarring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPresentingPaywall = true
        }
    }
}
