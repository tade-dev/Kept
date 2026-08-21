import StoreKit
import SwiftUI

/// Thin wrapper around StoreKit's review request. iOS handles all the
/// hard bits — throttling to 3 prompts per 365 days, whether to show
/// at all based on prior interactions, prompt UI. We just tell it
/// "now would be a good moment" from positive product moments.
///
/// Never call from a launch handler, splash, or error path — Apple
/// explicitly warns against it and users hate it. Always tie to a
/// user-initiated positive moment (claim pack export, first wallet
/// pass added, milestone scans).
@MainActor
enum ReviewPrompter {
    /// Fires the review request against the currently-active window
    /// scene. No-op if there is no active scene (background, share
    /// extension, etc.).
    static func request() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        AppStore.requestReview(in: scene)
    }
}
