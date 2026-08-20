import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// KeptShare entry point. Reads the shared item, writes a lightweight
/// JSON handoff into the App Group inbox, and dismisses under a second.
/// No SwiftData, no CloudKit, no extraction. All processing happens in
/// the main app on next foreground.
///
/// See `Kept/Features/EmailImport/SharedInbox.swift` for the reader side.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(rootView: SavingHUD())
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedContent() }
    }

    // MARK: - Handoff

    private func handleSharedContent() async {
        let providers = collectItemProviders()
        var saved = false

        for provider in providers {
            if let html = try? await loadString(from: provider, type: UTType.html) {
                writeToInbox(source: "email", content: html)
                saved = true
                break
            }
            if let text = try? await loadString(from: provider, type: UTType.plainText) {
                writeToInbox(source: "text", content: text)
                saved = true
                break
            }
            if let url = try? await loadURL(from: provider) {
                writeToInbox(source: "url", content: url.absoluteString)
                saved = true
                break
            }
        }

        // Held so the user sees the confirmation regardless of how fast
        // the write completes. Under a second either way.
        try? await Task.sleep(for: .milliseconds(saved ? 700 : 300))
        await dismissExtension()
    }

    private func collectItemProviders() -> [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    private func loadString(from provider: NSItemProvider, type: UTType) async throws -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { value, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let str = value as? String {
                    cont.resume(returning: str)
                } else if let data = value as? Data, let str = String(data: data, encoding: .utf8) {
                    cont.resume(returning: str)
                } else if let url = value as? URL, let contents = try? String(contentsOf: url, encoding: .utf8) {
                    cont.resume(returning: contents)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: value as? URL)
            }
        }
    }

    /// Writes a JSON envelope into the App Group container's
    /// `PendingImports/` directory. Kept in-file (no shared framework) so
    /// the extension has zero source dependencies on Kept.
    ///
    /// Schema mirrors `PendingImport` in the main app; keep them in sync.
    private func writeToInbox(source: String, content: String) {
        let appGroupID = "group.com.tade.Kept.shared"
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let dir = base.appendingPathComponent("PendingImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let id = UUID()
        // Encode createdAt as ISO8601 so it survives JSON round-trip;
        // the main-app decoder uses `.iso8601` strategy to match.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let payload: [String: Any] = [
            "id": id.uuidString,
            "source": source,
            "rawContent": content,
            "createdAt": iso.string(from: .now)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    @MainActor
    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - SwiftUI HUD

private struct SavingHUD: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Saved to Kept")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("We'll finish processing when you next open the app.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(28)
            .frame(maxWidth: 300)
            .background(.thinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
