import SwiftUI

struct ChangesView: View {
    @Bindable var store: RepositoryStore
    @Environment(Preferences.self) private var preferences
    @Environment(LibraryStore.self) private var library
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Changes").font(.headline)
                    Spacer(minLength: 4)
                    if store.isBusy { ProgressView().controlSize(.small).help(store.activity) }
                    repositoryActions
                    Menu {
                        Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.git.url.path) }
                        Button("Copy Repository Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.git.url.path, forType: .string) }
                        Button("Customise Project…") { library.editingProject = library.activeProject }
                        SettingsLink { Text("Settings…") }
                        Divider()
                        Button("Check All") { store.selection.setAll(true) }
                        Button("Uncheck All") { store.selection.setAll(false) }
                        Divider()
                        Button("Stage All", action: { Task { await store.stageAll() } }).disabled(store.unstaged.isEmpty)
                        Button("Unstage All", action: { Task { await store.unstageAll() } }).disabled(store.staged.isEmpty)
                        Divider()
                        Button("Discard All Changes…", role: .destructive) { store.pendingDiscard = DiscardRequest(files: store.files, includingStaged: true) }.disabled(store.files.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(store.isBusy)
                }.padding(.horizontal, 16).padding(.leading, store.sidebarVisible ? 0 : 84)
                    .frame(height: 52).contentShape(Rectangle()).simultaneousGesture(WindowDragGesture())
                Divider()
                if store.files.isEmpty {
                    ContentUnavailableView {
                        Label(store.hasLoaded ? "All up to date" : "Opening repository", systemImage: store.hasLoaded ? "checkmark.circle" : "folder")
                    } description: {
                        Text(store.hasLoaded ? "Changes you make will appear here." : "Reading your working tree…")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Toggle("All Changes", isOn: Binding(
                                get: { store.checkedFiles.count == store.files.count },
                                set: { store.selection.setAll($0) }
                            )).toggleStyle(.checkbox)
                            Spacer()
                            Text("\(store.checkedFiles.count) of \(store.files.count)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal, 16).padding(.vertical, 10).disabled(store.isBusy || store.isGenerating)
                        List(selection: $store.selectedFileID) {
                            ForEach(store.files) { file in fileRow(file) }
                        }.listStyle(.inset)
                    }
                }
                Divider()
                commitComposer.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 430)
            WorkingDiffView(store: store).frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(store.pendingDiscard?.title ?? "Discard changes?", isPresented: Binding(get: { store.pendingDiscard != nil }, set: { if !$0 { store.pendingDiscard = nil } }), titleVisibility: .visible, presenting: store.pendingDiscard) { request in
            Button("Discard Changes", role: .destructive) { Task { await store.discard(request) } }
            Button("Cancel", role: .cancel) { }
        } message: { request in Text(request.message) }
    }

    private var repositoryActions: some View {
        HStack(spacing: 9) {
            Button { Task { await store.perform("Fetching…") { try await store.git.fetch(); try await store.reload() } } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                .help("Fetch")
            Button { Task { await store.perform("Pulling…") { try await store.git.pull(); try await store.reload() } } } label: { Image(systemName: "arrow.down") }
                .help("Pull")
            Button { Task { await store.perform("Pushing…") { try await store.git.push(); try await store.reload() } } } label: { Image(systemName: "arrow.up") }
                .help("Push")
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh").keyboardShortcut("r")
        }.buttonStyle(.borderless).controlSize(.small).disabled(store.isBusy || store.isGenerating)
    }

    private func fileRow(_ file: GitFile) -> some View {
        HStack(spacing: 8) {
            Toggle("Include \(file.path)", isOn: Binding(
                get: { store.selection.checked.contains(file.path) },
                set: { store.selection.set(file.path, checked: $0) }
            )).labelsHidden().toggleStyle(.checkbox).disabled(store.isBusy || store.isGenerating)
            Image(systemName: file.isConflicted ? "exclamationmark.triangle" : fileMediaSymbol(file.path)).foregroundStyle(file.isConflicted ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                let parent = (file.path as NSString).deletingLastPathComponent
                if preferences.layout.showFilePaths, !parent.isEmpty { Text(parent).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: 2)
            if preferences.layout.showFileStatus || file.isConflicted { Text(file.status).font(.caption2).foregroundStyle(file.isConflicted ? .orange : .secondary) }
        }
        .padding(.vertical, preferences.layout.rowPadding)
        .padding(.horizontal, 4)
        .tag(file.id)
        .contentShape(Rectangle())
        .contextMenu {
            Button(file.isStaged ? "Unstage" : "Stage") { Task { if file.isStaged { await store.unstage(file) } else { await store.stage(file) } } }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.git.url.appendingPathComponent(file.path)]) }
            Divider()
            Button("Discard Changes…", role: .destructive) {
                store.pendingDiscard = DiscardRequest(files: [file], includingStaged: true)
            }.disabled(store.isBusy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "View Changes") { store.selectedFileID = file.id }
    }

    private var commitComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Commit").font(.headline)
                Spacer()
                if store.isGenerating { ProgressView().controlSize(.small) }
                Button { Task { await store.generate(using: preferences) } } label: { Label("Write", systemImage: "sparkles") }
                    .controlSize(.small)
                    .disabled(store.checkedFiles.isEmpty || store.isGenerating || store.isBusy)
                    .help("Write a commit message with \(preferences.provider.name)")
            }
            TextField("Summary", text: $store.summary, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Commit summary")
            TextEditor(text: $store.commitBody)
                .font(.body).frame(height: preferences.layout.commitEditorHeight)
                .scrollContentBackground(.hidden)
                .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if store.commitBody.isEmpty { Text("Description (optional)").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 8).allowsHitTesting(false) }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .accessibilityLabel("Commit description")
            if preferences.provider != .apple {
                Text("Write sends selected changes to \(preferences.provider.name).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(store.checkedFiles.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Commit") { Task { await store.commit() } }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(store.checkedFiles.isEmpty || store.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy || store.isGenerating || store.files.contains(where: \.isConflicted))
            }
        }.padding(16).disabled(store.isBusy || store.isGenerating)
    }
}

