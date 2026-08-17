import CloudKit
import SwiftUI

/// Settings section that shows iCloud sign-in status + Pro subscription state.
/// Uses `FileManager.ubiquityIdentityToken` for the quick "is iCloud
/// available" check (synchronous, doesn't need the CloudKit entitlement) and
/// falls back to CKContainer for the record ID display when the entitlement
/// is present. Never spins forever.
struct AccountSection: View {
    @Environment(SubscriptionAccess.self) private var subscription
    /// SettingsView owns the paywall sheet state — this section just tells
    /// it when the user tapped Upgrade.
    var onUpgradeTapped: () -> Void

    @State private var isICloudAvailable: Bool = false
    @State private var iCloudUserRecordName: String?
    @State private var didFinishInitialCheck: Bool = false

    var body: some View {
        Section {
            LabeledContent {
                iCloudStatusView
            } label: {
                Label("iCloud", systemImage: "icloud")
            }

            if let recordName = iCloudUserRecordName {
                LabeledContent("User ID") {
                    Text(recordName.masked)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LabeledContent {
                proStatusView
            } label: {
                Label("Kept Pro", systemImage: "sparkles")
            }

            Button {
                onUpgradeTapped()
            } label: {
                Label(subscription.service.isPro ? "Manage subscription" : "Upgrade to Pro",
                      systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Account")
        } footer: {
            Text(footerText)
        }
        .task { await refreshICloud() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
            Task { await refreshICloud() }
        }
    }

    // MARK: - Row content

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
        Text(subscription.service.isPro ? "Active" : "Free")
            .foregroundStyle(subscription.service.isPro ? Color.primary : .secondary)
            .font(KeptFont.sans(15, weight: .medium, relativeTo: .subheadline))
    }

    private var footerText: String {
        guard didFinishInitialCheck else { return " " }
        if isICloudAvailable {
            return "Your receipts sync across every device signed in to this iCloud account. Sync is free — Pro only unlocks unlimited items and the claim pack."
        }
        return "Sign in to iCloud in Settings to sync your receipts across devices. Kept works fully offline without it."
    }

    // MARK: - iCloud check

    private func refreshICloud() async {
        // 1. Fast, entitlement-free availability check.
        let token = FileManager.default.ubiquityIdentityToken
        isICloudAvailable = token != nil
        didFinishInitialCheck = true

        // 2. Only try for the record ID if iCloud is available AND we have
        //    the CloudKit entitlement. Skip cleanly if the container throws.
        guard token != nil else {
            iCloudUserRecordName = nil
            return
        }
        // Timeout so a hung CloudKit call can't keep this hidden work running.
        let fetch = Task { () -> String? in
            do {
                let recordID = try await CKContainer.default().userRecordID()
                return recordID.recordName
            } catch {
                return nil
            }
        }
        let timeout = Task { () -> String? in
            try? await Task.sleep(for: .seconds(2))
            fetch.cancel()
            return nil
        }
        let name = await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask { await fetch.value }
            group.addTask { await timeout.value }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
        iCloudUserRecordName = name
    }
}

private extension String {
    /// Masks a stable-but-opaque ID like `_abc123def456ghi` so we can show it
    /// in Settings without spilling the full string. `_abc1…6ghi`.
    var masked: String {
        guard count > 8 else { return self }
        let head = prefix(5)
        let tail = suffix(4)
        return "\(head)…\(tail)"
    }
}
