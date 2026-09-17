import DKBSecretCore
import SwiftUI

struct ItemDetailView: View {
    let model: ItemDetailViewModel
    let actions: ItemActions
    let inTrash: Bool
    @State private var confirmPurge = false
    @State private var confirmEnvExport = false

    var body: some View {
        if let item = model.item {
            Form {
                header(item)
                metadataSection(item)
                secretsSection(item)
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
            .confirmationDialog("Export as a plain .env file?", isPresented: $confirmEnvExport) {
                Button("Export Unencrypted File") { actions.exportEnvFile(item) }
            } message: {
                Text("The file will contain every value in plain text. Keep it out of version control and delete it when you're done.")
            }
            .confirmationDialog("Delete this item permanently?", isPresented: $confirmPurge) {
                Button("Delete Permanently", role: .destructive) { actions.purge(item) }
            } message: {
                Text("Its secrets and history cannot be recovered.")
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
                Button("Delete Permanently", systemImage: "trash.slash") { confirmPurge = true }
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
            ForEach(model.secretFields, id: \.self) { field in
                let spec = template.fields.first { $0.key == field }
                SecretFieldRow(
                    label: spec?.label ?? String(field.dropFirst(SecretItem.envFieldPrefix.count)),
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
        }
    }

    private func historySection(_ item: SecretItem) -> some View {
        Section("History") {
            ForEach(model.secretFields.filter { (model.historyCounts[$0] ?? 0) > 0 }, id: \.self) { field in
                let label = item.kind.template.fields.first { $0.key == field }?.label ?? field
                DisclosureGroup("\(label) — \(model.historyCounts[field] ?? 0) previous") {
                    ForEach(1...(model.historyCounts[field] ?? 1), id: \.self) { slot in
                        SecretFieldRow(
                            label: "Version -\(slot)", field: field, slot: slot, model: model,
                            onCopy: { actions.copy(item, field: field, slot: slot) },
                            onError: { actions.report($0) }
                        )
                    }
                }
            }
        }
    }
}
