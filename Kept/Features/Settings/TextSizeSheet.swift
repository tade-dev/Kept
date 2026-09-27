import SwiftUI

/// Full-height sheet for picking Kept's text size. Big live preview at
/// the top, custom drag slider below with A-to-A end markers. When the
/// "Follow iOS" toggle is on the slider is disabled and the preview
/// shows the current system size.
struct TextSizeSheet: View {
    @Binding var textSize: KeptTextSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    /// Only the manually-selectable sizes. `.system` isn't a slider
    /// position — it's a separate toggle.
    private static let steps: [KeptTextSize] = [.small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]

    private var isFollowingSystem: Bool {
        textSize == .system
    }

    private var currentStepIndex: Int {
        Self.steps.firstIndex(of: textSize) ?? Self.steps.firstIndex(of: .large) ?? 2
    }

    private var previewTypeSize: DynamicTypeSize {
        textSize.override ?? systemTypeSize
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewCard

                Spacer(minLength: 12)

                slider
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                followSystemToggle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Text size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(spacing: 12) {
            // Uses the same hero product as the onboarding key-moment and
            // empty-library sample so users see one consistent demo across
            // the app (see `KeyMomentScript`).
            Text("Samsung 55″ QLED TV")
                .font(.keptTitle3)
                .foregroundStyle(.primary)
                .lineLimit(1...2)
                .multilineTextAlignment(.center)

            Text("Warranty ends in 172 days")
                .font(.keptBody)
                .foregroundStyle(.secondary)
                .lineLimit(1...2)
                .multilineTextAlignment(.center)

            Text("Cover ends · 8 Feb 2027")
                .font(.keptFootnote)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .dynamicTypeSize(previewTypeSize)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: previewTypeSize)
    }

    // MARK: - Slider

    private var slider: some View {
        HStack(spacing: 14) {
            Text("A")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextSizeDragSlider(
                stepCount: Self.steps.count,
                currentStep: currentStepIndex,
                onChange: { newIndex in
                    let clamped = max(0, min(Self.steps.count - 1, newIndex))
                    textSize = Self.steps[clamped]
                }
            )
            .disabled(isFollowingSystem)
            .opacity(isFollowingSystem ? 0.4 : 1.0)

            Text("A")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Follow-system toggle

    private var followSystemToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow iOS text size")
                    .font(.body)
                Text("Uses whatever you've set in iOS Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isFollowingSystem },
                set: { newValue in
                    if newValue {
                        textSize = .system
                    } else {
                        // Bump to Large as a sensible starting point.
                        textSize = .large
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Custom drag slider

/// Discrete-step slider that snaps a draggable thumb to tick marks.
/// Track shows the tick positions; the thumb responds to drag with a
/// spring and fires haptic feedback on each step change.
private struct TextSizeDragSlider: View {
    let stepCount: Int
    let currentStep: Int
    let onChange: (Int) -> Void

    private let trackHeight: CGFloat = 3
    private let thumbSize: CGFloat = 26
    private let tickHeight: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let stepWidth = (width - thumbSize) / CGFloat(stepCount - 1)
            let thumbX = stepWidth * CGFloat(currentStep) + thumbSize / 2

            ZStack {
                // Track background
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: trackHeight)

                // Tick marks
                HStack(spacing: 0) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentStep ? Color.primary : Color(.tertiarySystemFill))
                            .frame(width: 2, height: tickHeight)
                        if index < stepCount - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, thumbSize / 2)

                // Filled portion of the track (thumb-side)
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(0, thumbX - thumbSize / 2 + 2), height: trackHeight)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, thumbSize / 2)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
                    .position(x: thumbX, y: proxy.size.height / 2)
                    .gesture(dragGesture(stepWidth: stepWidth, width: width))
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: currentStep)
            }
            .frame(width: width, height: max(thumbSize, tickHeight))
            .contentShape(Rectangle())
            .gesture(dragGesture(stepWidth: stepWidth, width: width))
            .sensoryFeedback(.selection, trigger: currentStep)
        }
        .frame(height: max(thumbSize, tickHeight))
    }

    private func dragGesture(stepWidth: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let usable = width - thumbSize
                let clampedX = max(0, min(usable, value.location.x - thumbSize / 2))
                let step = Int((clampedX / stepWidth).rounded())
                if step != currentStep {
                    onChange(step)
                }
            }
    }
}
