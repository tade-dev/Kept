import SwiftUI

/// A single-tap celebration sheet that pops after Kept's server has granted
/// the user 7 days of Kept Pro because they hit the engagement threshold in
/// the first 24 hours. A confetti burst plays on appear (respecting
/// Reduce Motion), the gift emblem bounces, and copy fades in beneath.
///
/// The parent presents this via `.sheet(isPresented:)` — sheet dismissal
/// (button tap or drag) hands control cleanly back to the library.
struct TrialBoostCelebration: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var confettiSeed: Int = 0

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                emblem
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.72), value: appeared)

                VStack(spacing: 10) {
                    Text("7 days of Kept Pro")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)

                    Text("You've saved a few receipts already — here's a week of Kept Pro on us to see what the upgrade unlocks.")
                        .font(.keptSubheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.snappy(duration: 0.42).delay(0.12), value: appeared)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.keptHeadline)
                        .foregroundStyle(KeptColor.adaptiveOnInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(KeptColor.adaptiveInk))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(appeared ? 1 : 0)
                .animation(.snappy(duration: 0.32).delay(0.22), value: appeared)
            }

            // Confetti sits on top of everything else so pieces can drift
            // across the emblem + copy without being clipped. Hit-testing
            // disabled so tapping "Continue" through them still works.
            if !reduceMotion {
                ConfettiBurst(seed: confettiSeed)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appeared = true
            // Bump seed so a re-presentation kicks off a fresh burst
            // rather than reusing stale particles.
            confettiSeed &+= 1
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 128, height: 128)

            Image(systemName: "gift.fill")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, options: .nonRepeating)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Confetti

/// Native SwiftUI confetti — no packages, no UIKit. Emits `count` particles
/// from the top of the containing space, each with random horizontal drift,
/// gravity, rotation, colour, and shape. The whole system finishes and
/// fades out over `duration` seconds, then holds at rest.
///
/// Reduce Motion callers should just not include this view — animation is
/// the whole point and a static confetti frame would look broken.
private struct ConfettiBurst: View {
    /// Changes to `seed` reseed the particle set. Lets a parent re-fire the
    /// burst on subsequent presentations of the same view instance.
    var seed: Int
    var count: Int = 46
    var duration: Double = 3.2

    @State private var startedAt: Date = .now
    @State private var particles: [Particle] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                Canvas { ctx, size in
                    // Pre-resolve one symbol per palette colour + kind so the
                    // hot loop only translates/rotates instead of re-hosting a
                    // View per particle per frame.
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    let progress = min(elapsed / duration, 1)
                    let overshoot = max(0, elapsed - duration)

                    for (index, particle) in particles.enumerated() {
                        let t = elapsed
                        let x = particle.originX * size.width
                            + particle.velocityX * t
                        let y = -particle.spawnOffsetY
                            + particle.velocityY * t
                            + 0.5 * particle.gravity * t * t

                        let fadeStart = 0.7
                        let alpha: Double
                        if overshoot > 0 {
                            alpha = max(0, 1 - overshoot / 0.6)
                        } else if progress > fadeStart {
                            alpha = 1 - (progress - fadeStart) / (1 - fadeStart)
                        } else {
                            alpha = 1
                        }
                        if alpha <= 0.01 { continue }

                        // Symbols were registered as ForEach children on the
                        // Canvas below with tag `particle.<index>` so the
                        // Canvas can resolve them by tag in the draw loop.
                        guard let symbol = ctx.resolveSymbol(id: index) else { continue }
                        var frame = ctx
                        frame.translateBy(x: x, y: y + size.height * 0.02)
                        frame.rotate(by: .degrees(particle.rotationRate * t * 360))
                        frame.opacity = alpha
                        frame.draw(symbol, at: .zero, anchor: .center)
                    }
                } symbols: {
                    // One View per particle, tagged by its index. The Canvas
                    // rasterises them once and re-uses them each frame — much
                    // cheaper than resolving a fresh View per particle per
                    // tick.
                    ForEach(particles.indices, id: \.self) { index in
                        particles[index].view.tag(index)
                    }
                }
                .onAppear { spawn(width: geo.size.width) }
                .onChange(of: seed) {
                    startedAt = .now
                    spawn(width: geo.size.width)
                }
            }
        }
    }

    // MARK: - Spawning

    private func spawn(width: CGFloat) {
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in Particle.random(rng: &rng) }
        startedAt = .now
    }

    // MARK: - Particle model

    struct Particle {
        var originX: Double            // 0…1 of container width
        var spawnOffsetY: Double       // Points above the top edge — starts off-screen
        var velocityX: Double          // pts/s
        var velocityY: Double          // pts/s (downward on iOS = positive y)
        var gravity: Double            // pts/s²
        var rotationRate: Double       // full turns per second
        var size: CGFloat
        var color: Color
        var kind: Kind

        enum Kind: CaseIterable { case rect, circle, sparkle }

        static func random(rng: inout SystemRandomNumberGenerator) -> Particle {
            Particle(
                originX: .random(in: 0.15...0.85, using: &rng),
                spawnOffsetY: .random(in: 20...80, using: &rng),
                velocityX: .random(in: -60...60, using: &rng),
                velocityY: .random(in: 80...220, using: &rng),
                gravity: .random(in: 340...440, using: &rng),
                rotationRate: .random(in: -1.5...1.5, using: &rng),
                size: .random(in: 6...12, using: &rng),
                color: Palette.random(using: &rng),
                kind: Kind.allCases.randomElement(using: &rng) ?? .rect
            )
        }

        /// SwiftUI view rendered for this particle. Registered once in the
        /// Canvas `symbols:` block via a tag and re-used every frame — the
        /// Canvas draw loop just translates + rotates the resolved symbol
        /// rather than re-hosting a View per tick.
        @ViewBuilder
        var view: some View {
            switch kind {
            case .rect:
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: size * 1.4, height: size * 0.55)
            case .circle:
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            case .sparkle:
                Image(systemName: "sparkle")
                    .font(.system(size: size + 4, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }

    private enum Palette {
        static let colors: [Color] = [
            Color(red: 0.96, green: 0.62, blue: 0.04),  // amber (endingSoon)
            Color(red: 0.30, green: 0.60, blue: 1.0),   // sky
            Color(red: 0.68, green: 0.46, blue: 1.0),   // violet
            Color(red: 0.10, green: 0.72, blue: 0.55),  // mint
            Color(red: 0.95, green: 0.35, blue: 0.55),  // rose
        ]
        static func random(using rng: inout SystemRandomNumberGenerator) -> Color {
            colors.randomElement(using: &rng) ?? .accentColor
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TrialBoostCelebration()
        }
}
