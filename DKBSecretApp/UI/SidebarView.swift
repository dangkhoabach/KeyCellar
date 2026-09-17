import DKBSecretCore
import SwiftUI

/// Smart lists, kinds, projects, tags, Trash, Settings. Styling ported from
/// DKB Monitor's sidebar: unselected icons dimmed to `.secondary`, resizable
/// column, focus reclaimed after every selection change (without it the
/// selection pill renders in the inactive gray even though the window is key).
struct SidebarView: View {
    @Bindable var navigation: AppNavigationState
    let model: SidebarViewModel
    @FocusState private var focused: Bool
    @State private var renaming: Renaming?
    @State private var renameText = ""

    private struct Renaming: Identifiable {
        enum Target { case project(Project), tag(Tag) }
        let target: Target
        var id: String {
            switch target {
            case .project(let p): "p-\(p.id)"
            case .tag(let t): "t-\(t.id)"
            }
        }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { navigation.sidebarSelection },
            set: { if let value = $0 { navigation.sidebarSelection = value } }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                row(.section(.all), SidebarSection.all.title, SidebarSection.all.systemImage, count: model.counts.all)
                row(.section(.favorites), SidebarSection.favorites.title, SidebarSection.favorites.systemImage, count: model.counts.favorites)
                row(.section(.recent), SidebarSection.recent.title, SidebarSection.recent.systemImage)
                row(.section(.expiring), SidebarSection.expiring.title, SidebarSection.expiring.systemImage,
                    count: model.counts.expiring, badge: model.counts.expiring > 0)
            }
            Section("Kinds") {
                ForEach(SecretKind.allCases, id: \.self) { kind in
                    row(.kind(kind), kind.title, kind.systemImage, count: model.counts.byKind[kind] ?? 0)
                }
            }
            if !model.projects.isEmpty {
                Section("Projects") {
                    ForEach(model.projects) { project in
                        row(.project(project.id), LocalizedStringKey(project.name), "folder",
                            count: model.counts.byProject[project.id] ?? 0, tint: ProjectColor(project.color).color)
                            .dropDestination(for: String.self) { ids, _ in
                                model.move(itemIds: ids, toProject: project.id)
                                return true
                            }
                            .contextMenu { projectMenu(project) }
                    }
                }
            }
            if !model.tags.isEmpty {
                Section("Tags") {
                    ForEach(model.tags) { tag in
                        row(.tag(tag.id), LocalizedStringKey(tag.name), "tag")
                            .contextMenu { tagMenu(tag) }
                    }
                }
            }
            Section {
                row(.section(.trash), SidebarSection.trash.title, SidebarSection.trash.systemImage, count: model.counts.trash)
                row(.section(.settings), SidebarSection.settings.title, SidebarSection.settings.systemImage)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .focused($focused)
        .onAppear { focused = true; model.start() }
        .onChange(of: navigation.sidebarSelection) { _, _ in focused = true }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { target in
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename(target) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Enter a new name.")
        }
    }

    private func row(_ value: SidebarSelection, _ title: LocalizedStringKey, _ symbol: String,
                     count: Int? = nil, badge: Bool = false, tint: Color? = nil) -> some View {
        let selected = navigation.sidebarSelection == value
        return Label {
            HStack {
                Text(title)
                Spacer()
                if let count, count > 0 {
                    Text(count, format: .number)
                        .font(.caption)
                        .foregroundStyle(badge && !selected ? Color.white : Color.secondary)
                        .padding(.horizontal, badge ? 6 : 0)
                        .background(badge && !selected ? Color.orange : Color.clear, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(selected ? Color.primary : (tint ?? Color.secondary))
        }
        .tag(value)
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button("Rename…") { renameText = project.name; renaming = Renaming(target: .project(project)) }
        Menu("Color") {
            ForEach(ProjectColor.allCases, id: \.self) { color in
                Button {
                    model.setProjectColor(project, color.rawValue)
                } label: {
                    Label(color.title, systemImage: project.color == color.rawValue ? "checkmark.circle.fill" : "circle.fill")
                }
                .tint(color.color)
            }
        }
        Divider()
        Button("Delete Project", role: .destructive) { model.deleteProject(project) }
    }

    @ViewBuilder
    private func tagMenu(_ tag: Tag) -> some View {
        Button("Rename…") { renameText = tag.name; renaming = Renaming(target: .tag(tag)) }
        Button("Delete Tag", role: .destructive) { model.deleteTag(tag) }
    }

    private func commitRename(_ target: Renaming) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch target.target {
        case .project(let p): model.renameProject(p, to: name)
        case .tag(let t): model.renameTag(t, to: name)
        }
    }
}

/// The handful of project colours offered in the context menu; stored by
/// name so the row is readable in the database.
enum ProjectColor: String, CaseIterable {
    case gray, blue, green, orange, red, purple

    init(_ raw: String?) { self = raw.flatMap(ProjectColor.init(rawValue:)) ?? .gray }

    var color: Color {
        switch self {
        case .gray: .secondary
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .gray: "Gray"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .red: "Red"
        case .purple: "Purple"
        }
    }
}
