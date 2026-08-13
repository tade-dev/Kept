import SwiftUI

/// Traveling-wave distortion that sweeps top→bottom across the view every ~2s
/// while `isActive` is true. Amplitude fades in/out on isActive changes.
struct ProcessingShimmerModifier: ViewModifier {
    var isActive: Bool
    /// Peak displacement at the crest, in points. The wave has gaussian falloff
    /// above / below the crest, so most of the image is undistorted at any moment.
    var maxAmplitude: Float = 8.0

    @State private var currentAmplitude: Float = 0
    @State private var viewHeight: CGFloat = 0

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let time = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
            let sampleOffset = CGFloat(maxAmplitude)
            content
                // Rasterize first — distortionEffect silently no-ops downstream
                // of matchedGeometryEffect without a drawing group.
                .drawingGroup()
                .distortionEffect(
                    ShaderLibrary.processingShimmer(
                        .float(time),
                        .float(currentAmplitude),
                        .float(Float(max(viewHeight, 1)))
                    ),
                    maxSampleOffset: CGSize(width: sampleOffset, height: sampleOffset)
                )
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { viewHeight = $0 })
        .onAppear {
            currentAmplitude = isActive ? maxAmplitude : 0
        }
        .onChange(of: isActive) { _, active in
            withAnimation(.easeInOut(duration: 0.35)) {
                currentAmplitude = active ? maxAmplitude : 0
            }
        }
    }
}

extension View {
    /// Traveling-wave shimmer while OCR + LLM extraction run.
    func processingShimmer(isActive: Bool) -> some View {
        modifier(ProcessingShimmerModifier(isActive: isActive))
    }
}
