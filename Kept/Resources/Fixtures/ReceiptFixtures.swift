import UIKit

enum ReceiptFixtures {
    static let bundleSubdirectory = "Resources/Fixtures/Receipts"

    static var names: [String] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "Fixtures/Receipts")
            ?? Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "Resources/Fixtures/Receipts")
        else {
            // Flat copy into bundle root as a last resort.
            return (1...10).compactMap { index -> String? in
                let prefixes = [
                    "01_apple_store", "02_primark", "03_woolworths", "04_best_buy", "05_ikea",
                    "06_jb_hi_fi", "07_tesco", "08_currys", "09_target", "10_harvey_norman",
                ]
                guard index - 1 < prefixes.count else { return nil }
                return Bundle.main.url(forResource: prefixes[index - 1], withExtension: "png") != nil
                    ? prefixes[index - 1] : nil
            }
        }
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    static func image(named name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Fixtures/Receipts")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/Fixtures/Receipts")
            ?? Bundle.main.url(forResource: name, withExtension: "png"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return UIImage(named: name)
    }
}
