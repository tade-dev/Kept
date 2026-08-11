import SwiftUI
import AVKit

/// Silent, looping demo video. Renders a first-class placeholder when the bundle
/// resource is missing so the flow stays intact before the video ships.
struct DemoVideoView: View {
    let resourceName: String
    let resourceExtension: String
    let cornerRadius: CGFloat

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var resourceMissing = false

    init(
        resourceName: String,
        resourceExtension: String = "mp4",
        cornerRadius: CGFloat = Radius.xl
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let player, !resourceMissing {
                VideoPlayer(player: player)
                    .disabled(true)
                    .allowsHitTesting(false)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task { load() }
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

    private func load() {
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
    }
}

#Preview("Missing resource → placeholder") {
    DemoVideoView(resourceName: "does-not-exist")
        .aspectRatio(9/16, contentMode: .fit)
        .padding()
}
