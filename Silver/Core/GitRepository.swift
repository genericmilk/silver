import Foundation

public struct GitRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func run(_ arguments: [String]) async throws -> String {
        try await GitRunner.run(arguments, at: url)
    }

    public func root() async throws -> URL {
        let path = try await run(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public func load() async throws -> RepositorySnapshot {
        let root = try await root()
        let branch: String
        do { branch = try await run(["symbolic-ref", "--quiet", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { branch = "Detached HEAD" }
        return try await snapshot(root: root, branch: branch)
    }

    private func snapshot(root: URL, branch: String) async throws -> RepositorySnapshot {
        let status = try await run(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        let branches = try await run(["for-each-ref", "--sort=-committerdate", "--format=%(refname:short)%09%(HEAD)%09%(refname)%09%(upstream:short)", "refs/heads", "refs/remotes"])
        let hasHead = (try? await run(["rev-parse", "--verify", "HEAD"])) != nil
        let history = hasHead ? try await run(["log", "-n", "500", "-z", "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00%b%x00%D"]) : ""
        let tracking = (try? await run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])) ?? "0\t0"
        let counts = tracking.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }
        return RepositorySnapshot(root: root, branch: branch, commits: GitParser.history(history), branches: GitParser.branches(branches), files: GitParser.status(status), ahead: counts.first ?? 0, behind: counts.last ?? 0)
    }

    public func stage(_ file: GitFile) async throws {
        var paths = [file.path]
        if let original = file.originalPath, file.indexStatus != "R" { paths.append(original) }
        _ = try await run(["--literal-pathspecs", "add", "--"] + paths)
    }

    public func unstage(_ file: GitFile) async throws {
        var paths = [file.path]
        if let original = file.originalPath { paths.append(original) }
        if (try? await run(["rev-parse", "--verify", "HEAD"])) != nil {
            _ = try await run(["--literal-pathspecs", "restore", "--staged", "--"] + paths)
        } else {
            _ = try await run(["--literal-pathspecs", "rm", "--cached", "--"] + paths)
        }
    }

    public func commit(summary: String, body: String) async throws {
        let title = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw GitFailure("Write a commit summary first.") }
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await run(["commit", "-m", message.isEmpty ? title : title + "\n\n" + message])
    }

    public func commit(files: [GitFile], summary: String, body: String) async throws {
        let title = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw GitFailure("Write a commit summary first.") }
        guard !files.isEmpty else { throw GitFailure("Choose at least one file to commit.") }
        let paths = Array(Set(files.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) })).sorted()
        for file in files { try await stage(file) }
        let description = body.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await run(["--literal-pathspecs", "commit", "--only", "-m", description.isEmpty ? title : title + "\n\n" + description, "--"] + paths)
    }

    public func changesDiff(file: GitFile, context: Int = 20) async throws -> String {
        if file.isUntracked { return try await diff(file: file, staged: false) }
        if (try? await run(["rev-parse", "--verify", "HEAD"])) == nil {
            if file.worktreeStatus == "D" { return "" }
            return try await newFileDiff(path: file.path)
        }
        let paths = [file.path] + (file.originalPath.map { [$0] } ?? [])
        return try await run(["--literal-pathspecs", "diff", "HEAD", "--no-ext-diff", "--no-textconv", "--unified=\(context)", "--"] + paths)
    }

    public func selectedDiff(files: [GitFile]) async throws -> String {
        var output = ""
        for file in files {
            let patch = try await changesDiff(file: file, context: 3)
            output += patch + "\n"
            if output.count > 40_000 { break }
        }
        return output
    }

    public func diff(file: GitFile, staged: Bool) async throws -> String {
        if file.isUntracked {
            return try await newFileDiff(path: file.path)
        }
        return try await run(["--literal-pathspecs", "diff", "--no-ext-diff", "--no-textconv", "--unified=20"] + (staged ? ["--cached"] : []) + ["--", file.path])
    }

    private func newFileDiff(path: String) async throws -> String {
            let fileURL = url.appendingPathComponent(path)
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { return "Symbolic link → " + (try FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)) }
            guard (values.fileSize ?? 0) <= 1_000_000 else { return "This file is too large to preview." }
            let data = try Data(contentsOf: fileURL)
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return "Binary file" }
            var lines = text.components(separatedBy: "\n")
            if text.hasSuffix("\n") { lines.removeLast() }
            if text.isEmpty { lines = [] }
            return "diff --git a/\(path) b/\(path)\n--- /dev/null\n+++ b/\(path)\n@@ -0,0 +1,\(lines.count) @@\n" + lines.map { "+" + $0 }.joined(separator: "\n") + (text.hasSuffix("\n") || text.isEmpty ? "\n" : "\n\\ No newline at end of file\n")
    }

    public func stagedDiff() async throws -> String {
        try await run(["diff", "--cached", "--no-ext-diff", "--no-textconv", "--unified=3"])
    }

    public func files(in commit: GitCommit) async throws -> [CommitFile] {
        GitParser.commitFiles(try await run(["diff-tree", "--root", "--first-parent", "-m", "-M", "--no-commit-id", "--name-status", "-r", "-z", commit.id]))
    }

    public func diff(commit: GitCommit, path: String? = nil) async throws -> String {
        var args = ["--literal-pathspecs", "show", "--format=", "--first-parent", "--no-ext-diff", "--no-textconv", "--unified=20", commit.id]
        if let path { args += ["--", path] }
        return try await run(args)
    }

    public func switchBranch(_ name: String) async throws { _ = try await run(["switch", "--", name]) }

    public func bringChanges(to branch: String) async throws -> String? {
        guard !(try await load().files).isEmpty else { try await switchBranch(branch); return nil }
        _ = try await run(["stash", "push", "--include-untracked", "-m", "Silver: bring changes to \(branch)"])
        let stash = try await run(["rev-parse", "refs/stash"]).trimmingCharacters(in: .whitespacesAndNewlines)
        do { try await switchBranch(branch) }
        catch {
            let switchError = error.localizedDescription
            do { _ = try await run(["stash", "apply", "--index", stash]) }
            catch { throw GitFailure("The branch could not be switched. Your work is preserved in stash \(stash). \(switchError)\n\(error.localizedDescription)") }
            try await dropStash(stash)
            throw GitFailure(switchError)
        }
        do {
            _ = try await run(["stash", "apply", "--index", stash])
        } catch {
            let status = try await load()
            if status.files.isEmpty {
                do { _ = try await run(["stash", "apply", stash]) }
                catch { return "Switched to \(branch). Some changes need resolving. Your original work is preserved in stash \(stash).\n\n\(error.localizedDescription)" }
            } else {
                return "Switched to \(branch). Some changes need resolving. Your original work is preserved in stash \(stash).\n\n\(error.localizedDescription)"
            }
        }
        try await dropStash(stash)
        return nil
    }

    private func dropStash(_ hash: String) async throws {
        let list = try await run(["stash", "list", "--format=%H%x09%gd"])
        if let entry = list.split(separator: "\n").first(where: { $0.hasPrefix(hash + "\t") }), let ref = entry.split(separator: "\t").last {
            _ = try await run(["stash", "drop", String(ref)])
        }
    }

    /// Unstaged discard restores the index version. All-changes discard restores HEAD.
    /// New files go to the system Trash instead of being permanently deleted.
    @discardableResult
    public func discard(_ file: GitFile, includingStaged: Bool) async throws -> URL? {
        let fileURL = url.appendingPathComponent(file.path)
        var trashedURL: NSURL?
        if file.isUntracked {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
            return trashedURL as URL?
        }
        if !includingStaged && !file.isConflicted {
            _ = try await run(["--literal-pathspecs", "restore", "--worktree", "--", file.path])
            return nil
        }
        let hasHead = (try? await run(["rev-parse", "--verify", "HEAD"])) != nil
        var paths = [file.path]
        if let original = file.originalPath { paths.append(original) }
        let trackedInHead = hasHead ? try await run(["--literal-pathspecs", "ls-tree", "-z", "--name-only", "HEAD", "--"] + paths) : ""
        if !trackedInHead.isEmpty {
            _ = try await run(["--literal-pathspecs", "restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths)
        } else {
            if FileManager.default.fileExists(atPath: fileURL.path) || (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
            }
            _ = try await run(["--literal-pathspecs", "rm", "--cached", "--force", "--"] + paths)
        }
        return trashedURL as URL?
    }
    public func createBranch(_ name: String) async throws {
        guard !name.isEmpty, !name.hasPrefix("-") else { throw GitFailure("Enter a valid branch name.") }
        _ = try await run(["check-ref-format", "--branch", name])
        _ = try await run(["switch", "-c", name])
    }
    public func fetch() async throws { _ = try await run(["fetch", "--all", "--prune"]) }
    public func pull() async throws { _ = try await run(["pull", "--ff-only"]) }
    public func push() async throws { _ = try await run(["push"]) }

    public static func clone(remote: String, to destination: URL) async throws {
        guard !remote.hasPrefix("-"), !remote.isEmpty else { throw GitFailure("Enter a repository URL.") }
        _ = try await GitRunner.run(["clone", "--", remote, destination.path])
    }

    public static func initialize(at url: URL) async throws {
        _ = try await GitRunner.run(["init", "-b", "main", "--", url.path])
    }
}
