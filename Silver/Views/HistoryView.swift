import SwiftUI

struct HistoryView: View {
    @Bindable var store: RepositoryStore
    @Environment(Preferences.self) private var preferences
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("History").font(.headline)
                    Spacer()
                    Text("\(store.commits.count)").font(.caption).foregroundStyle(.secondary)
                }.padding(16)
                TextField("Search commits", text: $store.search).textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 12)
                Divider()
                if store.commits.isEmpty {
                    ContentUnavailableView(store.search.isEmpty ? "No Commits Yet" : "No Matching Commits", systemImage: "clock", description: Text(store.search.isEmpty ? "Your first commit starts the story." : "Try a different name, message, or commit ID."))
                        .frame(maxHeight: .infinity)
                } else {
                    List(selection: $store.selectedCommitID) {
                        ForEach(store.commits) { commit in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: commit.parents.count > 1 ? "arrow.triangle.merge" : "circle.inset.filled")
                                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(commit.subject).fontWeight(.medium).lineLimit(2)
                                    HStack {
                                        Text(commit.author).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(commit.date, style: .relative).lineLimit(1)
                                    }.font(.caption).foregroundStyle(.secondary)
                                    if !commit.decorations.isEmpty {
                                        Label(commit.decorations, systemImage: "tag").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }.padding(.vertical, preferences.layout.rowPadding).tag(commit.id)
                                .contextMenu {
                                    Button("Copy Commit ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.id, forType: .string) }
                                    Button("Copy Commit Message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.subject + (commit.body.isEmpty ? "" : "\n\n" + commit.body), forType: .string) }
                                }
                        }
                    }.listStyle(.inset)
                }
                Text("Showing the latest 500 commits on this branch.").font(.caption2).foregroundStyle(.tertiary).padding(10)
            }.frame(minWidth: 300, idealWidth: 350, maxWidth: 470)
            Group {
                if let commit = store.selectedCommit {
                    CommitDetailView(git: store.git, commit: commit).id(commit.id)
                } else {
                    ContentUnavailableView("Select a Commit", systemImage: "clock", description: Text("Explore the changes that brought you here."))
                }
            }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CommitDetailView: View {
    let git: GitRepository
    let commit: GitCommit
    @State private var files: [CommitFile] = []
    @State private var selectedPath: String?
    @State private var diff = ""
    @State private var media: MediaComparison?
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(commit.subject).font(.title2).fontWeight(.semibold).textSelection(.enabled)
                HStack {
                    Label(commit.author, systemImage: "person.crop.circle")
                    Spacer()
                    Text(commit.date, format: .dateTime.day().month().year().hour().minute())
                }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(commit.shortID).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.id, forType: .string) } label: {
                        Image(systemName: "doc.on.doc")
                    }.buttonStyle(.plain).help("Copy commit ID")
                    Spacer()
                }.foregroundStyle(.secondary)
                if !commit.body.isEmpty {
                    ScrollView { Text(commit.body).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
                }
            }.padding(20)
            Divider()
            HStack {
                Text("\(files.count) changed \(files.count == 1 ? "file" : "files")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("File", selection: $selectedPath) {
                    Text("All Files").tag(String?.none)
                    ForEach(files) { file in Text(file.path).tag(Optional(file.path)) }
                }.labelsHidden().frame(maxWidth: 280)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { ContentUnavailableView("Unable to Load Commit", systemImage: "exclamationmark.triangle", description: Text(error)).frame(maxHeight: .infinity) }
            else if let media { MediaComparisonView(comparison: media).id(selectedPath).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { DiffView(text: diff).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            do {
                files = try await git.files(in: commit)
                if files.count == 1 { selectedPath = files[0].path }
            }
            catch { self.error = error.localizedDescription }
        }
        .task(id: selectedPath) {
            loading = true
            error = nil
            media = nil
            do {
                if let file = files.first(where: { $0.path == selectedPath }), let comparison = await git.mediaComparison(commit: commit, file: file) {
                    guard !Task.isCancelled else { return }
                    media = comparison
                    loading = false
                    return
                }
                let result = try await git.diff(commit: commit, path: selectedPath)
                guard !Task.isCancelled else { return }
                diff = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}
