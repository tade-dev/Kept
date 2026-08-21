import SwiftUI
import SwiftData

/// Finder Icons orientation — date-grouped grid of receipt previews.
struct PurchaseGrid: View {
    let purchases: [Purchase]
    var zoomNamespace: Namespace.ID
    var layoutNamespace: Namespace.ID
    /// Purchase id to play a one-shot entry animation on. Cleared by the parent after ~1.5s.
    var highlightPurchaseID: PersistentIdentifier?
    let onDelete: (Purchase) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 20, alignment: .top)
    ]

    private var sections: [PurchaseDateSection] {
        DateGroupedPurchases.sections(from: purchases)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(section.purchases) { purchase in
                                NavigationLink(value: purchase) {
                                    FinderIconItem(
                                        purchase: purchase,
                                        isEntering: purchase.persistentModelID == highlightPurchaseID,
                                        zoomNamespace: zoomNamespace,
                                        layoutNamespace: layoutNamespace
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(purchase)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(purchase.accessibilityDescription)
                                .accessibilityAction(named: Text("Delete")) {
                                    onDelete(purchase)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } header: {
                        Text(section.title)
                            .font(.keptHeadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct FinderIconItem: View {
    let purchase: Purchase
    var isEntering: Bool = false
    var zoomNamespace: Namespace.ID
    var layoutNamespace: Namespace.ID

    /// Animation lifecycle: view mounts with scale/opacity at the "before" state
    /// when `isEntering` is true, then springs to the settled state on appear.
    @State private var settled = false

    private var showsEntry: Bool { isEntering && !settled }

    var body: some View {
        VStack(spacing: 6) {
            ReceiptThumbnail(data: purchase.receiptImage, cornerRadius: 6)
                .frame(width: 88, height: 110)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .overlay {
                    // Accent glow pulse — visible only during the entry window.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: showsEntry ? 2 : 0)
                        .blur(radius: showsEntry ? 6 : 0)
                        .opacity(showsEntry ? 0.9 : 0)
                        .allowsHitTesting(false)
                }
                .layoutMatchedThumbnail(id: purchase.transitionID, in: layoutNamespace)
                .matchedTransitionSource(id: purchase.transitionID, in: zoomNamespace)

            Text(purchase.displayMerchant)
                .font(.keptCaption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)

            Text(purchase.finderMetadata)
                .font(.keptCaption2)
                .foregroundStyle(.tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .scaleEffect(showsEntry ? 0.6 : 1.0)
        .opacity(showsEntry ? 0 : 1)
        .onAppear {
            guard isEntering else {
                settled = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                settled = true
            }
        }
    }
}
