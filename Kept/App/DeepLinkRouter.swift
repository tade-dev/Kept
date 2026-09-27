import Foundation
import Observation

/// Single source of truth for pending deep-link destinations.
///
/// `RootView` presents surfaces (the scanner sheet, for now) when
/// `pending` matches — but only after onboarding + the trial-entry
/// paywall have cleared, so a cold-launch deep link into Capture waits
/// out those gates instead of racing them. The router itself doesn't
/// care about the gates; it just holds the intent.
///
/// URL formats consumed:
///   • Universal link (App Store In-App Event, App Preview, share):
///       https://getkept.xyz/app/scan
///   • Custom scheme fallback (dev testing, Notes long-press):
///       kept://scan
@MainActor
@Observable
final class DeepLinkRouter {
    /// A destination the user has asked to land in but hasn't reached yet
    /// (typically because a fullScreenCover is still in flight). `nil` == no
    /// pending work. Views that satisfy the intent should clear the value.
    var pending: Destination?

    enum Destination: Equatable {
        /// Open the receipt-scan / Capture flow as a sheet on top of the
        /// Library. Used by the "Launch Week: First Scans" App Store event
        /// and any share link that says "start scanning."
        case scan
    }

    /// Parse an incoming URL and, if it maps to a supported destination,
    /// stage it. Unrecognised URLs are ignored — safer than crashing on a
    /// stray share-sheet link. Idempotent: calling twice with the same
    /// URL just leaves `pending` at the same value.
    func handle(_ url: URL) {
        guard let destination = Destination(url: url) else { return }
        pending = destination
    }
}

extension DeepLinkRouter.Destination {
    /// Recognised shapes:
    ///   https://getkept.xyz/app/scan   (universal link)
    ///   kept://scan                    (custom scheme)
    /// Anything else returns nil so unknown links fall through to Safari.
    init?(url: URL) {
        // Custom scheme: `kept://<host>` — the destination is the host,
        // not the path, because iOS strips the trailing slash from empty
        // paths (`kept://scan` → host="scan", path="").
        if url.scheme?.lowercased() == "kept" {
            switch url.host?.lowercased() {
            case "scan": self = .scan; return
            default:     return nil
            }
        }

        // Universal link: `https://getkept.xyz/app/<destination>`. Path
        // components include the leading "/", so we skip empties.
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
           url.host?.lowercased() == "getkept.xyz" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0].lowercased() == "app" {
                switch parts[1].lowercased() {
                case "scan": self = .scan; return
                default:     return nil
                }
            }
        }

        return nil
    }
}
