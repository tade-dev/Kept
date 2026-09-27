import SwiftUI

/// Final first-run copy from the design handoff.
enum OnboardingCopy {
    static let welcomeHeadline = LocalizedStringKey("Something broke?\nKnow if it's covered.")
    static let welcomeSubhead = LocalizedStringKey("Scan the receipt once. Kept keeps the cover and the proof.")
    static let welcomeCTA = LocalizedStringKey("See how it works")

    static let keyMomentContext = LocalizedStringKey("Your headphones just stopped working.")
    static let keyMomentQuestion = LocalizedStringKey("Still covered?")
    static let keyMomentPayoff = LocalizedStringKey("Your proof and cover, right there.")

    static let privacyTitle = LocalizedStringKey("Your photos stay yours")
    /// `/extract` receives OCR text only. Photos still sync to the user's own
    /// iCloud, so this line says we never send them to our servers. Keep it
    /// identical to `INFOPLIST_KEY_NSCameraUsageDescription`.
    static let privacyLine = LocalizedStringKey("We never send your receipt photos to our servers. To read one, we send only its text.")

    static let emptyLibraryCaption = LocalizedStringKey("When something breaks, this is what you'll see.")
    static let emptyLibraryTitle = LocalizedStringKey("Start your library")

    static let firstSaveHeadline = LocalizedStringKey("If it breaks, it's all here.")
    static let firstSaveSubtitle = LocalizedStringKey("Your first receipt is saved.")
    static let walletCaption = LocalizedStringKey("Adds a countdown pass to Apple Wallet.")
    static let claimPackCaptionFree = LocalizedStringKey("For the day you need to claim. Included with Kept Pro.")
    static let claimPackCaptionPro = LocalizedStringKey("A one-page PDF with your receipt, ready to send.")
}

/// Scripted key-moment card. Not a `Purchase`.
///
/// Kept meets the user three times with the same hero product — this
/// scripted card, `SampleCoverageCard` on the empty library, and the
/// `DemoReceipt` image on the key-moment proof row — so the demo reads
/// as one coherent story instead of three unrelated products. Currys
/// with a big-ticket TV is the everyday UK anxiety-driver that matches
/// the "laptop dies in month 13" note in the App Store description.
enum KeyMomentScript {
    static let merchant = "Currys"
    static let item = "Samsung 55″ QLED TV"
    /// ~16 months into a 24-month guarantee — safely inside the coverage
    /// window so the covered pill reads as reassurance, not a lucky escape.
    static let daysRemaining = 486
    static let phase = CoverageCard.Phase.covered
    /// Stillness after the step is inserted, then the card resolves.
    static let questionMilliseconds = 1200
    /// Gap between the resolve and the payoff line.
    static let payoffMilliseconds = 550
}

/// Empty-library sample. Not a `Purchase`, never inserted or counted.
/// Mirrors `KeyMomentScript` on purpose — see the note there.
enum SampleCoverageCard {
    static let merchant = "Currys"
    static let item = "Samsung 55″ QLED TV"
    static let daysRemaining = 486
    static let phase = CoverageCard.Phase.covered
}

enum DemoAssets {
    /// Cropped receipt for the key-moment proof row. Nil falls back to the
    /// `doc.text` thumbnail inside `ReceiptThumbnail`.
    static var receiptJPEG: Data? {
        guard let image = UIImage(named: "DemoReceipt") else { return nil }
        return image.jpegData(compressionQuality: 0.85) ?? image.pngData()
    }
}
