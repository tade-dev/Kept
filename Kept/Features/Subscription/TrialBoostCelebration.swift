import SwiftUI

/// A single-tap celebration sheet that pops after Kept's server has granted
/// the user 7 days of Kept Pro for hitting the engagement threshold in the
/// first 24 hours.
///
/// Composition: the gift emblem is the visual origin — pulsing halo rings
/// radiate outward, confetti explodes from the emblem's centre (real party-
/// popper physics: radial burst first, then gravity kicks in), and the
/// headline sits directly beneath. Continue button hugs the bottom safe
/// area. The whole thing respects Reduce Motion — pulses go still,
/// confetti disappears, gift bounces once.
struct TrialBoostCelebration: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var confettiSeed: Int = 0
    /// Emblem centre in the sheet's coordinate space — measured from
    /// `GeometryReader` so the confetti burst originates exactly on the
    /// gift, not on some hard-coded x/y guess.
    @State private var emblemCentre: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    emblem
                        .background(emblemAnchor)
                        .scaleEffect(appeared ? 1 : 0.55)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.68), value: appeared)

                    Spacer().frame(height: 32)

                    Text("7 days of Kept Pro")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.snappy(duration: 0.42).delay(0.15), value: appeared)

                    Text("You've saved a few receipts already — here's a week of Kept Pro on us to see what the upgrade unlocks.")
                        .font(.keptSubheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.snappy(duration: 0.42).delay(0.22), value: appeared)

                    Spacer(minLength: 24)

                    Button {
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.keptHeadline)
                            .foregroundStyle(KeptColor.adaptiveOnInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Capsule().fill(KeptColor.adaptiveInk))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(.snappy(duration: 0.32).delay(0.32), value: appeared)
                }

                // Confetti overlay — bursts radially from the emblem centre.
                // Sits on top so pieces drift across copy without being
                // clipped; hit-testing disabled so the CTA stays tappable
                // through the falling particles.
                if !reduceMotion, emblemCentre != .zero {
                    ConfettiBurst(
                        seed: confettiSeed,
                        origin: emblemCentre,
                        containerSize: geo.size
                    )
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "celebration")
            .onAppear {
                appeared = true
                // Fresh seed so re-presentation triggers a new burst rather
                // than reusing stale particles.
                confettiSeed &+= 1
            }
            .onPreferenceChange(EmblemCentrePreference.self) { emblemCentre = $0 }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Emblem

    private var emblem: some View {
        ZStack {
            // Halo rings — three concentric soft rings pulse outward,
            // making the emblem read as the source of the celebration.
            if !reduceMotion {
                ForEach(0..<3) { index in
                    PulsingHalo(delay: Double(index) * 0.4)
                }
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.28),
                            Color.accentColor.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 148, height: 148)

            Image(systemName: "gift.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, options: .nonRepeating)
        }
        .accessibilityHidden(true)
    }

    /// Invisible sibling that reports the emblem's centre in the parent's
    /// coordinate space via a preference key. Lets the confetti burst
    /// originate exactly on the gift without hard-coding coordinates.
    private var emblemAnchor: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: EmblemCentrePreference.self,
                value: CGPoint(x: proxy.frame(in: .named("celebration")).midX,
                               y: proxy.frame(in: .named("celebration")).midY)
            )
        }
    }
}

// MARK: - Emblem centre preference

private struct EmblemCentrePreference: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

// MARK: - Pulsing halo

/// Single ring that scales up and fades to zero on a loop. Composed three
/// times with staggered delay to give a "sonar" pulse.
private struct PulsingHalo: View {
    var delay: Double
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(0.32), lineWidth: 1.5)
            .frame(width: 148, height: 148)
            .scaleEffect(pulsing ? 1.55 : 0.9)
            .opacity(pulsing ? 0 : 0.9)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.8)
                        .repeatForever(autoreverses: false)
                        .delay(delay)
                ) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Confetti

