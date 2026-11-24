import SwiftUI

enum RepositorySection: String, CaseIterable, Identifiable {
    case changes = "Changes", history = "History", branches = "Branches"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .changes: "square.and.pencil"; case .history: "clock"; case .branches: "arrow.triangle.branch" }
    }
}

@MainActor @Observable
final class RepositoryStore {
    let git: GitRepository
    var snapshot: RepositorySnapshot?
    var sidebarVisible = true
    var section: RepositorySection = .changes
    var isBusy = false
    var error: String?
    var activity = ""
    var selectedCommitID: String?
    var selectedFileID: String?
    var summary = "" { didSet { saveDraft() } }
    var commitBody = "" { didSet { saveDraft() } }
    var search = ""
    var isGenerating = false
    var showNewBranch = false
    var hasLoaded = false
    var revision = 0
    var pendingDiscard: DiscardRequest?
    var selection = ChangeSelection()
    var pendingBranch: GitBranch?
    var notice: String?

    init(url: URL) {
        git = GitRepository(url: url)
        let draft = UserDefaults.standard.dictionary(forKey: "commitDraft-" + url.path) as? [String: String]
        summary = draft?["summary"] ?? ""
        commitBody = draft?["body"] ?? ""
    }
    private func saveDraft() {
        UserDefaults.standard.set(["summary": summary, "body": commitBody], forKey: "commitDraft-" + git.url.path)
    }
    var files: [GitFile] { snapshot?.files ?? [] }
    var staged: [GitFile] { files.filter(\.isStaged) }
    var unstaged: [GitFile] { files.filter(\.hasUnstagedChanges) }
    var selectedFile: GitFile? { files.first { $0.id == selectedFileID } }
    var checkedFiles: [GitFile] { files.filter { selection.checked.contains($0.path) } }
    var selectedCommit: GitCommit? { snapshot?.commits.first { $0.id == selectedCommitID } }
    var commits: [GitCommit] {
        (snapshot?.commits ?? []).filter { search.isEmpty || "\($0.subject) \($0.author) \($0.id) \($0.body)".localizedCaseInsensitiveContains(search) }
    }

    func reload() async throws {
        snapshot = try await git.load()
        revision += 1
        selection.reconcile(paths: files.map(\.path))
        hasLoaded = true
        if selectedFileID == nil || !files.contains(where: { $0.id == selectedFileID }) { selectedFileID = files.first?.id }
        if selectedCommitID == nil { selectedCommitID = snapshot?.commits.first?.id }
    }

    func refresh() async {
        guard !isBusy else { return }
        await perform("Refreshing…") { try await self.reload() }
    }

    func perform(_ label: String, operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        activity = label
        defer { isBusy = false; activity = "" }
        do { try await operation() }
        catch { self.error = error.localizedDescription }
    }

    func stage(_ file: GitFile) async {
        await perform("Staging…") { try await self.git.stage(file); try await self.reload() }
    }
    func unstage(_ file: GitFile) async {
        await perform("Unstaging…") { try await self.git.unstage(file); try await self.reload() }
    }
    func stageAll() async {
        await perform("Staging…") { _ = try await self.git.run(["add", "--all"]); try await self.reload() }
    }
    func unstageAll() async {
        await perform("Unstaging…") {
            for file in self.staged { try await self.git.unstage(file) }
            try await self.reload()
        }
    }
    func commit() async {
        guard !checkedFiles.isEmpty else { return }
        await perform("Committing…") {
            do { try await self.git.commit(files: self.checkedFiles, summary: self.summary, body: self.commitBody) }
            catch { try? await self.reload(); throw error }
            self.summary = ""
            self.commitBody = ""
            try await self.reload()
        }
    }
    func discard(_ request: DiscardRequest) async {
        await perform("Discarding changes…") {
            for file in request.files { try await self.git.discard(file, includingStaged: request.includingStaged) }
            try await self.reload()
        }
    }
    func switchBranch(_ branch: GitBranch) async {
        guard !isGenerating, !branch.remote, !branch.current else { return }
        await perform("Switching branch…") {
            do { try await self.git.switchBranch(branch.name) }
            catch {
                if !self.files.isEmpty && (error.localizedDescription.contains("would be overwritten") || error.localizedDescription.contains("Please commit") || error.localizedDescription.contains("Please move or remove")) {
                    self.pendingBranch = branch
                    return
                }
                throw error
            }
            self.selectedCommitID = nil
            try await self.reload()
        }
    }
    func bringChanges(to branch: GitBranch) async {
        await perform("Bringing changes…") {
            do { self.notice = try await self.git.bringChanges(to: branch.name) }
            catch { try? await self.reload(); throw error }
            self.selectedCommitID = nil
            try await self.reload()
        }
    }
    func generate(using preferences: Preferences) async {
        guard !isGenerating, !isBusy else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let diff = try await git.selectedDiff(files: checkedFiles)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitFailure("Choose changes before writing a commit message.") }
            let result = try await CommitWriter.generate(diff: diff, provider: preferences.provider, model: preferences.model, instruction: preferences.instruction)
            summary = result.summary
            commitBody = result.body
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscardRequest {
    let files: [GitFile]
    let includingStaged: Bool
    var title: String { files.count == 1 ? "Discard changes to \((files[0].path as NSString).lastPathComponent)?" : "Discard all changes?" }
    var message: String {
        (includingStaged ? "Staged and unstaged changes will be discarded." : "Unstaged changes will be discarded. Staged changes will be kept.") + " New files will be moved to Trash. Changes to tracked files cannot be undone."
    }
}
