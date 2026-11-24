import SwiftUI
import UniformTypeIdentifiers

@main
struct SilverApp: App {
    @State private var library = LibraryStore()
    @State private var preferences = Preferences()

    var body: some Scene {
        Window("Silver", id: "main") {
            RootView()
                .environment(library)
                .environment(preferences)
                .tint(preferences.accent.color)
                .font(.system(size: preferences.layout.interfaceSize, design: preferences.layout.fontDesign))
                .environment(\.defaultMinListRowHeight, preferences.layout.rowHeight)
                .preferredColorScheme(preferences.scheme)
                .frame(minWidth: 980, minHeight: 640)
                .task { preferences.updateDockIcon() }
                .onOpenURL { url in Task { await library.open(url) } }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            RepositoryCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open Repository…", action: library.chooseRepository).keyboardShortcut("o")
                Button("Clone Repository…") { library.showClone = true }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("New Repository…", action: library.createRepository).keyboardShortcut("n")
                Divider()
                Button("Project Library") { library.activeProject = nil }.keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(library.activeProject == nil)
            }
        }
        Settings {
            SettingsView().environment(preferences)
                .tint(preferences.accent.color)
                .preferredColorScheme(preferences.scheme)
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        @Bindable var library = library
        Group {
            if let project = library.activeProject {
                RepositoryView(project: project).id(project.id)
            } else {
                ProjectPickerView()
            }
        }
        .background(WindowContentLayout())
        .sheet(isPresented: $library.showClone, onDismiss: {
            if let url = library.clonedRepository {
                library.clonedRepository = nil
                Task { await library.open(url) }
            }
        }) { CloneView() }
        .fileImporter(isPresented: $library.showOpenPanel, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await library.open(url) }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .sheet(item: $library.editingProject) { project in ProjectEditor(project: project) }
        .sheet(item: $library.pendingProject) { project in ProjectEditor(project: project, isAdding: true) }
        .alert("Unable to Open Repository", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}

struct RepositoryCommands: Commands {
    @FocusedValue(\.repositoryStore) private var store
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { store?.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option]).disabled(store == nil)
        }
    }
}