/// Native SwiftUI radial confetti. Bursts outward from `origin` for the
/// first ~500ms, then gravity pulls the pieces down. All particles fade
/// out over the last ~30% of the animation so a settled Canvas isn't
/// stuck redrawing sprites forever.
///
/// Reduce Motion callers should just not include this view.
private struct ConfettiBurst: View {
    var seed: Int
    var origin: CGPoint
    var containerSize: CGSize
    var count: Int = 60
    var duration: Double = 3.4

    @State private var startedAt: Date = .now
    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            Canvas { ctx, _ in
                let t = context.date.timeIntervalSince(startedAt)
                let progress = min(t / duration, 1)
                let overshoot = max(0, t - duration)

                for (index, particle) in particles.enumerated() {
                    // Radial burst → gravity. Initial radial velocity is
                    // decayed exponentially so the "explosion" phase is
                    // punchy up front then settles into a parabolic fall.
                    let radialDecay = exp(-t * 2.2)
                    let vx = particle.radialVX * radialDecay + particle.driftX
                    let vy = particle.radialVY * radialDecay + particle.driftY
                    let x = origin.x + vx * t
                    let y = origin.y + vy * t + 0.5 * particle.gravity * t * t

                    // Cull anything that's drifted way off-screen.
                    if x < -60 || x > containerSize.width + 60 { continue }
                    if y > containerSize.height + 60 { continue }

                    let fadeStart = 0.72
                    let alpha: Double
                    if overshoot > 0 {
                        alpha = max(0, 1 - overshoot / 0.5)
                    } else if progress > fadeStart {
                        alpha = 1 - (progress - fadeStart) / (1 - fadeStart)
                    } else {
                        alpha = 1
                    }
                    if alpha <= 0.02 { continue }

                    guard let symbol = ctx.resolveSymbol(id: index) else { continue }
                    var frame = ctx
                    frame.translateBy(x: x, y: y)
                    frame.rotate(by: .degrees(particle.rotationRate * t * 360))
                    frame.opacity = alpha
                    frame.draw(symbol, at: .zero, anchor: .center)
                }
            } symbols: {
                ForEach(particles.indices, id: \.self) { i in
                    particles[i].view.tag(i)
                }
            }
            .onAppear { spawn() }
            .onChange(of: seed) {
                startedAt = .now
                spawn()
            }
        }
    }

    private func spawn() {
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in Particle.random(rng: &rng) }
        startedAt = .now
    }

    struct Particle {
        /// Radial launch velocity components (fast at t=0, decay quickly).
        var radialVX: Double
        var radialVY: Double
        /// Constant gentle drift that keeps working after the radial burst
        /// has faded — spreads late particles horizontally.
        var driftX: Double
        var driftY: Double
        var gravity: Double
        var rotationRate: Double
        var size: CGFloat
        var color: Color
        var kind: Kind

        enum Kind: CaseIterable { case rect, circle, sparkle }

        static func random(rng: inout SystemRandomNumberGenerator) -> Particle {
            // Bias upward — most party poppers throw more up + out than
            // down, so weight the launch cone toward the top hemisphere.
            let angle = Double.random(in: -.pi ... 0, using: &rng)
            let speed = Double.random(in: 260 ... 460, using: &rng)
            return Particle(
                radialVX: cos(angle) * speed,
                radialVY: sin(angle) * speed,
                driftX: .random(in: -30 ... 30, using: &rng),
                driftY: .random(in: 20 ... 60, using: &rng),
                gravity: .random(in: 380 ... 520, using: &rng),
                rotationRate: .random(in: -1.8 ... 1.8, using: &rng),
                size: .random(in: 6 ... 12, using: &rng),
                color: Palette.random(using: &rng),
                kind: Kind.allCases.randomElement(using: &rng) ?? .rect
            )
        }

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
                .coordinateSpace(name: "celebration")
        }
}
