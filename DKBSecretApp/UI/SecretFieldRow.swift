import DKBSecretCore
import SwiftUI

/// A masked value with reveal and copy buttons. Revealed text is monospaced
/// inside a yellow border with a countdown, then hides itself (plan §7.3).
struct SecretFieldRow: View {
    /// A `Text` so template labels are localized while `.env` KEY names stay verbatim.
    let label: Text
    let field: String
    var slot = 0
    var multiline = false
    let model: ItemDetailViewModel
    let onCopy: () -> Void
    let onError: (any Error) -> Void

    var body: some View {
        LabeledContent {
            HStack(alignment: .top, spacing: 6) {
                Group {
                    if let value = model.revealedValue(field, slot: slot) {
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(multiline ? nil : 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.yellow.opacity(0.8)))
                    } else {
                        Text(verbatim: "••••••••••••")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let left = model.revealCountdown[.init(field: field, slot: slot)] {
                    Text("\(left)s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        do { try await model.toggleReveal(field, slot: slot) } catch { onError(error) }
                    }
                } label: {
                    Image(systemName: model.isRevealed(field, slot: slot) ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(model.isRevealed(field, slot: slot) ? "Hide" : "Reveal (Touch ID)")
                .accessibilityLabel(model.isRevealed(field, slot: slot) ? "Hide \(label)" : "Reveal \(label)")
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy (Touch ID)")
                .accessibilityLabel("Copy \(label)")
            }
        } label: {
            label
        }
    }
}
