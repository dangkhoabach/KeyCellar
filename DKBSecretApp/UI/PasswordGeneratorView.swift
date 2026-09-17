import DKBSecretCore
import SwiftUI

/// Popover attached to a password/key field. "Use" writes the generated
/// value into the field.
struct PasswordGeneratorView: View {
    let onUse: (String) -> Void
    @State private var options = PasswordGenerator.Options()
    @State private var generated = PasswordGenerator.generate()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(generated)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { regenerate() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Regenerate")
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            let bits = PasswordGenerator.entropyBits(options)
            HStack {
                ProgressView(value: min(bits, 128), total: 128)
                    .tint(bits < 50 ? .red : (bits < 80 ? .orange : .green))
                Text("\(Int(bits)) bits").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            HStack {
                Text("Length: \(options.length)").monospacedDigit().frame(width: 90, alignment: .leading)
                Slider(value: Binding(get: { Double(options.length) }, set: { options.length = Int($0) }),
                       in: Double(PasswordGenerator.lengthRange.lowerBound)...Double(PasswordGenerator.lengthRange.upperBound), step: 1)
            }
            Grid(alignment: .leading, verticalSpacing: 4) {
                GridRow {
                    Toggle("Lowercase (a-z)", isOn: $options.lowercase)
                    Toggle("Uppercase (A-Z)", isOn: $options.uppercase)
                }
                GridRow {
                    Toggle("Digits (0-9)", isOn: $options.digits)
                    Toggle("Symbols (!@#…)", isOn: $options.symbols)
                }
            }
            Toggle("Exclude ambiguous (0 O 1 l I |)", isOn: $options.excludeAmbiguous)

            HStack {
                Spacer()
                Button("Use Password") { onUse(generated) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(generated.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onChange(of: options) { _, _ in regenerate() }
    }

    private func regenerate() {
        generated = PasswordGenerator.generate(options)
    }
}
