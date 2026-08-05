#if DEBUG
import Foundation

/// Documents/ReceiptFixtures — DEBUG capture only, never ships in Release.
enum ReceiptFixtureStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ReceiptFixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    static func save(_ fixture: ReceiptFixture) throws {
        let data = try ReceiptFixture.jsonEncoder.encode(fixture)
        try data.write(to: fileURL(for: fixture.id), options: .atomic)
    }

    static func loadAll() throws -> [ReceiptFixture] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }

        return try urls
            .compactMap { url -> ReceiptFixture? in
                let data = try Data(contentsOf: url)
                return try ReceiptFixture.jsonDecoder.decode(ReceiptFixture.self, from: data)
            }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    static func allFileURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
#endif
