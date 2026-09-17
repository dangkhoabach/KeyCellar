import DKBSecretCore
import Foundation
import GRDB
import Observation

/// One item, its tags and the shape of its secrets (which fields exist, how
/// much history), plus whatever is currently revealed. Revealed values are
/// kept as `SecretBytes` and dropped again after `revealSeconds`.
@MainActor
@Observable
final class ItemDetailViewModel {
    private(set) var item: SecretItem?
    private(set) var tags: [Tag] = []
    /// field → number of history slots (blobs with slot ≥ 1).
    private(set) var historyCounts: [String: Int] = [:]
    /// Field keys present for this item, template order first, then any
    /// dynamic `env.*` keys alphabetically.
    private(set) var secretFields: [String] = []
    private(set) var revealed: [RevealKey: SecretBytes] = [:]
    private(set) var revealCountdown: [RevealKey: Int] = [:]

    var revealSeconds = 30

    struct RevealKey: Hashable {
        let field: String
        let slot: Int
    }

    private let vault: SecretVault
    private let dbQueue: DatabaseQueue
    private var observation: Task<Void, Never>?
    private var timers: [RevealKey: Task<Void, Never>] = [:]

    init(vault: SecretVault, dbQueue: DatabaseQueue) {
        self.vault = vault
        self.dbQueue = dbQueue
    }

    func show(itemId: String?) {
        hideAll()
        observation?.cancel()
        guard let itemId else {
            item = nil
            return
        }
        let tracking = ValueObservation.tracking { db -> (SecretItem?, [Tag], [SecretBlob]) in
            let item = try SecretItem.fetchOne(db, key: itemId)
            let tags = try Tag.fetchAll(db, sql: """
                SELECT t.* FROM tags t JOIN item_tags it ON it.tag_id = t.id WHERE it.item_id = ? ORDER BY t.name COLLATE NOCASE
                """, arguments: [itemId])
            let blobs = try SecretBlob.filter(Column("item_id") == itemId).fetchAll(db)
            return (item, tags, blobs)
        }
        let dbQueue = dbQueue
        observation = Task { [weak self] in
            do {
                for try await (item, tags, blobs) in tracking.values(in: dbQueue) {
                    guard let self else { return }
                    self.item = item
                    self.tags = tags
                    apply(blobs: blobs, kind: item?.kind)
                }
            } catch {}
        }
    }

    private func apply(blobs: [SecretBlob], kind: SecretKind?) {
        var counts: [String: Int] = [:]
        for blob in blobs where blob.slot >= 1 { counts[blob.field, default: 0] += 1 }
        historyCounts = counts
        let present = Set(blobs.map(\.field))
        let templated = kind?.template.secretFields.map(\.key).filter(present.contains) ?? []
        let dynamic = present.subtracting(templated).sorted()
        secretFields = templated + dynamic
    }

    // MARK: Reveal

    func isRevealed(_ field: String, slot: Int = 0) -> Bool {
        revealed[RevealKey(field: field, slot: slot)] != nil
    }

    func revealedValue(_ field: String, slot: Int = 0) -> String? {
        revealed[RevealKey(field: field, slot: slot)]?.string
    }

    func toggleReveal(_ field: String, slot: Int = 0) async throws {
        let key = RevealKey(field: field, slot: slot)
        if revealed[key] != nil {
            hide(key)
            return
        }
        guard let item else { return }
        let secret = try await vault.reveal(itemId: item.id, field: field, slot: slot)
        revealed[key] = secret
        revealCountdown[key] = revealSeconds
        timers[key] = Task { [weak self] in
            while let self, let left = revealCountdown[key], left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                revealCountdown[key] = left - 1
            }
            self?.hide(key)
        }
    }

    func hide(_ key: RevealKey) {
        timers[key]?.cancel()
        timers[key] = nil
        revealed[key] = nil
        revealCountdown[key] = nil
    }

    func hideAll() {
        for key in Array(revealed.keys) { hide(key) }
    }
}
