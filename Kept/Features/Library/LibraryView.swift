import SwiftUI
import SwiftData
#if DEBUG
import PhotosUI
#endif

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    @AppStorage("libraryViewMode") private var viewModeRaw: String = LibraryViewMode.icons.rawValue
    /// Zoom navigation into purchase detail.
    @Namespace private var receiptNamespace
    /// Thumbnail morph between Icons / List / Gallery.
    @Namespace private var layoutNamespace

    @State private var isCapturing = false
    @State private var isSettingsPresented = false
    #if DEBUG
    @State private var isPhotoPickerPresented = false
    @State private var isFixtureCapturePresented = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var deletedTick = 0
    #endif

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .icons
    }

    private var viewModeBinding: Binding<LibraryViewMode> {
        Binding(
            get: { viewMode },
            set: { newValue in
                guard newValue != viewMode else { return }
                if reduceMotion {
                    viewModeRaw = newValue.rawValue
                } else {
                    withAnimation(.snappy(duration: 0.42, extraBounce: 0.04)) {
                        viewModeRaw = newValue.rawValue
                    }
                }
            }
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
            .task {
                await CoverageNotificationScheduler.rescheduleAll(purchases)
            }
            .toolbarTitleDisplayMode(.inline)
            .sensoryFeedback(.impact(weight: .light), trigger: deletedTick)
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .secondaryAction) {
                    Menu("Debug") {
                        Button {
                            isFixtureCapturePresented = true
                        } label: {
                            Label("Capture OCR fixture", systemImage: "text.viewfinder")
                        }
                        Button {
                            // PhotosPicker inside Menu never presents — flip a flag instead.
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Pick from Photos", systemImage: "photo.on.rectangle")
                        }
                        if !ReceiptFixtures.names.isEmpty {
                            Section("Fixtures") {
                                ForEach(ReceiptFixtures.names, id: \.self) { name in
                                    Button(name) {
                                        if let image = ReceiptFixtures.image(named: name) {
                                            pickedImage = image
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                #endif
            }
            .sheet(isPresented: $isCapturing) {
                CaptureView()
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            #if DEBUG
            .sheet(isPresented: $isFixtureCapturePresented) {
                FixtureCaptureView()
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $pickerItem,
                matching: .images
            )
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
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
                onDelete: delete(_:)
            )
        case .list:
            PurchaseList(
                purchases: purchases,
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
                onDelete: delete(_:)
            )
        case .gallery:
            PurchaseGallery(
                purchases: purchases,
                zoomNamespace: receiptNamespace,
                layoutNamespace: layoutNamespace,
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
        CoverageNotificationScheduler.cancel(for: purchase)
        modelContext.delete(purchase)
        deletedTick &+= 1
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
        .modelContainer(for: [Purchase.self, WarrantyTerm.self, PassRecord.self], inMemory: true)
}

#Preview("With items") {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
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
    _ = apple.setDuration(months: 12, byUser: false)
    apple.primaryWarranty?.confidence = 0.92
    context.insert(apple)

    let primark = Purchase(
        merchant: "Primark Stores Ltd",
        itemName: "Cargo Navy",
        price: 22,
        currency: "GBP",
        purchaseDate: Calendar.current.date(byAdding: .day, value: -400, to: .now)!
    )
    _ = primark.setReturnWindow(days: 28, byUser: false)
    primark.returnWindow?.confidence = 0.75
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
