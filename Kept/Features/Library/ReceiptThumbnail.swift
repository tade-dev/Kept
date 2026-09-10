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
        return trimmed.isEmpty ? String(localized: "Unnamed", comment: "Fallback when a purchase has no merchant") : trimmed
    }

    var displayItem: String {
        let trimmed = itemName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "Receipt", comment: "Fallback when a purchase has no item name") : trimmed
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
            parts.append(String(localized: "from \(merchantTrimmed)", comment: "VoiceOver: '<item> from <merchant>'"))
        }

        let dateString = purchaseDate.formatted(.dateTime.day().month().year())
        parts.append(String(localized: "purchased \(dateString)", comment: "VoiceOver purchase-date fragment"))

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
        let isReturn = term.kind == .returnWindow

        if days > 1 {
            return isReturn
                ? String(localized: "return window ends in \(days) days", comment: "VoiceOver return-window countdown; needs plural handling")
                : String(localized: "warranty ends in \(days) days", comment: "VoiceOver warranty countdown; needs plural handling")
        }
        if days == 1 {
            return isReturn
                ? String(localized: "return window ends tomorrow")
                : String(localized: "warranty ends tomorrow")
        }
        if days == 0 {
            return isReturn
                ? String(localized: "return window ends today")
                : String(localized: "warranty ends today")
        }
        let ago = -days
        return isReturn
            ? String(localized: "return window ended \(ago) days ago", comment: "VoiceOver expired return; needs plural handling")
            : String(localized: "warranty ended \(ago) days ago", comment: "VoiceOver expired warranty; needs plural handling")
    }
}
