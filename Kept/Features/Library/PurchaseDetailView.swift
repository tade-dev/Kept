import SwiftUI
import SwiftData

struct PurchaseDetailView: View {
    @Bindable var purchase: Purchase

    @State private var warrantyMonthsText: String = ""
    @State private var returnDaysText: String = ""
    @State private var priceText: String = ""
    @State private var isShowingFullImage = false

    var body: some View {
        Form {
            if let data = purchase.receiptImage, let image = UIImage(data: data) {
                Section {
                    Button {
                        isShowingFullImage = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section("Purchase") {
                TextField("Merchant", text: $purchase.merchant)
                TextField("Item", text: $purchase.itemName)
                HStack {
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: priceText) { _, newValue in
                            let normalised = newValue.replacingOccurrences(of: ",", with: ".")
                            purchase.price = Decimal(string: normalised) ?? 0
                        }
                    TextField("CUR", text: $purchase.currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker(
                    "Purchased",
                    selection: $purchase.purchaseDate,
                    displayedComponents: .date
                )
                .onChange(of: purchase.purchaseDate) { _, _ in
                    recomputeExpiry()
                }
            }

            Section {
                HStack {
                    TextField("Days to return", text: $returnDaysText)
                        .keyboardType(.numberPad)
                        .onChange(of: returnDaysText) { _, newValue in
                            _ = purchase.setReturnWindow(days: Int(newValue) ?? 0, byUser: true)
                        }
                    if purchase.returnWindow?.source == .inferred {
                        inferredChip
                    }
                }
                if let term = purchase.returnWindow {
                    LabeledContent("Return by") {
                        Text(term.expiryDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Return window")
            } footer: {
                if purchase.returnWindow == nil {
                    Text("Optional. Clothing and many retailers allow returns for a short window.")
                } else if purchase.returnWindow?.source == .inferred {
                    Text("Kept guessed this return window. Edit it to override.")
                }
            }

            Section {
                HStack {
                    TextField("Duration (months)", text: $warrantyMonthsText)
                        .keyboardType(.numberPad)
                        .onChange(of: warrantyMonthsText) { _, newValue in
                            _ = purchase.setDuration(months: Int(newValue) ?? 0, byUser: true)
                        }
                    if purchase.primaryWarranty?.source == .inferred {
                        inferredChip
                    }
                }
                if let warranty = purchase.primaryWarranty {
                    LabeledContent("Expires") {
                        Text(warranty.expiryDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Warranty")
            } footer: {
                if purchase.primaryWarranty == nil {
                    Text("No repair warranty tracked. Leave blank for fashion and consumables.")
                } else if purchase.primaryWarranty?.source == .inferred {
                    Text("Kept guessed this length. Edit it to override.")
                }
            }

            Section("Notes") {
                TextField("Add a note", text: $purchase.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            warrantyMonthsText = purchase.primaryWarranty.map { String($0.durationMonths) } ?? ""
            returnDaysText = purchase.returnWindow.map { String($0.durationDays) } ?? ""
            priceText = purchase.price > 0 ? formatDecimal(purchase.price) : ""
        }
        .fullScreenCover(isPresented: $isShowingFullImage) {
            if let data = purchase.receiptImage, let image = UIImage(data: data) {
                FullReceiptViewer(image: image)
            }
        }
    }

    private var inferredChip: some View {
        Text("inferred")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var displayTitle: String {
        let trimmed = purchase.merchant.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Receipt" : trimmed
    }

    private func recomputeExpiry() {
        if let warranty = purchase.primaryWarranty {
            _ = purchase.setDuration(
                months: warranty.durationMonths,
                byUser: warranty.source == .userProvided
            )
        }
        if let returnTerm = purchase.returnWindow {
            _ = purchase.setReturnWindow(
                days: returnTerm.durationDays,
                byUser: returnTerm.source == .userProvided
            )
        }
    }

    private func formatDecimal(_ value: Decimal) -> String {
        // POSIX, no grouping — avoids "2,849" → Decimal("2.849") on edit.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct FullReceiptViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let purchase = Purchase(
        merchant: "Primark",
        itemName: "Cargo Navy",
        price: 22,
        currency: "GBP",
        purchaseDate: .now
    )
    _ = purchase.setReturnWindow(days: 28, byUser: false)
    container.mainContext.insert(purchase)
    return NavigationStack {
        PurchaseDetailView(purchase: purchase)
    }
    .modelContainer(container)
}
