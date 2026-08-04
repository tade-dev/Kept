import SwiftData
import SwiftUI

/// Finder Gallery orientation — large preview, glass inspector, filmstrip.
struct PurchaseGallery: View {
    let purchases: [Purchase]
    var namespace: Namespace.ID
    let onDelete: (Purchase) -> Void

    @State private var selection: PersistentIdentifier?

    private var selected: Purchase? {
        purchases.first(where: { $0.persistentModelID == selection }) ?? purchases.first
    }

    var body: some View {
        Group {
            if purchases.isEmpty {
                ContentUnavailableView(
                    "No receipts",
                    systemImage: "photo.stack",
                    description: Text("Scan one to see it here.")
                )
            } else {
                VStack(spacing: 0) {
                    previewPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    filmstrip
                        .padding(.vertical, 12)
                }
            }
        }
        .onAppear {
            if selection == nil {
                selection = purchases.first?.persistentModelID
            }
        }
        .onChange(of: purchases) { _, newValue in
            if let current = selection,
               !newValue.contains(where: { $0.persistentModelID == current }) {
                selection = newValue.first?.persistentModelID
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let purchase = selected {
            NavigationLink(value: purchase) {
                ZStack(alignment: .bottom) {
                    previewImage(for: purchase)
                        .matchedTransitionSource(id: purchase.transitionID, in: namespace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                        .padding(.bottom, 88)

                    inspector(for: purchase)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    onDelete(purchase)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func previewImage(for purchase: Purchase) -> some View {
        if let data = purchase.receiptImage, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func inspector(for purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(purchase.displayMerchant)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(purchase.displayItem)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .center) {
                Text(purchase.purchaseDate, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if purchase.price > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(purchase.price, format: .currency(code: purchase.currency))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                WarrantyStatusBadge(warranty: purchase.warranty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(purchases) { purchase in
                        let isSelected = purchase.persistentModelID == selected?.persistentModelID
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                selection = purchase.persistentModelID
                            }
                        } label: {
                            ReceiptThumbnail(data: purchase.receiptImage, cornerRadius: 6)
                                .frame(width: 54, height: 68)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.clear,
                                            lineWidth: 2.5
                                        )
                                }
                                .opacity(isSelected ? 1 : 0.72)
                        }
                        .buttonStyle(.plain)
                        .id(purchase.persistentModelID)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
