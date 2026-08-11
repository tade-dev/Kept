import SwiftUI

/// Step 7 — brief "we're setting things up" beat. Counting % + gradient bar + checklist.
struct SettingUpStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: () -> Void

    @State private var percentage: Int = 0
    @State private var completedCount: Int = 0

    private let steps: [String] = [
        "Warming up the coverage engine",
        "Loading your categories",
        "Scheduling reminders",
        "Ready to scan",
    ]

    private var currentSubtitle: String {
        let index = min(completedCount, steps.count - 1)
        return "\(steps[index])…"
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text("\(percentage)%")
                    .font(.system(size: 72, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("We're setting everything up for you.")
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.lg)
            }

            progressBar
                .padding(.horizontal, Spacing.lg)

            Text(currentSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            Spacer()

            checklist
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
        }
        .task { await run() }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [KeptColor.endingSoon, KeptColor.ink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * Double(percentage) / 100))
                    .animation(.snappy(duration: 0.15), value: percentage)
            }
        }
        .frame(height: 8)
    }

    // MARK: - Checklist card

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What we're doing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: Spacing.sm) {
                ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                    checklistRow(
                        title: pair.element,
                        done: pair.offset < completedCount
                    )
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func checklistRow(title: String, done: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(done ? KeptColor.ink : Color.secondary.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(done ? .primary : .secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Run

    private func run() async {
        let totalDuration: Double = reduceMotion ? 0.8 : 1.9
        let ticks = 100
        let perTickNs = UInt64(totalDuration * 1_000_000_000 / Double(ticks))

        for value in 1...100 {
            percentage = value
            let index = min(steps.count, Int(Double(value) / 100.0 * Double(steps.count)) + 1)
            if index > completedCount {
                withAnimation(.snappy(duration: 0.2)) {
                    completedCount = index
                }
            }
            try? await Task.sleep(nanoseconds: perTickNs)
        }

        withAnimation(.snappy(duration: 0.2)) {
            completedCount = steps.count
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        onComplete()
    }
}

#Preview {
    SettingUpStepView(onComplete: {})
}
