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
                            .font(.system(size: 28, weight: .light))
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
}
