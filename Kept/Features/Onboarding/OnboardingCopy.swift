import SwiftUI

/// Copy for the first-run redesign.
///
/// `DESIGN-PENDING` marks placeholder wording DesignBot is still replacing.
/// Strings without that mark are locked product copy.
enum OnboardingCopy {
    // DESIGN-PENDING: Welcome headline. Leads with the moment something broke.
    static let welcomeHeadline = LocalizedStringKey("Something broke. You have everything you need.")

    // DESIGN-PENDING: Welcome subhead.
    static let welcomeSubhead = LocalizedStringKey("The receipt, the dates, and the claim — already together.")

    // DESIGN-PENDING: key-moment screen title (value beat).
    static let valueBeatTitle = LocalizedStringKey("And this is already waiting.")

    /// DESIGN-PENDING: wording only. The facts are not optional:
    /// receipts sync through CloudKit when iCloud is signed in, Vision OCR
    /// runs on device, and the extract worker receives recognized text — not
    /// a claim that photos never leave the phone.
    static let privacyLine = LocalizedStringKey("Receipts sync with your iCloud account. The photo is read on your phone; only the recognized text is sent to fill in the details.")

    /// Locked caption under the empty-library sample card.
    static let emptyLibraryCaption = LocalizedStringKey("When something breaks, this is what you'll see.")

    // DESIGN-PENDING: empty-library body. Must not use countdown framing.
    static let emptyLibraryBody = LocalizedStringKey("Scan a receipt once. If it breaks, the proof is already here.")

    /// Locked headline on the first-save sheet.
    static let firstSaveHeadline = LocalizedStringKey("If it breaks, it's all here.")
}

/// Static sample shown on the value beat and the empty library.
/// Not a `Purchase`. Never inserted into SwiftData and never counted
/// toward the free-tier cap or the library total.
enum SampleCoverageCard {
    // DESIGN-PENDING: sample merchant, item, and the day count the card rests on.
    static let merchant = "Sony"
    static let item = "WH-1000XM5 Headphones"
    static let daysRemaining = 348
    static let phase = CoverageCard.Phase.covered
}
