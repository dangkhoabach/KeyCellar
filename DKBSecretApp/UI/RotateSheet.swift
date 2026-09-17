import DKBSecretCore
import SwiftUI

/// Enter the new value for a secret field; the old one becomes history and
/// the item's expiry is reset from its kind's default lifetime.
struct RotateSheet: View {
    let item: SecretItem
    let field: FieldSpec
    let ttlDays: Int
    let onRotate: (String) -> Void
    let onCancel: () -> Void
    @State private var value = ""
    @State private var showGenerator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rotate \(Text(LocalizedStringKey(field.label)))").font(.title3.bold())
            Text(item.title).foregroundStyle(.secondary)
            HStack {
                if field.isMultiline {
                    TextEditor(text: $value)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                } else {
                    SecureField("New \(Text(LocalizedStringKey(field.label)))", text: $value)
                    Button { showGenerator = true } label: { Image(systemName: "dice") }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showGenerator) {
                            PasswordGeneratorView { value = $0; showGenerator = false }
                        }
                }
            }
            Text(ttlDays > 0
                 ? "The current value is kept in History. Expiry will be set to \(ttlDays) days from now."
                 : "The current value is kept in History. This kind has no default expiry.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rotate") { onRotate(value) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
