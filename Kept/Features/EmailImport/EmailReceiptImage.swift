import SwiftUI

/// A receipt-shaped rendering of an imported email. Not a screenshot of
/// the original HTML — a Kept-curated visual that plays the role of
/// `Purchase.receiptImage` for email imports.
///
/// Downstream this image flows through the same slots a scanned
/// receipt does: library thumbnail, PurchaseDetailView top card,
/// claim pack PDF page 2. Having *something* there matters more than
/// having it look like a phone photograph.
struct EmailReceiptImage: View {
    let merchant: String?
    let lines: [String]
    let capturedAt: Date

    /// Fixed render size in points. Matches receipt-photo aspect
    /// (portrait, ~2:3) so it composes cleanly in the same UI slots.
    static let renderSize = CGSize(width: 600, height: 900)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            body(lines: lines)
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(width: Self.renderSize.width, height: Self.renderSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color.secondary.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(merchantDisplay)
                    .font(KeptFont.sans(20, weight: .bold, relativeTo: .title3))
                    .lineLimit(1)
                Text("Order confirmation email")
                    .font(KeptFont.sans(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func body(lines: [String]) -> some View {
        let trimmed = Array(lines.prefix(Self.maxDisplayLines))
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(trimmed.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if lines.count > Self.maxDisplayLines {
                Text("+ \(lines.count - Self.maxDisplayLines) more lines")
                    .font(KeptFont.sans(10, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Imported \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(KeptFont.sans(9, weight: .regular, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("KEPT")
                .font(KeptFont.sans(10, weight: .bold, relativeTo: .caption2))
                .tracking(2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Formatting

    private var merchantDisplay: String {
        let trimmed = (merchant ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Imported receipt" : trimmed
    }

    /// Cap prevents oversized emails from rendering huge images.
    /// 60 lines is enough to see the important content without
    /// consuming the whole page.
    private static let maxDisplayLines = 60
}

// MARK: - Rendering helper

extension EmailReceiptImage {
    /// Rasterises the view at 2× to `UIImage`. Called from the main
    /// app during pending-import drain — cheap (~20ms on-device) since
    /// we're not going through WKWebView.
    @MainActor
    static func render(merchant: String?, lines: [String], capturedAt: Date = .now) -> UIImage? {
        let view = EmailReceiptImage(merchant: merchant, lines: lines, capturedAt: capturedAt)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(renderSize)
        renderer.scale = 2
        let image = renderer.uiImage
        if image == nil {
            NSLog("[Kept.email] EmailReceiptImage.render returned nil (merchant=\(merchant ?? "nil"), lines=\(lines.count))")
        } else {
            NSLog("[Kept.email] EmailReceiptImage.render produced image \(image!.size)")
        }
        return image
    }
}

#Preview {
    EmailReceiptImage(
        merchant: "Amazon.co.uk",
        lines: [
            "Your Amazon.co.uk order",
            "Thanks for your order, Ade!",
            "Order confirmation for order #204-8271933-8452301.",
            "Sony WH-1000XM5 Wireless Noise Cancelling Headphones - Black",
            "£299.99",
            "Sold by: Amazon EU S.a.r.L.",
            "Items subtotal: £299.99",
            "Order Total: £299.99",
            "Order date: 20 August 2026"
        ],
        capturedAt: .now
    )
}
