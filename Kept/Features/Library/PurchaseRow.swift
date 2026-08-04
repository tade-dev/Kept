import SwiftUI

/// Finder List orientation row — thumbnail, name, blue metadata.
struct PurchaseRow: View {
    let purchase: Purchase
    var namespace: Namespace.ID?

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumbnail(data: purchase.receiptImage, cornerRadius: 5)
                .frame(width: 36, height: 44)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                .modifier(OptionalMatchedTransition(
                    id: purchase.transitionID,
                    namespace: namespace
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

                WarrantyStatusBadge(warranty: purchase.warranty)
            }
        }
        .padding(.vertical, 4)
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

struct WarrantyStatusBadge: View {
    let warranty: WarrantyTerm?

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
        guard let warranty else { return .none }
        let days = Calendar.current.dateComponents([.day], from: .now, to: warranty.expiryDate).day ?? 0
        return days < 0 ? .expired(daysAgo: -days) : .active(daysLeft: days)
    }

    private var label: String {
        switch status {
        case .none:
            "no warranty"
        case .active(let days) where days == 0:
            "Expires today"
        case .active(let days) where days == 1:
            "1 day left"
        case .active(let days) where days < 60:
            "\(days) days left"
        case .active(let days):
            "\(days / 30) mo left"
        case .expired(let days) where days == 0:
            "Expired today"
        case .expired(let days) where days < 30:
            "Expired \(days)d ago"
        case .expired(let days):
            "Expired \(days / 30)mo ago"
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
