import SwiftUI

struct WorkspaceSettings: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Repository") {
                Picker("Open repositories to", selection: $preferences.layout.defaultSection) {
                    ForEach(RepositorySection.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Show sidebar when opening a repository", isOn: $preferences.layout.sidebarInitiallyVisible)
                Toggle("Show branches in the sidebar", isOn: $preferences.layout.showSidebarBranches)
                Toggle("Show file paths", isOn: $preferences.layout.showFilePaths)
                Toggle("Show file status labels", isOn: $preferences.layout.showFileStatus)
            }
            Section("Project Library") {
                Picker("Sort projects by", selection: $preferences.layout.projectSort) {
                    Text("Last Opened").tag("recent")
                    Text("Name").tag("name")
                }
                Toggle("Show project paths", isOn: $preferences.layout.showProjectPaths)
                Toggle("Show when projects were last opened", isOn: $preferences.layout.showProjectDates)
                Toggle("Open projects with a single click", isOn: $preferences.layout.singleClickProjects)
            }
        }.formStyle(.grouped)
    }
}
