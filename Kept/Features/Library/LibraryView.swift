import SwiftUI
import SwiftData
#if DEBUG
import PhotosUI
#endif

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    @AppStorage("libraryViewMode") private var viewModeRaw: String = LibraryViewMode.icons.rawValue
    @Namespace private var receiptNamespace

    @State private var isCapturing = false
    #if DEBUG
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    #endif

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .icons
    }

    private var viewModeBinding: Binding<LibraryViewMode> {
        Binding(
            get: { viewMode },
            set: { viewModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty {
                    emptyState
                } else {
                    modeContent
                }
            }
            .navigationTitle("Kept")
            .navigationDestination(for: Purchase.self) { purchase in
                PurchaseDetailView(purchase: purchase)
                    .navigationTransition(.zoom(sourceID: purchase.transitionID, in: receiptNamespace))
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Scan receipt", systemImage: "doc.viewfinder")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    viewModeMenu
                }
                #if DEBUG
                ToolbarItem(placement: .secondaryAction) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Pick from Photos (debug)", systemImage: "photo.on.rectangle")
                    }
                }
                #endif
            }
            .sheet(isPresented: $isCapturing) {
                CaptureView()
            }
            #if DEBUG
            .sheet(item: Binding(
                get: { pickedImage.map(IdentifiedImage.init) },
                set: { if $0 == nil { pickedImage = nil } }
            )) { wrapper in
                CaptureView(image: wrapper.image)
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    }
                    pickerItem = nil
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewMode {
        case .icons:
            PurchaseGrid(
                purchases: purchases,
                namespace: receiptNamespace,
                onDelete: delete(_:)
            )
        case .list:
            List {
                ForEach(DateGroupedPurchases.sections(from: purchases)) { section in
                    Section(section.title) {
                        ForEach(section.purchases) { purchase in
                            NavigationLink(value: purchase) {
                                PurchaseRow(
                                    purchase: purchase,
                                    namespace: receiptNamespace
                                )
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                delete(section.purchases[index])
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        case .gallery:
            PurchaseGallery(
                purchases: purchases,
                namespace: receiptNamespace,
                onDelete: delete(_:)
            )
        }
    }

    private var viewModeMenu: some View {
        Menu {
            Picker("View", selection: viewModeBinding) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("View", systemImage: viewMode.systemImage)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing kept yet", systemImage: "tray")
        } description: {
            Text("Scan a receipt to start tracking your warranties.")
        } actions: {
            Button {
                isCapturing = true
            } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func delete(_ purchase: Purchase) {
        modelContext.delete(purchase)
    }

    #if DEBUG
    private struct IdentifiedImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    #endif
}

#Preview("Empty") {
    LibraryView()
        .modelContainer(for: [Purchase.self, WarrantyTerm.self], inMemory: true)
}

#Preview("With items") {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let apple = Purchase(
        merchant: "Apple Chermside",
        itemName: "iPhone 16 Pro Max 1TB",
        price: 2849,
        currency: "AUD",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    )
    apple.warranty = WarrantyTerm(
        durationMonths: 12,
        expiryDate: Calendar.current.date(byAdding: .month, value: 11, to: .now)!,
        source: .inferred,
        confidence: 0.92
    )
    context.insert(apple)

    let primark = Purchase(
        merchant: "Primark Stores Ltd",
        itemName: "Cargo Navy",
        price: 22,
        currency: "GBP",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -400, to: .now)!
    )
    primark.warranty = WarrantyTerm(
        durationMonths: 12,
        expiryDate: Calendar.current.date(byAdding: .day, value: -35, to: .now)!,
        source: .inferred,
        confidence: 0.75
    )
    context.insert(primark)

    let woolies = Purchase(
        merchant: "Woolworths",
        itemName: "Grocery shop",
        price: 87.42,
        currency: "AUD",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!
    )
    context.insert(woolies)

    return LibraryView()
        .modelContainer(container)
}
