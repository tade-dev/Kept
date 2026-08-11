import SwiftUI
import QuartzCore

/// Circular arc rendered by a `CAShapeLayer`. `fraction` drives `strokeEnd` (1 = full, 0 = empty).
/// Starts at 12 o'clock and drains clockwise. Colour follows `tint`.
struct CountdownRing: UIViewRepresentable {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    func makeUIView(context: Context) -> RingView {
        RingView(lineWidth: lineWidth)
    }

    func updateUIView(_ view: RingView, context: Context) {
        view.apply(fraction: fraction, tint: UIColor(tint), lineWidth: lineWidth)
    }

    final class RingView: UIView {
        private let track = CAShapeLayer()
        private let ring = CAShapeLayer()
        private var currentFraction: Double = 1

        init(lineWidth: CGFloat) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear

            // Rotate the layer so the arc starts at 12 o'clock and drains clockwise.
            let rotate = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)

            track.fillColor = UIColor.clear.cgColor
            track.strokeColor = UIColor.tertiaryLabel.withAlphaComponent(0.35).cgColor
            track.lineWidth = lineWidth
            track.strokeEnd = 1
            track.transform = rotate

            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor.label.cgColor
            ring.lineWidth = lineWidth
            ring.lineCap = .round
            ring.strokeEnd = 1
            ring.transform = rotate

            layer.addSublayer(track)
            layer.addSublayer(ring)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = ring.lineWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let path = UIBezierPath(ovalIn: rect).cgPath
            track.path = path
            ring.path = path
            [track, ring].forEach { $0.frame = bounds }
        }

        func apply(fraction: Double, tint: UIColor, lineWidth: CGFloat) {
            ring.lineWidth = lineWidth
            track.lineWidth = lineWidth
            ring.strokeColor = tint.cgColor

            let clamped = max(0, min(1, fraction))
            guard abs(clamped - currentFraction) > 0.001 else { return }
            let from = currentFraction
            currentFraction = clamped

            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = from
            anim.toValue = clamped
            anim.duration = 0.4
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(anim, forKey: "drain")
            ring.strokeEnd = clamped
        }
    }
}
