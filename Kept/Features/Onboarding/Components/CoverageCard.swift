import SwiftUI


struct CoverageCard: View {
    let state: Phase
    let merchant: String
    let item: String
    let daysRemaining: Int
    var emphasized: Bool = false

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
            case .covered:    "Covered"
            case .endingSoon: "Ending soon"
            case .expired:    "Expired"
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
                        .contentTransition(.numericText(countsDown: true))
                    Text(daysRemaining == 1 ? "day left" : "days left")
                        .font(.keptSubheadline)
                        .foregroundStyle(.secondary)
                }
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
