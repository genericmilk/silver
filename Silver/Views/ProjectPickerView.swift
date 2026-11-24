import SwiftUI

struct ProjectPickerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Preferences.self) private var preferences
    @State private var search = ""
    @State private var selected: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var projects: [Project] {
        let items = library.sortedProjects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
        return preferences.layout.projectSort == "name" ? items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : items
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                AnimatedProjectIcon(symbol: "arrow.triangle.branch", color: preferences.accent, size: 88, image: AppIconRenderer.image)
                    .frame(width: 88, height: 88).padding(.bottom, 24)
                Text("Welcome to Silver").font(.largeTitle).fontWeight(.bold)
                Text("A home for your repositories.")
                    .font(.title3).foregroundStyle(.secondary).padding(.top, 6)
                VStack(spacing: 14) {
                    action("Open a Repository…", symbol: "folder", shortcut: "⌘O", action: library.chooseRepository)
                    action("Clone a Repository…", symbol: "square.and.arrow.down", action: { library.showClone = true })
                    action("Create a Repository…", symbol: "plus.square", action: library.createRepository)
                }.padding(.top, 38).frame(width: 246)
                Spacer()
            }
            .frame(width: 380)
            .frame(maxHeight: .infinity)
            .background(.background)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Projects").font(.title2).fontWeight(.semibold)
                    Spacer()
                    if library.isOpening { ProgressView().controlSize(.small) }
                    Menu {
                        Button("Open Repository…", action: library.chooseRepository)
                        Button("Clone Repository…") { library.showClone = true }
                        Button("New Repository…", action: library.createRepository)
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().help("Add a project")
                }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 18)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search projects", text: $search).textFieldStyle(.plain)
                        .onSubmit { openFirstProject() }
                        .onChange(of: search) { selected = projects.first?.id }
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 24).padding(.bottom, 14)
                if library.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Your next great project", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Open an existing repository, or start something new.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if projects.isEmpty {
                    ContentUnavailableView.search(text: search).frame(maxHeight: .infinity)
                } else {
                    List(selection: $selected) {
                        let pinned = projects.filter(\.pinned)
                        if !pinned.isEmpty {
                            Section("Pinned") { ForEach(pinned) { project in projectRow(project) } }
                        }
                        Section("Recent") { ForEach(projects.filter { !$0.pinned }) { project in projectRow(project) } }
                    }
                    .listStyle(.inset)
                    .onKeyPress(.return) {
                        guard let project = projects.first(where: { $0.id == selected }) ?? projects.first else { return .ignored }
                        Task { await library.open(project.url) }
                        return .handled
                    }
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary)
        }
        .navigationTitle("Silver")
        .toolbar {
            ToolbarSpacer(.flexible)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .disabled(library.isOpening)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.projects.count)
    }

    private func openFirstProject() {
        if let project = projects.first(where: { $0.id == selected }) ?? projects.first { Task { await library.open(project.url) } }
    }

    private func action(_ title: String, symbol: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(preferences.accent.color).frame(width: 24)
                Text(title).font(.body)
                Spacer(minLength: 0)
                if let shortcut { Text(shortcut).font(.caption).foregroundStyle(.tertiary) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.vertical, 5)
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            ProjectIcon(project: project)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.headline).lineLimit(1)
                if preferences.layout.showProjectPaths { Text(project.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer()
            if preferences.layout.showProjectDates { Text(project.lastOpened, style: .relative).font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, preferences.layout.rowPadding + 3)
        .tag(project.id)
        .contentShape(Rectangle())
        .onTapGesture(count: preferences.layout.singleClickProjects ? 1 : 2) { Task { await library.open(project.url) } }
        .contextMenu {
            Button("Open") { Task { await library.open(project.url) } }
            Button(project.pinned ? "Unpin" : "Pin") { var item = project; item.pinned.toggle(); library.update(item) }
            Button("Customise…") { library.editingProject = project }
            Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }
            Divider()
            Button("Remove from Recents") { library.remove(project) }
        }
        .accessibilityAction(named: "Open") { Task { await library.open(project.url) } }
        .accessibilityHint(preferences.layout.singleClickProjects ? "Click to open" : "Double-click to open")
    }
}
