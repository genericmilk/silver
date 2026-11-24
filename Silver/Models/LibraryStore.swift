import SwiftUI

@MainActor @Observable
final class LibraryStore {
    var projects: [Project] = []
    var activeProject: Project?
    var error: String?
    var isOpening = false
    var showClone = false
    var showOpenPanel = false
    var editingProject: Project?
    var pendingProject: Project?
    var clonedRepository: URL?

    init() {
        if let data = UserDefaults.standard.data(forKey: "projects"), let projects = try? JSONDecoder().decode([Project].self, from: data) {
            self.projects = projects
        }
    }

    var sortedProjects: [Project] {
        projects.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.lastOpened > b.lastOpened }
    }

    func save() {
        if let data = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(data, forKey: "projects") }
    }

    func update(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) { projects[i] = project }
        if activeProject?.id == project.id { activeProject = project }
        save()
    }

    func remove(_ project: Project) { projects.removeAll { $0.id == project.id }; save() }

    func open(_ url: URL) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let root = try await GitRepository(url: url).root()
            if let project = projects.first(where: { $0.path == root.path }) { activate(project) }
            else { pendingProject = Project(path: root.path, name: root.lastPathComponent) }
        } catch { self.error = error.localizedDescription }
    }

    func add(_ project: Project) {
        guard !projects.contains(where: { $0.path == project.path }) else { return }
        projects.append(project)
        pendingProject = nil
        activate(project)
    }
    private func activate(_ value: Project) {
        var project = value
        project.lastOpened = Date()
        update(project)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.2)) { activeProject = project }
        NSDocumentController.shared.noteNewRecentDocumentURL(project.url)
    }

    func chooseRepository() {
        showOpenPanel = true
    }

    func createRepository() {
        let panel = NSSavePanel()
        panel.title = "New Repository"
        panel.nameFieldStringValue = "Untitled"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try await GitRepository.initialize(at: url)
                    await self.open(url)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
