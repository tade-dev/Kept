import SwiftUI
import QuartzCore

/// Diagonal light sweep over a rounded rect. Renders through a `CAGradientLayer` whose
/// `locations` are animated with a repeating `CABasicAnimation`. Auto-plays, respects
/// Reduce Motion (renders a static faint gradient instead).
struct SpecularShimmer: UIViewRepresentable {
    var cornerRadius: CGFloat = 28
    var duration: CFTimeInterval = 2.4
    var reduceMotion: Bool = false

    func makeUIView(context: Context) -> ShimmerView {
        ShimmerView(cornerRadius: cornerRadius, duration: duration, reduceMotion: reduceMotion)
    }

    func updateUIView(_ view: ShimmerView, context: Context) {
        view.apply(cornerRadius: cornerRadius, duration: duration, reduceMotion: reduceMotion)
    }

    final class ShimmerView: UIView {
        private let gradient = CAGradientLayer()
        private var duration: CFTimeInterval
        private var reduceMotion: Bool
        private var isAnimating = false

        init(cornerRadius: CGFloat, duration: CFTimeInterval, reduceMotion: Bool) {
            self.duration = duration
            self.reduceMotion = reduceMotion
            super.init(frame: .zero)

            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.masksToBounds = true
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous

            let clear = UIColor.white.withAlphaComponent(0).cgColor
            let bright = UIColor.white.withAlphaComponent(0.32).cgColor
            gradient.colors = [clear, bright, clear]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            gradient.locations = [0.0, 0.5, 1.0]
            layer.addSublayer(gradient)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func apply(cornerRadius: CGFloat, duration: CFTimeInterval, reduceMotion: Bool) {
            layer.cornerRadius = cornerRadius
            let previousReduce = self.reduceMotion
            self.duration = duration
            self.reduceMotion = reduceMotion
            if previousReduce != reduceMotion {
                gradient.removeAnimation(forKey: "sweep")
                isAnimating = false
                startIfNeeded()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = bounds
            startIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { startIfNeeded() } else { stop() }
        }

        private func startIfNeeded() {
            guard !isAnimating, bounds.width > 0, window != nil, !reduceMotion else { return }
            isAnimating = true

            let anim = CABasicAnimation(keyPath: "locations")
            anim.fromValue = [-0.5, -0.25, 0.0]
            anim.toValue = [1.0, 1.25, 1.5]
            anim.duration = duration
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(anim, forKey: "sweep")
        }

        private func stop() {
            gradient.removeAnimation(forKey: "sweep")
            isAnimating = false
        }
    }
}
