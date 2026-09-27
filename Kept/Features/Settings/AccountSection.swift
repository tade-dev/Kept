import CloudKit
import SwiftUI
import UIKit


struct AccountSection: View {
    @Environment(SubscriptionAccess.self) private var subscription
    /// SettingsView owns the paywall sheet state — this section just tells
    /// it when the user tapped Upgrade.
    var onUpgradeTapped: () -> Void

    @State private var isICloudAvailable: Bool = false
    @State private var didFinishInitialCheck: Bool = false
    @State private var isRestoring: Bool = false
    @State private var restoreMessage: String?
    @State private var copiedCustomerID: Bool = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        Section {
            LabeledContent {
                iCloudStatusView
            } label: {
                Label("iCloud", systemImage: "icloud")
            }

            LabeledContent {
                proStatusView
            } label: {
                Label("Kept Pro", systemImage: "sparkles")
            }

            if subscription.isPro {
                proRows
            } else {
                Button {
                    onUpgradeTapped()
                } label: {
                    Label("Upgrade to Pro", systemImage: "arrow.up.right.square")
                }
            }

            // Always visible, regardless of Pro state. Apple's IAP
            // guidelines require a restore action reachable by any
            // user — someone reinstalling on a new device shows as
            // Free until the CloudKit-scoped auto-login completes,
            // and needs a manual fallback if that never happens
            // (offline, iCloud signed out, different Apple ID on
            // the App Store, etc.).
            restorePurchasesRow
        } header: {
            Text("Account")
        } footer: {
            Text(footerText)
        }
        .task { await refreshICloud() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
            Task { await refreshICloud() }
        }
        .alert(
            restoreMessage ?? "",
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var proRows: some View {
        Button {
            UIApplication.shared.open(manageSubscriptionsURL)
        } label: {
            Label("Manage subscription", systemImage: "creditcard")
        }

        Button {
            copyCustomerID()
        } label: {
            Label(
                copiedCustomerID ? "Copied to clipboard" : "Copy customer ID",
                systemImage: copiedCustomerID ? "checkmark" : "doc.on.doc"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityHint("Copies your RevenueCat customer ID so you can include it in a support ticket.")
    }

    private var restorePurchasesRow: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            HStack {
                Label("Restore purchases", systemImage: "arrow.clockwise")
                if isRestoring {
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - Status rows

    @ViewBuilder
    private var iCloudStatusView: some View {
        if !didFinishInitialCheck {
            ProgressView().controlSize(.small)
        } else if isICloudAvailable {
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(KeptFont.sans(15, weight: .medium, relativeTo: .subheadline))
        } else {
            Text("Not signed in")
                .foregroundStyle(.secondary)
        }
    }

    private var proStatusView: some View {
        Text(subscription.isPro ? "Active" : "Free")
            .foregroundStyle(subscription.isPro ? Color.primary : .secondary)
            .font(KeptFont.sans(15, weight: .medium, relativeTo: .subheadline))
    }

    private var footerText: String {
        guard didFinishInitialCheck else { return " " }
        if isICloudAvailable {
            return String(localized: "Your receipts, including photos, sync across every device signed in to this iCloud account. Sync is on for everyone. Pro only unlocks unlimited items and the claim pack.")
        }
        return String(localized: "Sign in to iCloud in Settings to sync your receipts, including photos, across devices. Sync is on for everyone and isn't part of Pro. Kept works fully offline without it.")
    }

    // MARK: - Actions

    private func copyCustomerID() {
        UIPasteboard.general.string = subscription.appUserID
        withAnimation { copiedCustomerID = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedCustomerID = false }
        }
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let restored = try await subscription.restorePurchases()
            restoreMessage = restored
                ? String(localized: "Purchases restored.")
                : String(localized: "No previous purchases were found on this Apple ID.")
        } catch let error as SubscriptionServiceError {
            restoreMessage = error.errorDescription ?? String(localized: "Something went wrong.")
        } catch {
            restoreMessage = String(localized: "Something went wrong.")
        }
    }

    // MARK: - iCloud check

    private func refreshICloud() async {
        let token = FileManager.default.ubiquityIdentityToken
        isICloudAvailable = token != nil
        didFinishInitialCheck = true
    }
}
