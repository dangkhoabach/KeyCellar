import DKBSecretCore
import Foundation
import Observation

/// State behind the create/edit sheet. Field values are plain `String`s here
/// because `TextField` needs them; the sheet is short-lived and the model is
/// dropped as soon as it closes, which is the best a text field allows.
///
/// Editing: secret fields start empty and empty means "unchanged"; the
/// exceptions are an `.env` set and a set of recovery codes, whose editor is
/// the whole text, so their current values are revealed (one Touch ID) when
/// the sheet opens.
@MainActor
@Observable
final class ItemFormModel: Identifiable {
    enum Mode {
        case create(kind: SecretKind?)
        case edit(SecretItem)
    }

    enum ExpiryPreset: Hashable, CaseIterable {
        case none, days30, days90, days180, days365, custom

        var days: Int? {
            switch self {
            case .none, .custom: nil
            case .days30: 30
            case .days90: 90
            case .days180: 180
            case .days365: 365
            }
        }
    }

    let id = UUID()
    let mode: Mode
    var kind: SecretKind?
    var title = ""
    /// Template field key → text (metadata and secret fields alike).
    var values: [String: String] = [:]
    var envText = ""
    var tagsText = ""
    var projectId: String?
    var newProjectName = ""
    var environment: DeploymentEnvironment?
    var expiryPreset: ExpiryPreset = .none
    var customExpiry = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    var favorite = false
    /// "Replace Codes…": the editor starts empty instead of revealing the old
    /// set, and saving replaces it (plan RC9).
    var replacingCodes = false
    private(set) var validationMessage: String?
    private(set) var isLoading = false
    private(set) var saveError: String?

    private let vault: SecretVault
    private let items: ItemRepository
    private let projectRepository: ProjectRepository
    /// For `.envSet` edits: what the item held when the sheet opened.
    private var originalEnv: [String: String] = [:]
    /// For `.recoveryCodes` edits: the codes the item held when the sheet opened.
    private var originalCodes: [String] = []

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var availableProjects: [Project] { (try? projectRepository.all()) ?? [] }

    private let expiryPolicy: ExpiryPolicy

    init(mode: Mode, vault: SecretVault, items: ItemRepository, projects: ProjectRepository, expiryPolicy: ExpiryPolicy = ExpiryPolicy()) {
        self.mode = mode
        self.vault = vault
        self.items = items
        projectRepository = projects
        self.expiryPolicy = expiryPolicy
        switch mode {
        case .create(let kind):
            self.kind = kind
            if let kind { applyDefaultExpiry(kind) }
        case .edit(let item):
            kind = item.kind
            title = item.title
            values["service"] = item.service ?? ""
            values["url"] = item.url ?? ""
            values["username"] = item.username ?? ""
            for (key, value) in item.metadata { values[key] = value }
            projectId = item.projectId
            environment = item.environment
            favorite = item.favorite
            if let expires = item.expiresAt {
                expiryPreset = .custom
                customExpiry = expires
            }
            tagsText = ((try? items.tags(for: item.id)) ?? []).map(\.name).joined(separator: ", ")
        }
    }

    /// The kind's default lifetime, as the matching preset. Called whenever
    /// the kind is chosen while creating.
    func applyDefaultExpiry(_ kind: SecretKind) {
        expiryPreset = switch expiryPolicy.ttl(for: kind) {
        case 30: .days30
        case 90: .days90
        case 180: .days180
        case 365: .days365
        default: .none
        }
    }

