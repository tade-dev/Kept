import Foundation

/// When the one-time first-save sheet may appear.
/// Pure: it does not read UserDefaults or insert a purchase.
enum FirstSavePayoffPolicy {
    /// True only for the save that moves the library from 0 purchases to 1,
    /// and only if that sheet has not already been shown.
    static func shouldPresent(previousCount: Int, newCount: Int, hasSeen: Bool) -> Bool {
        !hasSeen && previousCount == 0 && newCount == 1
    }
}
