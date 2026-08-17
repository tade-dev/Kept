import SwiftUI

/// Interactive rejection surface — when the classifier decides the scanned
/// document isn't a receipt. Rubber-stamp reveal + warm copy + rescan/override.
///
/// Motion:
///   1. Scanned image scales up + fades in
///   2. ~400ms later a red rubber-stamp swings down from the top-right at an
///      angle, springs to rest with a haptic thump
///   3. Copy + CTAs fade in underneath
struct RejectedDocumentSheet: View {
    let image: UIImage?
    let documentType: DocumentType
    /// Fires when the user taps the toolbar close (X). Parent should cancel
    /// the whole capture flow — not just this sheet.
    var onClose: () -> Void
    /// Fires when the user wants to try scanning again — parent should reset
    /// capture state and present the camera.
    var onRetry: () -> Void
    /// Fires when the user overrides — insists the classifier was wrong and
    /// wants to save anyway. Parent proceeds to the confirm screen with the
    /// original extraction.
    var onOverride: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var imageShown = false
    @State private var stampLanded = false
    @State private var copyShown = false
    @State private var stampTick = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 8)

                    imageWithStamp
                        .frame(maxWidth: .infinity)

                    copyBlock
                        .opacity(copyShown ? 1 : 0)
                        .offset(y: copyShown ? 0 : 8)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 120)  // room for CTA bar
                }
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) { ctaBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(KeptFont.sans(17, weight: .semibold, relativeTo: .body))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampTick)
        .task { await runReveal() }
    }

    // MARK: - Layered image + stamp

    private var imageWithStamp: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .scaleEffect(imageShown ? 1 : 0.92)
                    .opacity(imageShown ? 1 : 0)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 220, height: 300)
                    .opacity(imageShown ? 1 : 0)
            }

            stamp
                .rotationEffect(.degrees(stampLanded ? -8 : 40))
                .scaleEffect(stampLanded ? 1.0 : 1.6)
                .opacity(stampLanded ? 1 : 0)
                .offset(
                    x: stampLanded ? 20 : 140,
                    y: stampLanded ? -30 : -160
                )
        }
        .frame(height: 340)
    }

    private var stamp: some View {
        VStack(spacing: 2) {
            Text(documentType.stampLabel)
                .font(KeptFont.sans(20, weight: .bold, relativeTo: .title))
                .kerning(2)
            Text("NOT A RECEIPT")
                .font(KeptFont.sans(11, weight: .bold, relativeTo: .caption2))
                .kerning(1.5)
        }
        .foregroundStyle(stampInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(stampInk, lineWidth: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(stampInk.opacity(0.4), lineWidth: 1)
                .padding(4)
        )
    }

    private var stampInk: Color {
        Color(red: 0.75, green: 0.15, blue: 0.20)  // rubber-stamp red
    }

    // MARK: - Copy

    private var copyBlock: some View {
        VStack(spacing: 6) {
            Text(documentType.friendlyExplanation)
                .font(KeptFont.sans(22, weight: .semibold, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Snap a receipt or invoice to have Kept remember the warranty for you.")
                .font(.keptSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - CTAs

    private var ctaBar: some View {
        VStack(spacing: 10) {
            Button {
                onRetry()
            } label: {
                Text("Try again")
                    .font(.keptHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(KeptColor.ink))
            }
            .buttonStyle(.plain)
            .opacity(copyShown ? 1 : 0)

            Button {
                onOverride()
            } label: {
                Text("This IS a receipt")
                    .font(.keptFootnote)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .opacity(copyShown ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Reveal choreography

    private func runReveal() async {
        if reduceMotion {
            imageShown = true
            stampLanded = true
            copyShown = true
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            imageShown = true
        }
        try? await Task.sleep(nanoseconds: 400_000_000)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            stampLanded = true
        }
        stampTick &+= 1   // haptic thump when the stamp lands

        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(.easeOut(duration: 0.32)) {
            copyShown = true
        }
    }
}

#Preview("Passport") {
    RejectedDocumentSheet(
        image: nil,
        documentType: .passport,
        onClose: {},
        onRetry: {},
        onOverride: {}
    )
}

#Preview("Menu") {
    RejectedDocumentSheet(
        image: nil,
        documentType: .menu,
        onClose: {},
        onRetry: {},
        onOverride: {}
    )
}

#Preview("Business card") {
    RejectedDocumentSheet(
        image: nil,
        documentType: .businessCard,
        onClose: {},
        onRetry: {},
        onOverride: {}
    )
}
