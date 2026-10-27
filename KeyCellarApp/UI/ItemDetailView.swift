import KeyCellarCore
import SwiftUI

struct ItemDetailView: View {
    let model: ItemDetailViewModel
    let actions: ItemActions
    let inTrash: Bool
    @State private var confirmEnvExport = false

    var body: some View {
        if let item = model.item {
            Form {
                header(item)
                metadataSection(item)
                if item.kind == .recoveryCodes {
                    RecoveryCodesSection(item: item, model: model, actions: actions, inTrash: inTrash)
                }
                // A set of codes without notes has nothing else to show here.
                if item.kind != .recoveryCodes || model.secretFields.contains("notes") {
                    secretsSection(item)
                }
                if model.historyCounts.values.contains(where: { $0 > 0 }) {
                    historySection(item)
                }
                Section {
                    LabeledContent("Created") { Text(item.createdAt, format: .dateTime) }
                    LabeledContent("Updated") { Text(item.updatedAt, format: .dateTime) }
                    if let used = item.lastUsedAt {
                        LabeledContent("Last Used") { Text(used, format: .relative(presentation: .named)) }
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: Binding(get: { actions.rotating != nil }, set: { if !$0 { actions.rotating = nil } })) {
                if let rotating = actions.rotating {
                    RotateSheet(item: rotating.item, field: rotating.field, ttlDays: AppServices.shared.preferences.expiry.ttl(for: rotating.item.kind)) { value in
                        actions.rotate(rotating.item, field: rotating.field.key, newValue: value)
                        actions.rotating = nil
                    } onCancel: { actions.rotating = nil }
                }
            }
            .confirmationDialog("Export as a plain .env file?", isPresented: $confirmEnvExport) {
                Button("Export Unencrypted File") { actions.exportEnvFile(item) }
            } message: {
                Text("The file will contain every value in plain text. Keep it out of version control and delete it when you're done.")
            }
        } else {
            ContentUnavailableView("No Item Selected", systemImage: "key")
        }
    }

    private func header(_ item: SecretItem) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: item.kind.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title2.bold())
                    HStack(spacing: 6) {
                        Text(item.kind.singularTitle)
                        if let env = item.environment {
                            Circle().fill(env.color).frame(width: 8, height: 8)
                            Text(env.title)
                        }
                        if inTrash { Text("· In Trash").foregroundStyle(.red) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                actionButtons(item)
            }
            .padding(.vertical, 4)
        }
    }

