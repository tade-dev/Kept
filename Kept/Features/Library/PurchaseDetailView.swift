import SwiftUI
import SwiftData

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var purchase: Purchase

    @State private var warrantyMonthsText: String = ""
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
                    TextField("Duration (months)", text: $warrantyMonthsText)
                        .keyboardType(.numberPad)
                        .onChange(of: warrantyMonthsText) { _, newValue in
                            applyWarrantyChange(months: Int(newValue) ?? 0)
                        }
                    if purchase.warranty?.source == .inferred {
                        Text("inferred")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let warranty = purchase.warranty {
                    LabeledContent("Expires") {
                        Text(warranty.expiryDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Warranty")
            } footer: {
                if purchase.warranty == nil {
                    Text("No warranty tracked. Enter a duration to add one.")
                } else if purchase.warranty?.source == .inferred {
                    Text("Kept guessed this length. Edit it to override.")
                }
            }

            Section("Notes") {
                TextField("Add a note", text: $purchase.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(displayTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .task {
            warrantyMonthsText = purchase.warranty.map { String($0.durationMonths) } ?? ""
            priceText = purchase.price > 0 ? formatDecimal(purchase.price) : ""
        }
        .fullScreenCover(isPresented: $isShowingFullImage) {
            if let data = purchase.receiptImage, let image = UIImage(data: data) {
                FullReceiptViewer(image: image)
            }
        }
    }

    private var displayTitle: String {
        let trimmed = purchase.merchant.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Receipt" : trimmed
    }

    private func applyWarrantyChange(months: Int) {
        if months <= 0 {
            if let existing = purchase.warranty {
                modelContext.delete(existing)
                purchase.warranty = nil
            }
            return
        }

        let expiry = Calendar.current.date(
            byAdding: .month,
            value: months,
            to: purchase.purchaseDate
        ) ?? purchase.purchaseDate

        if let existing = purchase.warranty {
            existing.durationMonths = months
            existing.expiryDate = expiry
            existing.source = .userSet
        } else {
            let warranty = WarrantyTerm(
                durationMonths: months,
                expiryDate: expiry,
                source: .userSet,
                confidence: 1.0
            )
            purchase.warranty = warranty
        }
    }

    private func recomputeExpiry() {
        guard let warranty = purchase.warranty else { return }
        warranty.expiryDate = Calendar.current.date(
            byAdding: .month,
            value: warranty.durationMonths,
            to: purchase.purchaseDate
        ) ?? purchase.purchaseDate
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
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
