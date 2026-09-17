import SwiftUI

/// Sidebar + item list + detail. The list and detail columns are empty
/// placeholders until Phase 4; the sidebar styling (dimmed unselected icons,
/// resizable column, focus reclaimed after every tab switch) is ported
/// verbatim from DKB Monitor's `ContentView`, where each of those was a fix
/// for a real problem.
struct ContentView: View {
    @Bindable private var navigationState = AppNavigationState.shared
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: Binding(
                get: { navigationState.sidebarSelection },
                set: { if let newValue = $0 { navigationState.sidebarSelection = newValue } }
            )) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section == navigationState.sidebarSelection ? Color.primary : Color.secondary)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .focused($sidebarFocused)
        } content: {
            ContentUnavailableView(navigationState.sidebarSelection.title, systemImage: navigationState.sidebarSelection.systemImage)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            ContentUnavailableView("No Item Selected", systemImage: "key")
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { sidebarFocused = true }
        .onChange(of: navigationState.sidebarSelection) { _, _ in sidebarFocused = true }
    }
}
