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
                    .font(.body)
                    .lineLimit(1)

                Text(purchase.displayItem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(purchase.finderMetadata)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .lineLimit(1)

                CoverageStatusBadge(term: purchase.nextDeadline)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
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
            "No Deadline"
        case .active(let days) where days == 0:
            isReturn ? "Return today" : "Expires today"
        case .active(let days) where days == 1:
            isReturn ? "Return · 1 day" : "1 day left"
        case .active(let days) where days < 60:
            isReturn ? "Return · \(days)d" : "\(days) days left"
        case .active(let days):
            isReturn ? "Return · \(days / 30)mo" : "\(days / 30) mo left"
        case .expired(let days) where days == 0:
            isReturn ? "Return ended" : "Expired today"
        case .expired(let days) where days < 30:
            isReturn ? "Return ended \(days)d ago" : "Expired \(days)d ago"
        case .expired(let days):
            isReturn ? "Return ended \(days / 30)mo ago" : "Expired \(days / 30)mo ago"
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
