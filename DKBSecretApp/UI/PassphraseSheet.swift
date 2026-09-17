import DKBSecretCore
import SwiftUI

/// Asks for the backup passphrase. `.create` demands two matching entries
/// and shows a strength estimate; `.enter` is a single field for import.
struct PassphraseSheet: View {
    enum Purpose {
        case create(title: LocalizedStringKey)
        case enter(title: LocalizedStringKey)
    }

    let purpose: Purpose
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var isCreate: Bool {
        if case .create = purpose { return true }
        return false
    }

    /// Twelve lowercase letters pass the length rule at ~56 bits; this is the
    /// floor that actually makes the PBKDF2 work count for something.
    static let minimumBits = 60.0

    private var problem: LocalizedStringKey? {
        if passphrase.count < BackupCrypto.minimumPassphraseLength { return "At least \(BackupCrypto.minimumPassphraseLength) characters." }
        if isCreate, Self.entropyBits(passphrase) < Self.minimumBits { return "Too easy to guess — make it longer or mix in more kinds of characters." }
        if isCreate, passphrase != confirmation { return "The two entries don't match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch purpose {
            case .create(let title), .enter(let title):
                Text(title).font(.title3.bold())
            }
            SecureField("Passphrase", text: $passphrase)
            if isCreate {
                SecureField("Confirm passphrase", text: $confirmation)
                let bits = Self.entropyBits(passphrase)
                HStack {
                    ProgressView(value: min(bits, 100), total: 100)
                        .tint(bits < 40 ? .red : (bits < 70 ? .orange : .green))
                    Text("\(Int(bits)) bits").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Text("There is no way to recover a backup without this passphrase. Write it down somewhere safe that isn't this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let problem, !passphrase.isEmpty {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Continue") { onConfirm(passphrase) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Rough strength: character-class size to the power of the length.
    nonisolated static func entropyBits(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        var classes = 0
        if text.contains(where: \.isLowercase) { classes += 26 }
        if text.contains(where: \.isUppercase) { classes += 26 }
        if text.contains(where: \.isNumber) { classes += 10 }
        if text.contains(where: { !$0.isLetter && !$0.isNumber }) { classes += 33 }
        return Double(text.count) * log2(Double(max(classes, 1)))
    }
}
