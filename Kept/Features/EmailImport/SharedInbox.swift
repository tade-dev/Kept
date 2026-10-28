import Foundation

/// A single item the Share Extension handed off for the main app to
/// finish processing. Persisted as JSON in the App Group container so
/// both processes can reach it without a shared SwiftData store.
///
/// The extension writes the *raw* content it received from the host app.
/// All parsing (HTML strip, text passthrough, URL fetch) happens on the
/// main-app side at drain time — that way the extension has no dependency
/// on Kept's extraction module and stays tiny.
struct PendingImport: Codable, Identifiable, Sendable {
    var id: UUID
    var source: Source
    var rawContent: String
    var createdAt: Date

    enum Source: String, Codable, Sendable {
        /// HTML body (typically from Mail sharing an order confirmation).
        /// Drain-time processor runs `HTMLReceiptStripper` before extraction.
        case email
        /// Plain text (shared from Notes, Messages, Slack, etc.).
        /// Fed directly to extraction with each line preserved.
        case text
        /// A URL. v1: stored as-is, user reviews. Later: server-side fetch.
        case url
    }
}

/// One-way mailbox from the Share Extension to the main app.
///
/// Extension calls `write(_:)` and dismisses.
/// Main app calls `drain()` on foreground and consumes each item.
///
/// Uses a plain files-in-a-directory scheme rather than a shared SwiftData
/// store — SwiftData + CloudKit + App Group is fiddly and this hand-off
/// doesn't need CloudKit sync (the items get materialised into the real
/// store as full Purchases only after the user confirms).
enum SharedInbox {
    /// Group ID configured on both targets' entitlements.
    static let appGroupID = "group.com.tade.Kept.shared"
    private static let directoryName = "PendingImports"

    /// Persists a pending import for the main app to pick up.
    /// Fails silently — a dropped share is a poor experience, but a
    /// crashed share is worse.
    static func write(_ item: PendingImport) {
        guard let dir = ensureDirectory() else { return }
        let url = dir.appendingPathComponent("\(item.id.uuidString).json")
        let encoder = JSONEncoder()
        // Match the Share Extension, which writes `createdAt` as ISO-8601.
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns pending imports oldest-first and leaves them in place.
    /// Callers should invoke `remove(_:)` after handing each one to the
    /// user, so mid-session crashes don't lose the queue.
    static func peekAll() -> [PendingImport] {
        guard let dir = try? directoryURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items: [PendingImport] = files
            .filter { $0.pathExtension == "json" }
            .compactMap {
                guard let data = try? Data(contentsOf: $0) else { return nil }
                return try? decoder.decode(PendingImport.self, from: data)
            }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    /// Deletes an item after it's been handled. Idempotent — a missing
    /// file is a no-op, not an error.
    static func remove(_ item: PendingImport) {
        guard let dir = try? directoryURL() else { return }
        let url = dir.appendingPathComponent("\(item.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Directory management

    private static func directoryURL() throws -> URL {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw SharedInboxError.appGroupUnavailable
        }
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func ensureDirectory() -> URL? {
        guard let dir = try? directoryURL() else { return nil }
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }
}

enum SharedInboxError: Error {
    case appGroupUnavailable
}
