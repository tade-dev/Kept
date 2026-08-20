import SwiftData
import SwiftUI

/// A Kept-branded, print-ready summary page for a single purchase.
///
/// Rendered at A4 size (595×842pt) by `ClaimPackRenderer`. The receipt image
/// is intentionally *not* embedded here — it gets its own page so it can scale
/// as large as possible without distorting the summary layout.
struct ClaimPackDocument: View {
    let purchase: Purchase
    let generatedAt: Date

    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            Divider()

            purchaseBlock

            coverageBlock

            if !purchase.lineItems.isEmpty {
                lineItemsBlock
            }

            if !purchase.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notesBlock
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(Self.margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    // MARK: - Blocks

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Claim Pack")
                    .font(KeptFont.sans(30, weight: .bold, relativeTo: .largeTitle))
                Text("Prepared by Kept on \(generatedAt.formatted(date: .long, time: .omitted))")
                    .font(KeptFont.sans(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("KEPT")
                .font(KeptFont.sans(16, weight: .bold, relativeTo: .headline))
                .tracking(3)
                .foregroundStyle(.secondary)
        }
    }

    private var purchaseBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Purchase")
            row("Item",     purchase.itemName.isEmpty ? "—" : purchase.itemName)
            row("Merchant", purchase.merchant.isEmpty ? "—" : purchase.merchant)
            row("Purchased", purchase.purchaseDate.formatted(date: .long, time: .omitted))
            row("Amount",    formattedPrice)
            if !purchase.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                row("Serial no.", purchase.serialNumber)
            }
        }
    }

    @ViewBuilder
    private var coverageBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Coverage")

            if let warranty = purchase.primaryWarranty {
                warrantyRow(
                    label: "Warranty",
                    months: warranty.durationMonths,
                    expiry: warranty.expiryDate,
                    source: warranty.source
                )
            } else {
                row("Warranty", "None recorded")
            }

            if let returnTerm = purchase.returnWindow {
                returnRow(
                    label: "Return window",
                    days: returnTerm.durationDays,
                    expiry: returnTerm.expiryDate,
                    source: returnTerm.source
                )
            }
        }
    }

    private var lineItemsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Items on receipt")
            VStack(spacing: 6) {
                ForEach(purchase.lineItems) { item in
                    HStack {
                        Text(item.name)
                            .font(KeptFont.sans(12, weight: .regular, relativeTo: .footnote))
                        Spacer()
                        Text(item.price, format: .number.precision(.fractionLength(0...2)))
                            .font(KeptFont.sans(12, weight: .medium, relativeTo: .footnote))
                            .monospacedDigit()
                    }
                    Divider().opacity(0.3)
                }
                HStack {
                    Text("Total")
                        .font(KeptFont.sans(13, weight: .semibold, relativeTo: .footnote))
                    Spacer()
                    Text(formattedPrice)
                        .font(KeptFont.sans(13, weight: .semibold, relativeTo: .footnote))
                        .monospacedDigit()
                }
                .padding(.top, 4)
            }
        }
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notes")
            Text(purchase.notes)
                .font(KeptFont.sans(12, weight: .regular, relativeTo: .footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text("Kept · Receipts that remember")
                    .font(KeptFont.sans(10, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(KeptFont.sans(10, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Row helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(KeptFont.sans(11, weight: .semibold, relativeTo: .caption))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(KeptFont.sans(12, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
            Spacer(minLength: 0)
        }
    }

    private func warrantyRow(label: String, months: Int, expiry: Date, source: WarrantySource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(KeptFont.sans(12, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text("\(months) \(months == 1 ? "month" : "months") — expires \(expiry.formatted(date: .long, time: .omitted))")
                    .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                sourceChip(source)
                Text(remainingDescription(for: expiry))
                    .font(KeptFont.sans(11, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 110)
        }
    }

    private func returnRow(label: String, days: Int, expiry: Date, source: WarrantySource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(KeptFont.sans(12, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text("\(days) \(days == 1 ? "day" : "days") — return by \(expiry.formatted(date: .long, time: .omitted))")
                    .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                sourceChip(source)
                Text(remainingDescription(for: expiry))
                    .font(KeptFont.sans(11, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 110)
        }
    }

    private func sourceChip(_ source: WarrantySource) -> some View {
        Text(source == .userProvided ? "confirmed by owner" : "estimated")
            .font(KeptFont.sans(9, weight: .medium, relativeTo: .caption2))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (source == .userProvided ? Color.black : Color.secondary.opacity(0.35)),
                in: Capsule()
            )
            .foregroundStyle(source == .userProvided ? .white : .primary)
    }

    // MARK: - Formatting

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = purchase.currency
        return formatter.string(from: purchase.price as NSDecimalNumber) ?? "\(purchase.price)"
    }

    private func remainingDescription(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s") remaining" }
        if days == 0 { return "expires today" }
        let abs = -days
        return "expired \(abs) day\(abs == 1 ? "" : "s") ago"
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Purchase.self, WarrantyTerm.self, PassRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let purchase = Purchase(
        merchant: "Apple Store",
        itemName: "MacBook Pro 14\"",
        price: 2499,
        currency: "USD",
        purchaseDate: .now.addingTimeInterval(-60 * 60 * 24 * 30)
    )
    _ = purchase.setDuration(months: 12, byUser: true)
    _ = purchase.setReturnWindow(days: 14, byUser: false)
    purchase.notes = "AppleCare+ eligible. Serial on box."
    container.mainContext.insert(purchase)
    return ClaimPackDocument(purchase: purchase, generatedAt: .now)
}
