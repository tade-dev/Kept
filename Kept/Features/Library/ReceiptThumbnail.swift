import SwiftUI
import SwiftData

struct ReceiptThumbnail: View {
    let data: Data?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "doc.text")
                            .font(KeptFont.sans(28, weight: .regular, relativeTo: .title))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension Purchase {
    var displayMerchant: String {
        let trimmed = merchant.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Unnamed" : trimmed
    }

    var displayItem: String {
        let trimmed = itemName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Receipt" : trimmed
    }

    var finderMetadata: String {
        if price > 0 {
            price.formatted(.currency(code: currency))
        } else {
            purchaseDate.formatted(.dateTime.day().month().year())
        }
    }

    /// Stable id for zoom / matched transition source.
    var transitionID: String {
        String(describing: persistentModelID)
    }

    /// Full spoken description for VoiceOver — combines item, merchant,
    /// purchase date, and coverage state into a single sentence so the
    /// user gets the whole picture without drilling into the card.
    /// Used as the `accessibilityLabel` on receipt cards across all
    /// three view modes (Icons / List / Gallery).
    var accessibilityDescription: String {
        var parts: [String] = [displayItem]

        let merchantTrimmed = merchant.trimmingCharacters(in: .whitespaces)
        if !merchantTrimmed.isEmpty {
            parts.append("from \(merchantTrimmed)")
        }

        parts.append("purchased \(purchaseDate.formatted(.dateTime.day().month().year()))")

        if let term = nextDeadline {
            parts.append(coverageDescription(for: term))
        }

        return parts.joined(separator: ", ")
    }

    private func coverageDescription(for term: WarrantyTerm) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: term.expiryDate)
        ).day ?? 0
        let kindWord = term.kind == .returnWindow ? "return window" : "warranty"

        if days > 1 {
            return "\(kindWord) ends in \(days) days"
        }
        if days == 1 {
            return "\(kindWord) ends tomorrow"
        }
        if days == 0 {
            return "\(kindWord) ends today"
        }
        let ago = -days
        return "\(kindWord) ended \(ago) \(ago == 1 ? "day" : "days") ago"
    }
}
