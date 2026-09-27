import SwiftUI

struct CoverageCard: View {
    let state: Phase
    let merchant: String
    let item: String
    let daysRemaining: Int
    var emphasized: Bool = false
    /// False is the key-moment "checking" beat. Merchant and item stay visible.
    var isResolved: Bool = true
    /// Adds the proof row under the countdown. Nil keeps the previous layout.
    var proof: Proof? = nil
    var remainingStyle: RemainingStyle = .days
    /// Sample tag, no shadow, lighter stroke. Use with `emphasized == false`.
    var isSample: Bool = false
    /// Spoken prefix for a scripted card, e.g. "Example". Sample cards say "Sample" on their own.
    var spokenLeadIn: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tiltPhase: Double = 0

    struct Proof: Equatable {
        var receiptImage: Data?
        var showsClaimPackReady: Bool
    }

    enum RemainingStyle { case days, adaptive }

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
                .degrees(emphasized && !reduceMotion && !isSample ? tiltPhase * 5 : 0),
                axis: (x: -tiltPhase * 0.6, y: tiltPhase * 1.2, z: 0),
                perspective: 0.55
            )
            .modifier(CardShadow(isSample: isSample, accent: accent, emphasized: emphasized, tiltPhase: tiltPhase))
            .animation(.snappy(duration: 0.45), value: state)
            .animation(.snappy(duration: 0.45), value: isResolved)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .task {
                guard emphasized, !reduceMotion, !isSample else { return }
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    tiltPhase = 1
                }
            }
    }

    private var accent: Color {
        if !isResolved { return Color.secondary }
        return state.accent
    }

    private var adaptiveParts: CoverageCardMapping.YearMonth? {
        guard remainingStyle == .adaptive else { return nil }
        return CoverageCardMapping.yearMonth(daysRemaining: daysRemaining)
    }

    private var spokenLabel: String {
        Self.accessibilityLabel(
            isResolved: isResolved,
            isSample: isSample,
            spokenLeadIn: spokenLeadIn,
            merchant: merchant,
            item: item,
            phaseLabel: state.label,
            remainingSpoken: CoverageCardMapping.spokenRemaining(
                daysRemaining: daysRemaining,
                yearMonth: adaptiveParts
            ),
            showsReceipt: proof != nil,
            showsClaimPackReady: proof?.showsClaimPackReady == true
        )
    }

    static func accessibilityLabel(
        isResolved: Bool,
        isSample: Bool,
        spokenLeadIn: String?,
        merchant: String,
        item: String,
        phaseLabel: String,
        remainingSpoken: String,
        showsReceipt: Bool,
        showsClaimPackReady: Bool
    ) -> String {
        if !isResolved {
            return String(localized: "Checking cover for \(item)", comment: "VoiceOver while the key-moment card is redacted")
        }
        var parts: [String] = []
        if let spokenLeadIn, !spokenLeadIn.isEmpty {
            parts.append(spokenLeadIn.hasSuffix(".") ? spokenLeadIn : "\(spokenLeadIn).")
        } else if isSample {
            parts.append(String(localized: "Sample.", comment: "VoiceOver prefix for the empty-library sample card"))
        }
        parts.append("\(merchant), \(item).")
        parts.append("\(phaseLabel), \(remainingSpoken).")
        if showsReceipt {
            parts.append(String(localized: "Receipt saved.", comment: "VoiceOver proof row"))
        }
        if showsClaimPackReady {
            parts.append(String(localized: "Claim pack ready.", comment: "VoiceOver proof row"))
        }
        return parts.joined(separator: " ")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                statePill
                    .placeholderRedacted(!isResolved)
                Spacer()
                topTrailing
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

            countdown
                .placeholderRedacted(!isResolved)

            if let proof {
                Divider().opacity(0.4)
                proofRow(proof)
                    .placeholderRedacted(!isResolved)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Color(.secondarySystemBackground))

                if emphasized && !isSample {
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
                .strokeBorder(accent.opacity(isSample ? 0.2 : 0.35), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var topTrailing: some View {
        if isSample {
            Text("Sample")
                .font(KeptFont.sans(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        } else {
            shieldOrnament
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if state == .expired {
            Text("Expired")
                .font(KeptFont.sans(44, weight: .semibold, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if let parts = adaptiveParts {
            adaptiveCountdown(parts)
        } else {
            dayCountdown
        }
    }

    private var dayCountdown: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
            Text("\(daysRemaining)")
                .font(KeptFont.sans(56, weight: .semibold, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentTransition(.numericText(countsDown: false))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(daysRemaining == 1 ? "day left" : "days left", comment: "Coverage countdown subtitle next to the big day number")
                .font(.keptSubheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func adaptiveCountdown(_ parts: CoverageCardMapping.YearMonth) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
            if parts.years > 0 {
                durationGroup(value: parts.years, unit: "yr")
            }
            if parts.months > 0 {
                durationGroup(value: parts.months, unit: "mo")
            }
            Text("left")
                .font(.keptSubheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func durationGroup(value: Int, unit: LocalizedStringKey) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
            Text("\(value)")
                .font(KeptFont.sans(56, weight: .semibold, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.keptSubheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var shieldOrnament: some View {
        if emphasized {
            ZStack {
                CountdownRing(
                    fraction: ringFraction,
                    tint: accent,
                    lineWidth: 2.5
                )
                .frame(width: 38, height: 38)

                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(accent)
                    .font(.keptSubheadline)
            }
        } else {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(accent)
                .font(.keptTitle3)
        }
    }

    /// Maps daysRemaining to a 0–1 fraction against a 14-day baseline. Clamps at extremes.
    private var ringFraction: Double {
        if state == .expired { return 0 }
        return max(0, min(1, Double(daysRemaining) / 14.0))
    }

    private func proofRow(_ proof: Proof) -> some View {
        let labels = VStack(alignment: .leading, spacing: Spacing.sm) {
            proofLabel("Receipt")
            if proof.showsClaimPackReady {
                proofLabel("Claim pack ready")
            }
        }
        let thumbnail = ReceiptThumbnail(data: proof.receiptImage, cornerRadius: 5)
            .frame(width: 36, height: 44)
            .accessibilityHidden(true)

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    thumbnail
                    labels
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.sm + Spacing.xs) {
                    thumbnail
                    labels
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func proofLabel(_ title: LocalizedStringKey) -> some View {
        Label {
            Text(title)
                .font(KeptFont.sans(15, weight: .medium, relativeTo: .subheadline))
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent)
        }
    }

    private var statePill: some View {
        Text(state.label)
            .font(KeptFont.sans(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(accent.opacity(0.14), in: Capsule())
    }
}

private extension View {
    @ViewBuilder
    func placeholderRedacted(_ isActive: Bool) -> some View {
        if isActive {
            redacted(reason: .placeholder)
        } else {
            self
        }
    }
}

private struct CardShadow: ViewModifier {
    var isSample: Bool
    var accent: Color
    var emphasized: Bool
    var tiltPhase: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSample {
            content
        } else {
            content.shadow(
                color: accent.opacity(emphasized ? 0.26 : 0.18),
                radius: emphasized ? 30 : 22,
                x: emphasized ? tiltPhase * 10 : 0,
                y: emphasized ? 16 + tiltPhase * 5 : 12
            )
        }
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

#Preview("Unresolved") {
    CoverageCard(
        state: .covered,
        merchant: "Sony",
        item: "WH-1000XM5 Headphones",
        daysRemaining: 214,
        isResolved: false,
        proof: .init(receiptImage: nil, showsClaimPackReady: true)
    )
    .padding()
}

#Preview("Covered with proof") {
    CoverageCard(
        state: .covered,
        merchant: "Sony",
        item: "WH-1000XM5 Headphones",
        daysRemaining: 214,
        proof: .init(receiptImage: nil, showsClaimPackReady: true)
    )
    .padding()
}

#Preview("Adaptive sample") {
    CoverageCard(
        state: .covered,
        merchant: "Dyson",
        item: "V15 Detect",
        daysRemaining: 608,
        remainingStyle: .adaptive,
        proof: .init(receiptImage: nil, showsClaimPackReady: false),
        isSample: true
    )
    .padding()
}

#Preview("Dark") {
    CoverageCard(
        state: .covered,
        merchant: "Sony",
        item: "WH-1000XM5 Headphones",
        daysRemaining: 214,
        proof: .init(receiptImage: nil, showsClaimPackReady: true)
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Accessibility") {
    CoverageCard(
        state: .covered,
        merchant: "Sony",
        item: "WH-1000XM5 Headphones",
        daysRemaining: 214,
        proof: .init(receiptImage: nil, showsClaimPackReady: true)
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Hero — covered") {
    CoverageCard(state: .covered, merchant: "Sony", item: "WH-1000XM5 Headphones", daysRemaining: 14, emphasized: true)
        .padding()
}
