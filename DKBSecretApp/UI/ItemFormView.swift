import DKBSecretCore
import SwiftUI

/// The create/edit sheet (plan §8 Phase 4.4). Creating starts on a kind
/// picker unless the kind is already known (clipboard detection, a dropped
/// .env file); editing goes straight to the fields.
struct ItemFormView: View {
    @Bindable var model: ItemFormModel
    let onDone: () -> Void
    @State private var saving = false
    @State private var generatorField: String?

    var body: some View {
        Group {
            if let kind = model.kind {
                fields(kind)
            } else {
                kindPicker
            }
        }
        .frame(width: 560)
        .frame(minHeight: 420)
    }

    // MARK: Step 1

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(SecretKind.allCases, id: \.self) { kind in
                    Button {
                        model.kind = kind
                        model.applyDefaultExpiry(kind)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: kind.systemImage).font(.system(size: 28))
                            Text(kind.singularTitle).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDone).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    // MARK: Step 2

    private func fields(_ kind: SecretKind) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label(kind.singularTitle, systemImage: kind.systemImage).font(.title3.bold())
                Spacer()
                Text(model.isEditing ? "Editing" : "New").foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 16)
            Form {
                Section {
                    TextField("Title", text: $model.title, prompt: Text("e.g. Resend – CaPheSuaDa"))
                    ForEach(kind.template.fields.filter { !$0.isSecret }, id: \.key) { spec in
                        metadataField(spec)
                    }
                }
                Section(kind == .envSet ? "Variables" : "Secrets") {
                    if kind == .envSet {
                        envEditor
                    }
                    ForEach(kind.template.secretFields, id: \.key) { spec in
                        secretField(spec)
                    }
                }
                Section("Organize") {
                    projectPicker
                    TextField("Tags", text: $model.tagsText, prompt: Text("comma, separated"))
                    Toggle("Favorite", isOn: $model.favorite)
                    Picker("Expires", selection: $model.expiryPreset) {
                        Text("Never").tag(ItemFormModel.ExpiryPreset.none)
                        Text("In 30 days").tag(ItemFormModel.ExpiryPreset.days30)
                        Text("In 90 days").tag(ItemFormModel.ExpiryPreset.days90)
                        Text("In 180 days").tag(ItemFormModel.ExpiryPreset.days180)
                        Text("In 1 year").tag(ItemFormModel.ExpiryPreset.days365)
                        Text("On a date…").tag(ItemFormModel.ExpiryPreset.custom)
                    }
                    if model.expiryPreset == .custom {
                        DatePicker("Date", selection: $model.customExpiry, displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(model.isLoading)
            .overlay {
                if model.isLoading { ProgressView("Decrypting current values…") }
            }

            Divider()
            HStack {
                if let message = model.validationMessage ?? model.saveError {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onDone).keyboardShortcut(.cancelAction)
                Button(model.isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || model.isLoading)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func metadataField(_ spec: FieldSpec) -> some View {
        if spec.key == "environment" {
            Picker("Environment", selection: $model.environment) {
                Text("None").tag(DeploymentEnvironment?.none)
                ForEach(DeploymentEnvironment.allCases, id: \.self) { Text($0.title).tag(DeploymentEnvironment?.some($0)) }
            }
        } else if spec.isMultiline {
            LabeledContent(LocalizedStringKey(spec.label)) {
                TextEditor(text: binding(spec.key))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60)
            }
        } else {
            TextField(LocalizedStringKey(spec.label), text: binding(spec.key))
        }
    }

    @ViewBuilder
    private func secretField(_ spec: FieldSpec) -> some View {
        let prompt = model.isEditing ? Text("Leave empty to keep the current value") : Text("")
        if spec.isMultiline {
            LabeledContent(LocalizedStringKey(spec.label)) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextEditor(text: binding(spec.key))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: spec.isPrimary ? 100 : 60)
                    if model.isEditing {
                        Text("Leave empty to keep the current value").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack {
                SecureField(LocalizedStringKey(spec.label), text: binding(spec.key), prompt: prompt)
                Button {
                    generatorField = spec.key
                } label: {
                    Image(systemName: "dice")
                }
                .buttonStyle(.borderless)
                .help("Generate")
                .popover(isPresented: Binding(get: { generatorField == spec.key }, set: { if !$0 { generatorField = nil } })) {
                    PasswordGeneratorView { generated in
                        model.values[spec.key] = generated
                        generatorField = nil
                    }
                }
            }
        }
    }

    private var envEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $model.envText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
            HStack {
                Text("One KEY=VALUE per line. Comments and `export` are fine.")
                Spacer()
                Button("Paste File Contents") {
                    if let text = NSPasteboard.general.string(forType: .string) { model.envText = text }
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var projectPicker: some View {
        HStack {
            Picker("Project", selection: $model.projectId) {
                Text("None").tag(String?.none)
                ForEach(model.availableProjects) { Text($0.name).tag(String?.some($0.id)) }
            }
            TextField("", text: $model.newProjectName, prompt: Text("or new project name"))
                .frame(width: 160)
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { model.values[key] ?? "" }, set: { model.values[key] = $0 })
    }

    private func save() {
        saving = true
        Task {
            if await model.save() { onDone() }
            saving = false
        }
    }
}
