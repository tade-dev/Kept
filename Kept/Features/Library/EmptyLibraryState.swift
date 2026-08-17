import SwiftUI

/// Empty-state for the library when the user has no receipts yet.
/// A custom receipt hero (built from SwiftUI shapes), warmer copy,
/// and a dark ink pill CTA that matches the app's wallet-pass identity.
struct EmptyLibraryState: View {
    var onScan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ReceiptHero()
                .frame(width: 148, height: 190)
                .clothWaveShimmer(isActive: !reduceMotion, amplitude: 2.5)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Start your library")
                    .font(.keptTitle2)
                    .foregroundStyle(.primary)

                Text("Snap your first receipt, Kept keeps the warranty countdown for you.")
                    .font(.keptSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 28)

            Button(action: onScan) {
                Label("Scan a receipt", systemImage: "doc.viewfinder")
                    .font(KeptFont.sans(17, weight: .semibold, relativeTo: .body))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(KeptColor.ink)
            .controlSize(.large)
            .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No receipts yet. Scan a receipt to start tracking your warranties.")
    }
}

// MARK: - Receipt hero illustration

private struct ReceiptHero: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let softInk = KeptColor.ink.opacity(0.75)
            let lineTint = Color.primary.opacity(0.14)

            ZStack {
                ReceiptShape()
                    .fill(Color.white)
                    .overlay(
                        ReceiptShape()
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )

                // Content
                VStack(alignment: .leading, spacing: h * 0.045) {
                    Text("RECEIPT")
                        .font(.system(size: w * 0.13, weight: .bold, design: .monospaced))
                        .foregroundStyle(softInk)
                        .kerning(1.5)

                    line(color: lineTint)

                    // 3 mock item rows
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(lineTint)
                                .frame(width: w * 0.42, height: h * 0.035)
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(lineTint)
                                .frame(width: w * 0.18, height: h * 0.035)
                        }
                    }

                    line(color: lineTint)

                    HStack(alignment: .center, spacing: 0) {
                        Text("TOTAL")
                            .font(.system(size: w * 0.10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(softInk)
                            .kerning(1.0)
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(softInk)
                            .frame(width: w * 0.22, height: h * 0.048)
                    }
                }
                .padding(.horizontal, w * 0.11)
                .padding(.top, h * 0.09)
                .padding(.bottom, h * 0.14)  // leaves room for the scalloped edge
            }
        }
        .accessibilityHidden(true)
    }

    private func line(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

// MARK: - Receipt shape with scalloped bottom edge

private struct ReceiptShape: Shape {
    var scallopCount: Int = 11
    var scallopDepth: CGFloat = 7
    var topCornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyBottom = rect.maxY - scallopDepth

        // Top-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Top edge → top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Right edge down to just above scallops
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom))

        // Scalloped bottom — semicircle-ish bumps pointing down (torn look)
        let scallopWidth = rect.width / CGFloat(scallopCount)
        for i in 0..<scallopCount {
            let endX = rect.maxX - CGFloat(i + 1) * scallopWidth
            let midX = endX + scallopWidth / 2
            path.addQuadCurve(
                to: CGPoint(x: endX, y: bodyBottom),
                control: CGPoint(x: midX, y: bodyBottom + scallopDepth * 2)
            )
        }

        // Left edge back to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topCornerRadius))
        path.closeSubpath()
        return path
    }
}

#Preview("Light") {
    EmptyLibraryState(onScan: {})
        .background(Color(.systemGroupedBackground))
}

#Preview("Dark") {
    EmptyLibraryState(onScan: {})
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