    /// In the header rather than `.toolbar`: inside `NavigationSplitView`
    /// the detail column's toolbar items were laid out over the list column.
    private func actionButtons(_ item: SecretItem) -> some View {
        HStack(spacing: 4) {
            if inTrash {
                Button("Restore", systemImage: "arrow.uturn.backward") { actions.restore(item) }
                Button("Delete Permanently", systemImage: "trash.slash") { actions.requestPurge(item) }
            } else {
                Button(item.favorite ? "Unfavorite" : "Favorite", systemImage: item.favorite ? "star.fill" : "star") {
                    actions.toggleFavorite(item)
                }
                .foregroundStyle(item.favorite ? Color.yellow : Color.secondary)
                Button("Edit", systemImage: "pencil") { actions.edit(item) }
                Button("Move to Trash", systemImage: "trash") { actions.trash(item) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    @ViewBuilder
    private func metadataSection(_ item: SecretItem) -> some View {
        let template = item.kind.template
        let rows = template.fields.filter { !$0.isSecret && $0.key != "environment" }
        let hasRows = rows.contains { !(metadataValue(item, $0.key) ?? "").isEmpty } || !model.tags.isEmpty || item.expiresAt != nil
        if hasRows {
            Section {
                ForEach(rows, id: \.key) { spec in
                    if let value = metadataValue(item, spec.key), !value.isEmpty {
                        metadataRow(spec, value)
                    }
                }
                if !model.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(model.tags.map { "#" + $0.name }.joined(separator: "  "))
                    }
                }
                if let expires = item.expiresAt {
                    LabeledContent("Expires") {
                        HStack {
                            Text(expires, format: .dateTime.day().month().year())
                            ExpiryLabel(date: expires)
                            if !inTrash {
                                Button("Mark as Rotated") { actions.markRotated(item) }
                                    .controlSize(.small)
                                    .help("The key was rotated elsewhere: reset the expiry without changing the stored value")
                            }
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(_ spec: FieldSpec, _ value: String) -> some View {
        LabeledContent(LocalizedStringKey(spec.label)) {
            HStack {
                if spec.key == "url", let url = URL(string: value.hasPrefix("http") ? value : "https://\(value)") {
                    Link(value, destination: url).lineLimit(1)
                } else {
                    Text(value)
                        .textSelection(.enabled)
                        .lineLimit(spec.isMultiline ? nil : 1)
                        .font(spec.isMultiline ? .system(.body, design: .monospaced) : .body)
                }
                Spacer()
                Button { actions.copyMetadata(value) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy")
            }
        }
    }

    private func metadataValue(_ item: SecretItem, _ key: String) -> String? {
        switch key {
        case "service": item.service
        case "url": item.url
        case "username": item.username
        default: item.metadata[key]
        }
    }

    @ViewBuilder
    private func secretsSection(_ item: SecretItem) -> some View {
        let template = item.kind.template
        Section(item.kind == .envSet ? "Variables" : "Secrets") {
            ForEach(model.secretFields.filter { $0 != "codes" }, id: \.self) { field in
                let spec = template.fields.first { $0.key == field }
                SecretFieldRow(
                    label: spec.map { Text(LocalizedStringKey($0.label)) } ?? Text(verbatim: String(field.dropFirst(SecretItem.envFieldPrefix.count))),
                    field: field,
                    multiline: spec?.isMultiline ?? false,
                    model: model,
                    onCopy: { actions.copy(item, field: field) },
                    onError: { actions.report($0) }
                )
            }
            if model.secretFields.isEmpty {
                Text("No secret values.").foregroundStyle(.secondary)
            }
            if item.kind == .envSet, !model.secretFields.isEmpty, !inTrash {
                Button("Export as .env…", systemImage: "square.and.arrow.up") { confirmEnvExport = true }
            }
            // A set of codes is replaced, not rotated (`RecoveryCodesSection`).
            if let primary = template.primaryField, model.secretFields.contains(primary.key), !inTrash, item.kind != .recoveryCodes {
                Button("Rotate \(Text(LocalizedStringKey(primary.label)))…", systemImage: "arrow.triangle.2.circlepath") { actions.beginRotate(item, field: primary) }
            }
        }
    }

    private func historySection(_ item: SecretItem) -> some View {
        Section("History") {
            ForEach(model.secretFields.filter { (model.historyCounts[$0] ?? 0) > 0 }, id: \.self) { field in
                let label = item.kind.template.fields.first { $0.key == field }.map { Text(LocalizedStringKey($0.label)) }
                    ?? Text(verbatim: String(field.dropFirst(SecretItem.envFieldPrefix.count)))
                DisclosureGroup("\(label) — \(model.historyCounts[field] ?? 0) previous") {
                    ForEach(1...(model.historyCounts[field] ?? 1), id: \.self) { slot in
                        SecretFieldRow(
                            label: Text("Version -\(slot)"), field: field, slot: slot, model: model,
                            onCopy: { actions.copy(item, field: field, slot: slot) },
                            onError: { actions.report($0) }
                        )
                    }
                }
            }
        }
    }
}

/// The codes of a `recoveryCodes` item, one row each: masked until "Reveal
/// All" (one Touch ID, hidden again after the same countdown as any reveal),
/// a copy button that marks the code used, and a checkbox for the used
/// state, which is metadata and needs no Touch ID.
struct RecoveryCodesSection: View {
    /// At or below this many unused codes the row and this section warn.
    static let lowCount = 2

    let item: SecretItem
    let model: ItemDetailViewModel
    let actions: ItemActions
    let inTrash: Bool
    @State private var confirmExport = false

    var body: some View {
        let codes = model.revealedValue("codes")?.split(separator: "\n").map(String.init)
        let used = item.usedRecoveryCodes
        let remaining = item.remainingRecoveryCodes
        Section {
            ForEach(0..<(codes?.count ?? item.recoveryCodeCount), id: \.self) { offset in
                row(index: offset + 1, code: codes?[offset], usedOn: used[offset + 1])
            }
            if !inTrash {
                if remaining <= Self.lowCount {
                    warning(remaining)
                }
                HStack {
                    Button("Copy Next Unused", systemImage: "doc.on.doc") { actions.copyRecoveryCode(item) }
                        .disabled(remaining == 0)
                    Button("Replace Codes…", systemImage: "arrow.triangle.2.circlepath") { actions.replaceCodes(item) }
                    Button("Export as .txt…", systemImage: "square.and.arrow.up") { confirmExport = true }
                }
            }
        } header: {
            HStack {
                Text("Recovery Codes")
                Spacer()
                Text("\(remaining) of \(item.recoveryCodeCount) left").foregroundStyle(.secondary)
                if let left = model.revealCountdown[.init(field: "codes", slot: 0)] {
                    Text("\(left)s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(codes == nil ? "Reveal All" : "Hide", systemImage: codes == nil ? "eye" : "eye.slash") {
                    Task {
                        do { try await model.toggleReveal("codes") } catch { actions.report(error) }
                    }
                }
                .buttonStyle(.borderless)
                .help(codes == nil ? "Reveal (Touch ID)" : "Hide")
            }
        }
        .confirmationDialog("Export as a plain .txt file?", isPresented: $confirmExport) {
            Button("Export Unencrypted File") { actions.exportRecoveryCodes(item) }
        } message: {
            Text("The file will contain every code in plain text. Print it or move it somewhere safe, then delete it.")
        }
    }

    private func row(index: Int, code: String?, usedOn: Date?) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(index)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Group {
                if let code {
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .strikethrough(usedOn != nil)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.yellow.opacity(0.8)))
                } else {
                    Text(verbatim: "•••• ••••")
                }
            }
            .foregroundStyle(usedOn == nil ? .primary : .secondary)
            if let usedOn {
                Text("used \(usedOn, format: .dateTime.day().month().year())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !inTrash {
                Button { actions.copyRecoveryCode(item, index: index) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy and mark as used (Touch ID)")
                Toggle("Used", isOn: Binding(
                    get: { usedOn != nil },
                    set: { actions.setRecoveryCode(item, index: index, used: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Used")
            }
        }
    }

    private func warning(_ remaining: Int) -> some View {
        HStack {
            Label(remaining == 0 ? "No unused codes left — generate a new set" : "Only \(remaining) codes left — generate a new set",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(remaining == 0 ? .red : .orange)
            Spacer()
            if let value = item.url, let url = URL(string: value.hasPrefix("http") ? value : "https://\(value)") {
                Link(value, destination: url).lineLimit(1)
            }
        }
    }
}
