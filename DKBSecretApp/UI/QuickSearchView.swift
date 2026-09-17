import DKBSecretCore
import SwiftUI

/// Type → ranked hits → Enter copies the primary secret, ⌘Enter opens the
/// item in the main window. Shared by the menu bar dropdown and the
/// floating `QuickSearchPanel`.
@MainActor
@Observable
final class QuickSearchModel {
    var query = "" { didSet { search() } }
    private(set) var results: [SecretItem] = []
    var selectedIndex = 0

    private let repository: ItemRepository
    let limit: Int

    init(repository: ItemRepository, limit: Int = 8) {
        self.repository = repository
        self.limit = limit
        search()
    }

    func search() {
        let all = (try? repository.fetch(ItemQuery(scope: .all, search: query))) ?? []
        results = QuickSearchRanker.rank(all, query: query, limit: limit)
        selectedIndex = 0
    }

    var selected: SecretItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    func reset() {
        query = ""
    }
}

struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let onCopy: (SecretItem) -> Void
    let onOpen: (SecretItem) -> Void
    let onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search secrets", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { if let item = model.selected { onCopy(item) } }
                    .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), let item = model.selected else { return .ignored }
                        onOpen(item)
                        return .handled
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            if model.results.isEmpty {
                Text(model.query.isEmpty ? "No items yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == model.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { onCopy(item) }
                            .onHover { if $0 { model.selectedIndex = index } }
                    }
                }
                .padding(6)
            }
            Divider()
            HStack {
                Text("↩ copy").foregroundStyle(.secondary)
                Text("⌘↩ open").foregroundStyle(.secondary)
                Spacer()
                Text("Touch ID on copy").foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .onAppear { focused = true }
    }

    private func row(_ item: SecretItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage).frame(width: 22).foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text([item.service, item.username].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let env = item.environment {
                Circle().fill(env.color).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(selected ? .white : .primary)
    }
}
