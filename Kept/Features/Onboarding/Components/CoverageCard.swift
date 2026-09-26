import SwiftUI


/// Optional proof row under the day count. Omit it and `CoverageCard` renders
/// exactly as before. Illustrative samples use `CoverageProof.illustrative`;
/// a real save can pass the receipt image bytes.
struct CoverageProof: Equatable {
    var imageData: Data? = nil
    var receiptStatus: String
    var claimPackStatus: String

    /// DESIGN-PENDING: thumbnail treatment when there is no real receipt image.
    /// The two status strings are locked product copy.
    static let illustrative = CoverageProof(
        imageData: nil,
        receiptStatus: String(localized: "Receipt ✓", comment: "Coverage card proof row"),
        claimPackStatus: String(localized: "Claim pack ready ✓", comment: "Coverage card proof row")
    )

    init(
        imageData: Data? = nil,
        receiptStatus: String = String(localized: "Receipt ✓", comment: "Coverage card proof row"),
        claimPackStatus: String = String(localized: "Claim pack ready ✓", comment: "Coverage card proof row")
    ) {
        self.imageData = imageData
        self.receiptStatus = receiptStatus
        self.claimPackStatus = claimPackStatus
    }
}

struct CoverageCard: View {
    let state: Phase
    let merchant: String
    let item: String
    let daysRemaining: Int
    var emphasized: Bool = false
    /// Opt-in. Existing call sites that omit this keep the previous layout.
    var proof: CoverageProof? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tiltPhase: Double = 0

    enum Phase {
        case covered
        case endingSoon
        case expired

        var accent: Color {
            switch self {
            case .covered:    KeptColor.covered
            case .endingSoon: KeptColor.endingSoon
            case .expired:    KeptColor.expired
            }
        }

        var label: String {
            switch self {
            case .covered:    String(localized: "Covered")
            case .endingSoon: String(localized: "Ending soon")
            case .expired:    String(localized: "Expired")
            }
        }
    }

    var body: some View {
        cardBody
            .rotation3DEffect(
                .degrees(emphasized && !reduceMotion ? tiltPhase * 5 : 0),
                axis: (x: -tiltPhase * 0.6, y: tiltPhase * 1.2, z: 0),
                perspective: 0.55
            )
            .shadow(
                color: state.accent.opacity(emphasized ? 0.26 : 0.18),
                radius: emphasized ? 30 : 22,
                x: emphasized ? tiltPhase * 10 : 0,
                y: emphasized ? 16 + tiltPhase * 5 : 12
            )
            .animation(.snappy(duration: 0.45), value: state)
            .task {
                guard emphasized, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    tiltPhase = 1
                }
            }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                statePill
                Spacer()
                shieldOrnament
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(merchant)
                    .font(KeptFont.sans(13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                Text(item)
                    .font(.keptTitle3)
                    .lineLimit(2)
            }

            Divider().opacity(0.4)

            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                if state == .expired {
                    Text("Expired")
                        .font(KeptFont.sans(44, weight: .semibold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(state.accent)
                } else {
                    Text("\(daysRemaining)")
                        .font(KeptFont.sans(56, weight: .semibold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(state.accent)
                        // Value beat counts up into Covered. A resting card does not animate.
                        .contentTransition(.numericText(countsDown: false))
                    // Two separate keys because the count renders as its own
                    // display element above; localizers can adjust the noun
                    // form directly per language.
                    Text(daysRemaining == 1 ? "day left" : "days left", comment: "Coverage countdown subtitle next to the big day number")
                        .font(.keptSubheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let proof {
                Divider().opacity(0.4)
                proofRow(proof)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Color(.secondarySystemBackground))

                if emphasized {
                    SpecularShimmer(
                        cornerRadius: Radius.xl,
                        duration: 2.6,
                        reduceMotion: reduceMotion
                    )
                    .allowsHitTesting(false)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(state.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - Shield ornament

    @ViewBuilder
    private var shieldOrnament: some View {
        if emphasized {
            ZStack {
                CountdownRing(
                    fraction: ringFraction,
                    tint: state.accent,
                    lineWidth: 2.5
                )
                .frame(width: 38, height: 38)

                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(state.accent)
                    .font(.keptSubheadline)
            }
        } else {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(state.accent)
                .font(.keptTitle3)
        }
    }

    /// Maps daysRemaining to a 0–1 fraction against a 14-day baseline. Clamps at extremes.
    private var ringFraction: Double {
        if state == .expired { return 0 }
        return max(0, min(1, Double(daysRemaining) / 14.0))
    }

    // MARK: - Bits

    private func proofRow(_ proof: CoverageProof) -> some View {
        HStack(spacing: Spacing.sm) {
            proofThumbnail(proof)
            Text(proof.receiptStatus)
            Text(proof.claimPackStatus)
            Spacer(minLength: 0)
        }
        .font(KeptFont.sans(12, weight: .semibold, relativeTo: .caption))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func proofThumbnail(_ proof: CoverageProof) -> some View {
        Group {
            if let data = proof.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // DESIGN-PENDING: illustrative receipt thumbnail.
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 36, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityHidden(true)
    }

    private var statePill: some View {
        Text(state.label)
            .font(KeptFont.sans(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(state.accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(state.accent.opacity(0.14), in: Capsule())
    }
}

#Preview("Compact") {
    VStack(spacing: 16) {
        CoverageCard(state: .covered, merchant: "Apple", item: "AirPods Pro", daysRemaining: 214)
        CoverageCard(state: .endingSoon, merchant: "Sony", item: "WH-1000XM5", daysRemaining: 3)
        CoverageCard(state: .expired, merchant: "IKEA", item: "MALM Dresser", daysRemaining: 0)
    }
    .padding()
}

#Preview("Hero — covered") {
    CoverageCard(state: .covered, merchant: "Sony", item: "WH-1000XM5 Headphones", daysRemaining: 14, emphasized: true)
        .padding()
}

#Preview("Hero — ending soon") {
    CoverageCard(state: .endingSoon, merchant: "Sony", item: "WH-1000XM5 Headphones", daysRemaining: 3, emphasized: true)
        .padding()
}

#Preview("Hero — expired") {
    CoverageCard(state: .expired, merchant: "Sony", item: "WH-1000XM5 Headphones", daysRemaining: 0, emphasized: true)
        .padding()
}

#Preview("Hero — covered with proof") {
    CoverageCard(
        state: .covered,
        merchant: SampleCoverageCard.merchant,
        item: SampleCoverageCard.item,
        daysRemaining: SampleCoverageCard.daysRemaining,
        emphasized: true,
        proof: .illustrative
    )
    .padding()
}
