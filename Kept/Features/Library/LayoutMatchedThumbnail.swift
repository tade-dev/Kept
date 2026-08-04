import SwiftUI

/// Morphs receipt thumbnails between library orientations via `matchedGeometryEffect`.
/// Skipped when Reduce Motion is on.
struct LayoutMatchedThumbnail: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

extension View {
    func layoutMatchedThumbnail(id: String, in namespace: Namespace.ID) -> some View {
        modifier(LayoutMatchedThumbnail(id: id, namespace: namespace))
    }
}
