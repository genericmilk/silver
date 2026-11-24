import SwiftUI

struct ProjectSwitcherView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var highlighted: UUID?
    @FocusState private var searchFocused: Bool
    private var results: [Project] {
        library.sortedProjects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a project", text: $search).textFieldStyle(.plain)
                    .focused($searchFocused).onSubmit { openHighlighted() }
            }.padding(14)
            Divider()
            if results.isEmpty {
                ContentUnavailableView.search(text: search).frame(height: 180)
            } else {
                List(selection: $highlighted) {
                    ForEach(results) { project in
                        HStack(spacing: 10) {
                            ProjectIcon(project: project, size: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).fontWeight(.medium).lineLimit(1)
                                Text(project.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if project.id == library.activeProject?.id { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4).tag(project.id).contentShape(Rectangle())
                            .onTapGesture { open(project) }
                    }
                }.listStyle(.inset).frame(height: min(280, CGFloat(results.count) * 56 + 14))
            }
            Divider()
            HStack {
                Button("All Projects") { dismiss(); library.activeProject = nil }
                Spacer()
                Button("Open Repository…") { dismiss(); library.chooseRepository() }
            }.buttonStyle(.borderless).font(.callout).padding(12)
        }
        .frame(width: 380)
        .onAppear { searchFocused = true; highlighted = results.first?.id }
        .onChange(of: search) { highlighted = results.first?.id }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openHighlighted(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }
    private func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == highlighted } ?? 0
        highlighted = results[min(max(0, index + offset), results.count - 1)].id
    }
    private func openHighlighted() {
        if let project = results.first(where: { $0.id == highlighted }) ?? results.first { open(project) }
    }
    private func open(_ project: Project) {
        dismiss()
        if library.activeProject?.id != project.id { Task { await library.open(project.url) } }
    }
}
