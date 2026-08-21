import SwiftData
import SwiftUI

/// Finder Gallery orientation — large preview, glass inspector, filmstrip.
struct PurchaseGallery: View {
    let purchases: [Purchase]
    var zoomNamespace: Namespace.ID
    var layoutNamespace: Namespace.ID
    let onDelete: (Purchase) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: PersistentIdentifier?

    private var selected: Purchase? {
        purchases.first(where: { $0.persistentModelID == selection }) ?? purchases.first
    }

    var body: some View {
        Group {
            if purchases.isEmpty {
                ContentUnavailableView {
                    Label("No receipts", systemImage: "photo.stack")
                        .font(.keptTitle3)
                } description: {
                    Text("Scan one to see it here.")
                        .font(.keptSubheadline)
                }
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
                        .layoutMatchedThumbnail(id: purchase.transitionID, in: layoutNamespace)
                        .matchedTransitionSource(id: purchase.transitionID, in: zoomNamespace)
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
                        .font(KeptFont.sans(56, weight: .regular, relativeTo: .largeTitle))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func inspector(for purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(purchase.displayMerchant)
                .font(.keptTitle3)
                .foregroundStyle(.primary)
                .lineLimit(1...2)

            Text(purchase.displayItem)
                .font(.keptSubheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...2)

            HStack(alignment: .center) {
                Text(purchase.purchaseDate, format: .dateTime.day().month().year())
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)

                if purchase.price > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(purchase.price, format: .currency(code: purchase.currency))
                        .font(.keptSubheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                CoverageStatusBadge(term: purchase.nextDeadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(purchase.accessibilityDescription)
        .accessibilityAction(named: Text("Delete")) {
            onDelete(purchase)
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(purchases) { purchase in
                        let isSelected = purchase.persistentModelID == selected?.persistentModelID
                        Button {
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                                selection = purchase.persistentModelID
                            }
                        } label: {
                            ReceiptThumbnail(data: purchase.receiptImage, cornerRadius: 6)
                                .frame(width: 54, height: 68)
                                // Selected item's geometry lives on the large preview.
                                .modifier(FilmstripLayoutMatch(
                                    id: purchase.transitionID,
                                    namespace: layoutNamespace,
                                    enabled: !isSelected
                                ))
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
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct FilmstripLayoutMatch: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.layoutMatchedThumbnail(id: id, in: namespace)
        } else {
            content
        }
    }
}
