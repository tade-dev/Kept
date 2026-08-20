import SwiftUI

/// Optional pre-render step. Lets the user write a short message that
/// appears at the top of the claim pack PDF — the "why I'm writing"
/// paragraph most claims need anyway (dead fridge, laptop won't boot,
/// item never arrived). Skipping is free: empty notes are dropped by
/// the document layout.
struct ClaimPackComposeSheet: View {
    let purchase: Purchase
    /// Fired with whatever the user typed (may be whitespace-only — the
    /// document trims before deciding whether to render the block).
    var onContinue: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var placeholder: String {
        let merchant = purchase.merchant.trimmingCharacters(in: .whitespaces)
        let item = purchase.itemName.trimmingCharacters(in: .whitespaces)
        if !item.isEmpty {
            return "Hi \(merchant.isEmpty ? "team" : merchant), the \(item) I bought from you has stopped working. Please can you help me arrange a repair under warranty? Thanks."
        }
        return "Write a short note explaining what happened and what you'd like the seller to do."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.keptBody)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.keptBody)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .focused($isFocused)
                }

                Divider()

                HStack {
                    Text("\(text.count) characters")
                        .font(.keptCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Optional")
                        .font(.keptCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Message to the seller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(KeptFont.sans(15, weight: .semibold, relativeTo: .body))
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onContinue(text)
                    } label: {
                        Text("Continue")
                            .font(KeptFont.sans(16, weight: .semibold, relativeTo: .body))
                    }
                }
            }
            .task {
                // Small delay so the sheet finishes presenting before the
                // keyboard slides up — jumping both at once looks janky.
                try? await Task.sleep(for: .milliseconds(250))
                isFocused = true
            }
        }
    }
}
