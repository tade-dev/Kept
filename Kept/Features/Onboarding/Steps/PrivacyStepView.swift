import SwiftUI

/// Short privacy step: one accurate line, then Continue (owned by OnboardingView).
struct PrivacyStepView: View {
    var body: some View {
        OnboardingScaffold(
            title: "Your receipts stay yours."
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Copy: OnboardingCopy.privacyLine (DESIGN-PENDING wording; facts are fixed).
                Text(OnboardingCopy.privacyLine)
                    .font(.keptBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    PrivacyStepView()
}
