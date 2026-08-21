import SwiftData
import SwiftUI

/// Finder List orientation — date-grouped rows with morphing thumbnails.
struct PurchaseList: View {
    let purchases: [Purchase]
    var zoomNamespace: Namespace.ID
    var layoutNamespace: Namespace.ID
    let onDelete: (Purchase) -> Void

    private var sections: [PurchaseDateSection] {
        DateGroupedPurchases.sections(from: purchases)
    }

    var body: some View {
        // ScrollView (not List) so `matchedGeometryEffect` can interpolate
        // thumbnail frames when switching orientations.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.purchases) { purchase in
                            NavigationLink(value: purchase) {
                                PurchaseRow(
                                    purchase: purchase,
                                    zoomNamespace: zoomNamespace,
                                    layoutNamespace: layoutNamespace
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDelete(purchase)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            // VoiceOver reachability for delete — context
                            // menu long-press is technically accessible but
                            // slow. An explicit rotor action is instant.
                            .accessibilityAction(named: Text("Delete")) {
                                onDelete(purchase)
                            }

                            if purchase.persistentModelID != section.purchases.last?.persistentModelID {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    } header: {
                        Text(section.title)
                            .font(.keptHeadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                            .background(.background)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }
}