    /// Fills the sheet from pasted text: the primary secret, plus the
    /// service `SecretDetector` recognised.
    func prefill(from text: String, detection: SecretDetector.Detection) {
        kind = detection.kind
        applyDefaultExpiry(detection.kind)
        if detection.kind == .envSet {
            envText = text
        } else if detection.kind == .recoveryCodes {
            loadCodes(text)
        } else if let primary = detection.kind.template.primaryField {
            values[primary.key] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let service = detection.service {
            values["service"] = service
            title = service
        }
    }

    /// The codes' text from a paste, a file or the clipboard detector; the
    /// account a Google file names fills an empty Account field.
    func loadCodes(_ text: String) {
        values["codes"] = text
        if (values["username"] ?? "").isEmpty, let account = RecoveryCodes.accountHint(text) {
            values["username"] = account
        }
    }

    /// What the codes editor holds, parsed; recomputed as the user types.
    var parsedCodes: [RecoveryCodes.Code] { RecoveryCodes.parse(values["codes"] ?? "") }

    func loadForEditing() async {
        guard case .edit(let item) = mode else { return }
        if item.kind == .recoveryCodes {
            if !replacingCodes { await loadCodesForEditing(item) }
            return
        }
        guard item.kind == .envSet else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let blobs = try items.blobs(for: item.id).filter { $0.slot == 0 && $0.field.hasPrefix(SecretItem.envFieldPrefix) }
            var pairs: [DotEnvFile.Pair] = []
            for blob in blobs.sorted(by: { $0.createdAt < $1.createdAt }) {
                let key = String(blob.field.dropFirst(SecretItem.envFieldPrefix.count))
                let value = try await vault.reveal(itemId: item.id, field: blob.field)
                pairs.append((key, value.string))
                originalEnv[key] = value.string
            }
            envText = DotEnvFile.serialize(pairs)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Shows the set as `serialize` writes it, used codes marked `[x]`, so
    /// the used state can be edited along with the codes.
    private func loadCodesForEditing(_ item: SecretItem) async {
        isLoading = true
        defer { isLoading = false }
        do {
            originalCodes = try await vault.reveal(itemId: item.id, field: "codes").string
                .split(separator: "\n").map(String.init)
            let used = item.usedRecoveryCodes
            values["codes"] = RecoveryCodes.serialize(originalCodes.enumerated().map { .init($1, used: used[$0 + 1] != nil) })
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Save

    var canSave: Bool { validate() == nil }

    func validate() -> String? {
        let bundle = AppLocale.bundle
        guard let kind else { return String(localized: "Choose a kind.", bundle: bundle) }
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "A title is required.", bundle: bundle) }
        if kind == .envSet {
            if DotEnvFile.parse(envText).isEmpty { return String(localized: "Add at least one KEY=VALUE line.", bundle: bundle) }
        } else if kind == .recoveryCodes {
            if parsedCodes.isEmpty { return String(localized: "Add at least one recovery code.", bundle: bundle) }
        } else if !isEditing, let primary = kind.template.primaryField,
                  (values[primary.key] ?? "").isEmpty {
            let label = String(localized: String.LocalizationValue(primary.label), bundle: bundle)
            return String(localized: "\(label) is required.", bundle: bundle)
        }
        return nil
    }

    func save() async -> Bool {
        validationMessage = validate()
        guard validationMessage == nil, let kind else { return false }
        do {
            let project = try resolveProject()
            let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            switch mode {
            case .create:
                var item = SecretItem(kind: kind, title: title.trimmingCharacters(in: .whitespaces))
                applyMetadata(to: &item, projectId: project)
                try await vault.create(item, tags: tags, secrets: secretsForCreate(kind))
            case .edit(let existing):
                var item = existing
                item.title = title.trimmingCharacters(in: .whitespaces)
                applyMetadata(to: &item, projectId: project)
                try await vault.updateMetadata(item, tags: tags)
                try await applySecretEdits(kind, itemId: item.id)
            }
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func resolveProject() throws -> String? {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return try projectRepository.findOrCreate(name: name).id }
        return projectId
    }

    private func applyMetadata(to item: inout SecretItem, projectId: String?) {
        let template = item.kind.template
        let previouslyUsed = item.usedRecoveryCodes
        item.projectId = projectId
        item.environment = environment
        item.favorite = favorite
        item.service = nonEmpty("service")
        item.url = nonEmpty("url")
        item.username = nonEmpty("username")
        item.metadata = [:]
        for spec in template.fields where !spec.isSecret && !["service", "url", "username", "environment"].contains(spec.key) {
            if let value = nonEmpty(spec.key) { item.metadata[spec.key] = value }
        }
        if item.kind == .recoveryCodes {
            let codes = parsedCodes
            item.recoveryCodeCount = codes.count
            item.usedRecoveryCodes = usedCodes(codes, previouslyUsed: previouslyUsed)
        }
        switch expiryPreset {
        case .none: item.expiresAt = nil
        case .custom: item.expiresAt = customExpiry
        default: item.expiresAt = Calendar.current.date(byAdding: .day, value: expiryPreset.days ?? 0, to: .now)
        }
    }

    /// Positions follow the new list: a code that was already used keeps
    /// its date wherever it moved to, one newly marked `[x]` gets today.
    private func usedCodes(_ codes: [RecoveryCodes.Code], previouslyUsed: [Int: Date]) -> [Int: Date] {
        var usedDate: [String: Date] = [:]
        for (index, date) in previouslyUsed where originalCodes.indices.contains(index - 1) {
            usedDate[originalCodes[index - 1]] = date
        }
        var used: [Int: Date] = [:]
        for (offset, code) in codes.enumerated() where code.used {
            used[offset + 1] = usedDate[code.value] ?? Date()
        }
        return used
    }

    /// The sealed form: one normalised code per line, no marks.
    private var codesBlob: String { parsedCodes.map(\.value).joined(separator: "\n") }

    private func nonEmpty(_ key: String) -> String? {
        let value = (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func secretsForCreate(_ kind: SecretKind) -> [String: SecretBytes] {
        var secrets: [String: SecretBytes] = [:]
        for spec in kind.template.secretFields {
            if let value = values[spec.key], !value.isEmpty { secrets[spec.key] = SecretBytes(value) }
        }
        if kind == .recoveryCodes {
            secrets["codes"] = SecretBytes(codesBlob)
        }
        if kind == .envSet {
            for (key, value) in DotEnvFile.parse(envText) {
                secrets[SecretItem.envFieldPrefix + key] = SecretBytes(value)
            }
        }
        return secrets
    }

    private func applySecretEdits(_ kind: SecretKind, itemId: String) async throws {
        for spec in kind.template.secretFields where spec.key != "codes" {
            if let value = values[spec.key], !value.isEmpty {
                try await vault.setSecret(itemId: itemId, field: spec.key, value: SecretBytes(value))
            }
        }
        // `setSecret`, not `rotate`: a replaced set is dead at the provider,
        // so there is no history worth keeping.
        if kind == .recoveryCodes, codesBlob != originalCodes.joined(separator: "\n") {
            try await vault.setSecret(itemId: itemId, field: "codes", value: SecretBytes(codesBlob))
        }
        guard kind == .envSet else { return }
        let edited = Dictionary(DotEnvFile.parse(envText), uniquingKeysWith: { _, last in last })
        for (key, value) in edited where originalEnv[key] != value {
            try await vault.setSecret(itemId: itemId, field: SecretItem.envFieldPrefix + key, value: SecretBytes(value))
        }
        for key in originalEnv.keys where edited[key] == nil {
            try await vault.deleteSecret(itemId: itemId, field: SecretItem.envFieldPrefix + key)
        }
    }
}
