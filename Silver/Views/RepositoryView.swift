import SwiftUI

struct RepositoryView: View {
    let project: Project
    @Environment(LibraryStore.self) private var library
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: RepositoryStore
    @State private var showProjectSwitcher = false

    init(project: Project) {
        self.project = project
        _store = State(initialValue: RepositoryStore(url: project.url))
    }

    var body: some View {
        HSplitView {
            if store.sidebarVisible {
                sidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 320)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(.container, edges: .top)
            }
            VStack(spacing: 0) {
                Group {
                    switch store.section {
                    case .changes: ChangesView(store: store)
                    case .history: HistoryView(store: store)
                    case .branches: BranchesView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, -preferences.titlebarInset)
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationTitle(project.name)
        .toolbar { ToolbarSpacer(.flexible) }
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            store.section = RepositorySection(rawValue: preferences.layout.defaultSection) ?? .changes
            store.sidebarVisible = preferences.layout.sidebarInitiallyVisible
            await store.refresh()
        }
        .tint(preferences.layout.useProjectAccent ? project.color.color : preferences.accent.color)
        .onChange(of: preferences.layout.sidebarInitiallyVisible) { store.sidebarVisible = preferences.layout.sidebarInitiallyVisible }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await store.refresh() } }
        .sheet(isPresented: $store.showNewBranch) { NewBranchView(store: store) }
        .confirmationDialog("Bring your changes to \(store.pendingBranch?.name ?? "this branch")?", isPresented: Binding(get: { store.pendingBranch != nil }, set: { if !$0 { store.pendingBranch = nil } }), titleVisibility: .visible, presenting: store.pendingBranch) { branch in
            Button("Bring Changes") { Task { await store.bringChanges(to: branch) } }
            Button("Cancel", role: .cancel) { }
        } message: { _ in Text("Your uncommitted work can be brought to the other branch. If changes overlap, Silver keeps a backup while you resolve them.") }
        .alert(store.notice == nil ? "Git Operation Failed" : "Changes Need Attention", isPresented: Binding(get: { store.error != nil || store.notice != nil }, set: { if !$0 { store.error = nil; store.notice = nil } })) {
            Button("OK") { store.error = nil; store.notice = nil }
        } message: { Text(store.error ?? store.notice ?? "") }
        .focusedSceneValue(\.repositoryStore, store)
    }

    private var sidebar: some View {
        List(selection: $store.section) {
            Section("Repository") {
                ForEach(RepositorySection.allCases.filter { $0 != .branches || !preferences.layout.showSidebarBranches }) { section in
                    HStack {
                        Label(section.rawValue, systemImage: section.symbol)
                        Spacer()
                        if section == .changes, !store.files.isEmpty { Text("\(store.files.count)").font(.caption).foregroundStyle(.secondary) }
                    }.tag(section)
                }
            }
            if preferences.layout.showSidebarBranches { Section {
                ForEach((store.snapshot?.branches ?? []).filter { !$0.remote }.prefix(12)) { branch in
                    Button { Task { await store.switchBranch(branch) } } label: {
                        HStack {
                            Label(branch.name, systemImage: "arrow.triangle.branch").lineLimit(1)
                            Spacer()
                            if branch.current { Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                        }
                    }.buttonStyle(.plain).disabled(store.isBusy)
                }
                Button { store.showNewBranch = true } label: { Label("New Branch…", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.isBusy)
            } header: {
                Button("Branches") { store.section = .branches }.buttonStyle(.plain)
            } }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button { showProjectSwitcher.toggle() } label: {
                HStack(spacing: 10) {
                    ProjectIcon(project: project, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name).font(.headline).lineLimit(1)
                        Text(store.snapshot?.branch ?? "Repository").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.top, preferences.windowFullScreen ? 0 : 52).help("Switch Project (⌘P)").keyboardShortcut("p")
                .disabled(store.isBusy || store.isGenerating)
                .popover(isPresented: $showProjectSwitcher, arrowEdge: .trailing) { ProjectSwitcherView() }
                .contextMenu { Button("Customise Project…") { library.editingProject = library.activeProject } }
        }
    }



}

struct RepositoryStoreKey: FocusedValueKey { typealias Value = RepositoryStore }
extension FocusedValues {
    var repositoryStore: RepositoryStore? {
        get { self[RepositoryStoreKey.self] }
        set { self[RepositoryStoreKey.self] = newValue }
    }
}

struct NewBranchView: View {
    let store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Branch").font(.title2.bold())
            Text("Create a branch from \(store.snapshot?.branch ?? "HEAD").").foregroundStyle(.secondary)
            TextField("Branch name", text: $name).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create Branch") {
                    Task {
                        busy = true
                        do {
                            try await store.git.createBranch(name.trimmingCharacters(in: .whitespacesAndNewlines))
                            store.selectedCommitID = nil
                            try await store.reload()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }.padding(24).frame(width: 420).disabled(busy).interactiveDismissDisabled(busy)
    }
}
