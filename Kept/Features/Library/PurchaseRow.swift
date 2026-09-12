import SwiftUI

/// Finder List orientation row — thumbnail, name, blue metadata.
struct PurchaseRow: View {
    let purchase: Purchase
    var zoomNamespace: Namespace.ID?
    var layoutNamespace: Namespace.ID?

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumbnail(data: purchase.receiptImage, cornerRadius: 5)
                .frame(width: 36, height: 44)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                .modifier(OptionalLayoutMatch(
                    id: purchase.transitionID,
                    namespace: layoutNamespace
                ))
                .modifier(OptionalMatchedTransition(
                    id: purchase.transitionID,
                    namespace: zoomNamespace
                ))

            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.displayMerchant)
                    .font(.keptBody)
                    .lineLimit(1...2)

                Text(purchase.displaySubtitle)
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(purchase.finderMetadata)
                    .font(.keptSubheadline)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                CoverageStatusBadge(term: purchase.nextDeadline)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(purchase.accessibilityDescription)
    }
}

private struct OptionalLayoutMatch: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.layoutMatchedThumbnail(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct OptionalMatchedTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct CoverageStatusBadge: View {
    let term: WarrantyTerm?

    var body: some View {
        Text(label)
            .font(KeptFont.sans(11, weight: .medium, relativeTo: .caption2))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private enum Status {
        case none
        case active(daysLeft: Int)
        case expired(daysAgo: Int)
    }

    private var status: Status {
        guard let term else { return .none }
        let days = Calendar.current.dateComponents([.day], from: .now, to: term.expiryDate).day ?? 0
        return days < 0 ? .expired(daysAgo: -days) : .active(daysLeft: days)
    }

    private var isReturn: Bool {
        term?.kind == .returnWindow
    }

    private var label: String {
        switch status {
        case .none:
            String(localized: "No Deadline")
        case .active(let days) where days == 0:
            isReturn ? String(localized: "Return today") : String(localized: "Expires today")
        case .active(let days) where days < 60:
            isReturn
                ? String(localized: "Return · \(days)d", comment: "Compact days badge, e.g. 'Return · 5d'")
                : String(localized: "\(days) days left", comment: "Days remaining until warranty expires; needs plural handling")
        case .active(let days):
            isReturn
                ? String(localized: "Return · \(days / 30)mo", comment: "Compact months badge, e.g. 'Return · 3mo'")
                : String(localized: "\(days / 30) mo left", comment: "Months remaining until warranty expires; needs plural handling")
        case .expired(let days) where days == 0:
            isReturn ? String(localized: "Return ended") : String(localized: "Expired today")
        case .expired(let days) where days < 30:
            isReturn
                ? String(localized: "Return ended \(days)d ago", comment: "Days since return window ended")
                : String(localized: "Expired \(days)d ago", comment: "Days since warranty expired")
        case .expired(let days):
            isReturn
                ? String(localized: "Return ended \(days / 30)mo ago", comment: "Months since return window ended")
                : String(localized: "Expired \(days / 30)mo ago", comment: "Months since warranty expired")
        }
    }

    private var tint: Color {
        switch status {
        case .none: .secondary
        case .active(let days) where days < 14: .orange
        case .active: .green
        case .expired: .red
        }
    }
}

/// Back-compat name used by older call sites.
typealias WarrantyStatusBadge = CoverageStatusBadge

extension CoverageStatusBadge {
    init(warranty: WarrantyTerm?) {
        self.init(term: warranty)
    }
}