struct WorkingDiffView: View {
    let store: RepositoryStore
    @State private var text = ""
    @State private var media: MediaComparison?
    @State private var loading = false
    @State private var error: String?
    private var identity: String { "\(store.selectedFileID ?? "")-\(store.revision)" }
    var body: some View {
        VStack(spacing: 0) {
            if let file = store.selectedFile {
                HStack {
                    Label(file.path, systemImage: fileMediaSymbol(file.path)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(file.status).foregroundStyle(.secondary)
                    Menu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.git.url.appendingPathComponent(file.path)]) }
                        Button("Discard Changes…", role: .destructive) {
                            store.pendingDiscard = DiscardRequest(files: [file], includingStaged: true)
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().disabled(store.isBusy)
                }.font(.callout).padding(.horizontal, 14).frame(height: 52)
                    .contentShape(Rectangle()).simultaneousGesture(WindowDragGesture())
                Divider()
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error { ContentUnavailableView("Unable to Show Changes", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if let media { MediaComparisonView(comparison: media).id(identity) }
                else { DiffView(text: text) }
            } else {
                ContentUnavailableView("Select a File", systemImage: "doc.text.magnifyingglass", description: Text("Review changes before your next commit."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: identity) {
            guard let file = store.selectedFile else { return }
            loading = true
            error = nil
            media = nil
            do {
                let comparison = await store.git.mediaComparison(file: file)
                guard !Task.isCancelled else { return }
                if let comparison {
                    media = comparison
                    loading = false
                    return
                }
                let result = try await store.git.changesDiff(file: file)
                guard !Task.isCancelled else { return }
                text = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}

func fileMediaSymbol(_ path: String) -> String {
    switch MediaKind.detect(path: path) { case .image: "photo"; case .audio: "waveform"; case nil: "doc.text" }
}
