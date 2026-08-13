import SwiftUI
import AVKit

/// Silent, looping demo video. Waits for the player to be genuinely ready
/// before revealing the video, so the user never sees AVPlayer's black
/// pre-playback frame. Renders a first-class placeholder when the bundle
/// resource is missing.
struct DemoVideoView: View {
    let resourceName: String
    let resourceExtension: String
    let cornerRadius: CGFloat
    /// Fires once when the player's first frame is ready to display.
    /// The parent can use this to coordinate its entrance animation.
    var onReady: (() -> Void)?

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var resourceMissing = false
    @State private var readyToShow = false

    init(
        resourceName: String,
        resourceExtension: String = "mp4",
        cornerRadius: CGFloat = Radius.xl,
        onReady: (() -> Void)? = nil
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.cornerRadius = cornerRadius
        self.onReady = onReady
    }

    var body: some View {
        ZStack {
            // Neutral hold color — sits behind the video during the load
            // window so the user never sees AVPlayer's raw black frame.
            Color.white
                .opacity(readyToShow ? 0 : 1)

            if let player, !resourceMissing {
                VideoPlayer(player: player)
                    .disabled(true)
                    .allowsHitTesting(false)
                    .opacity(readyToShow ? 1 : 0)
                    .blur(radius: readyToShow ? 0 : 12)
                    .scaleEffect(readyToShow ? 1.0 : 0.96)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if resourceMissing {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task { await load() }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        ZStack {
            KeptColor.covered.opacity(0.12)
            VStack(spacing: Spacing.sm) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(KeptColor.covered.opacity(0.55))
                Text("Demo")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            resourceMissing = true
            return
        }

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        resourceMissing = false

        // Fixed short delay is more reliable than KVO status observation for
        // bundled files — AVPlayer decodes the first frame within ~100-150ms
        // on modern devices. The white hold above keeps this window invisible.
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.easeOut(duration: 0.45)) {
            readyToShow = true
        }
        onReady?()
    }
}

#Preview("Missing resource → placeholder") {
    DemoVideoView(resourceName: "does-not-exist")
        .aspectRatio(9/16, contentMode: .fit)
        .padding()
}
