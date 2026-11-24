import Foundation
import Testing
@testable import SilverCore

private struct Fixture {
    let url: URL
    let git: GitRepository
    static func make() async throws -> Fixture {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Silver Tests \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try await GitRepository.initialize(at: url)
        let git = GitRepository(url: url)
        _ = try await git.run(["config", "user.name", "Silver Tests"])
        _ = try await git.run(["config", "user.email", "tests@silver.local"])
        _ = try await git.run(["config", "commit.gpgsign", "false"])
        _ = try await git.run(["config", "core.hooksPath", "/dev/null"])
        return Fixture(url: url, git: git)
    }
    func write(_ path: String, _ text: String) throws {
        try text.write(to: url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    func clean() { try? FileManager.default.removeItem(at: url) }
}

@Test func parseRenamesAndConflicts() {
    let files = GitParser.status("R  renamed file.swift\0old file.swift\0 M ünicode.txt\0?? new\nfile.txt\0UU conflict.txt\0")
    #expect(files.count == 4)
    #expect(files[0].path == "renamed file.swift")
    #expect(files[0].originalPath == "old file.swift")
    #expect(files[0].isStaged)
    #expect(files[1].hasUnstagedChanges)
    #expect(files[2].path == "new\nfile.txt")
    #expect(files[2].isUntracked)
    #expect(files[3].isConflicted)
}

@Test func initialCommitAndLiteralFilenames() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    var snapshot = try await f.git.load()
    #expect(snapshot.branch == "main")
    #expect(snapshot.commits.isEmpty)
    try f.write("[a]* notes.txt", "Hello\n")
    try f.write("another.txt", "Not staged\n")
    snapshot = try await f.git.load()
    let file = try #require(snapshot.files.first { $0.path == "[a]* notes.txt" })
    #expect(try await f.git.diff(file: file, staged: false).contains("+Hello"))
    try await f.git.stage(file)
    snapshot = try await f.git.load()
    #expect(snapshot.files.filter(\.isStaged).count == 1)
    try await f.git.unstage(try #require(snapshot.files.first { $0.isStaged }))
    #expect(try await f.git.load().files.allSatisfy { !$0.isStaged })
    try await f.git.stage(file)
    try await f.git.commit(summary: "Add initial notes", body: "Keep literal filenames intact.\n\nA second paragraph.")
    snapshot = try await f.git.load()
    let commit = try #require(snapshot.commits.first)
    #expect(commit.subject == "Add initial notes")
    #expect(commit.body == "Keep literal filenames intact.\n\nA second paragraph.")
    #expect(commit.parents.isEmpty)
    #expect(commit.author == "Silver Tests")
    #expect(snapshot.files.count == 1)
    let files = try await f.git.files(in: commit)
    #expect(files.map(\.path) == ["[a]* notes.txt"])
    #expect(try await f.git.diff(commit: commit).contains("+Hello"))
}

@Test func stagedAndWorkingChangesRemainSeparate() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("notes.txt", "one\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "First", body: "")
    try f.write("notes.txt", "two\n")
    let file = try #require(try await f.git.load().files.first)
    try await f.git.stage(file)
    try f.write("notes.txt", "three\n")
    let changed = try #require(try await f.git.load().files.first)
    #expect(changed.isStaged && changed.hasUnstagedChanges)
    #expect(try await f.git.diff(file: changed, staged: true).contains("+two"))
    #expect(try await f.git.diff(file: changed, staged: false).contains("+three"))
    try await f.git.commit(summary: "Second", body: "")
    let snapshot = try await f.git.load()
    #expect(snapshot.commits.map(\.subject) == ["Second", "First"])
    #expect(snapshot.files.first?.isStaged == false)
    #expect(snapshot.files.first?.hasUnstagedChanges == true)
    #expect(try String(contentsOf: f.url.appendingPathComponent("notes.txt"), encoding: .utf8) == "three\n")
}

@Test func branchesAndDetachedHead() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("file.txt", "initial")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try await f.git.createBranch("feature/native-ui")
    #expect(try await f.git.load().branch == "feature/native-ui")
    try await f.git.switchBranch("main")
    let snapshot = try await f.git.load()
    #expect(snapshot.branches.count == 2)
    #expect(snapshot.branches.first { $0.current }?.name == "main")
    _ = try await f.git.run(["switch", "--detach", "HEAD"])
    #expect(try await f.git.load().branch == "Detached HEAD")
    await #expect(throws: (any Error).self) { try await f.git.createBranch("invalid branch") }
    await #expect(throws: (any Error).self) { try await f.git.createBranch("--orphan") }
}

@Test func renameAndBinaryPreview() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("before.txt", "unchanged content")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    _ = try await f.git.run(["mv", "before.txt", "after.txt"])
    let file = try #require(try await f.git.load().files.first)
    #expect(file.originalPath == "before.txt")
    try await f.git.unstage(file)
    #expect(try await f.git.load().files.allSatisfy { !$0.isStaged })
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Rename", body: "")
    let commit = try #require(try await f.git.load().commits.first)
    #expect(try await f.git.files(in: commit).map(\.path) == ["after.txt"])
    try Data([0, 1, 2, 3]).write(to: f.url.appendingPathComponent("image.bin"))
    let binary = try #require(try await f.git.load().files.first)
    #expect(try await f.git.diff(file: binary, staged: false) == "Binary file")
}

@Test func cloneAndRemoteOperations() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("file.txt", "initial")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    let remote = f.url.deletingLastPathComponent().appendingPathComponent("Silver Remote \(UUID().uuidString).git")
    let clone = f.url.deletingLastPathComponent().appendingPathComponent("Silver Clone \(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: remote); try? FileManager.default.removeItem(at: clone) }
    _ = try await GitRunner.run(["clone", "--bare", "--", f.url.path, remote.path])
    try await GitRepository.clone(remote: remote.path, to: clone)
    let cloned = GitRepository(url: clone)
    #expect(try await cloned.load().commits.first?.subject == "Initial")
    try await cloned.fetch()
    try await cloned.pull()
    _ = try await f.git.run(["remote", "add", "origin", remote.path])
    _ = try await f.git.run(["push", "-u", "origin", "main"])
    try f.write("file.txt", "updated")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Update", body: "")
    try await f.git.push()
    try await cloned.fetch()
    #expect(try await cloned.load().behind == 1)
    try await cloned.pull()
    #expect(try await cloned.load().commits.first?.subject == "Update")
    await #expect(throws: (any Error).self) { try await GitRepository.clone(remote: "--help", to: clone) }
}

@Test func foldsOnlyUnchangedLines() {
    let context = (1...30).map { " line \($0)" }.joined(separator: "\n")
    let text = "diff --git a/file b/file\n@@ -1,31 +1,31 @@\n\(context)\n-old\n+new\n"
    let document = DiffDocument(text: text)
    let fold = document.blocks.first { $0.isFoldable }
    #expect(fold?.hiddenLineCount == 24)
    #expect(fold?.contextLines == 3)
    #expect(document.blocks.filter { $0.isFoldable }.allSatisfy { $0.lines.allSatisfy { $0.hasPrefix(" ") } })
    #expect(document.blocks.filter { !$0.isFoldable }.flatMap(\.lines).contains("+new"))
    #expect(DiffDocument(text: text, contextLines: 0).blocks.first { $0.isFoldable }?.hiddenLineCount == 30)
    #expect(DiffDocument(text: String(repeating: "+new\n", count: 100)).blocks.allSatisfy { !$0.isFoldable })
    #expect(DiffDocument(text: text, limit: 20).truncated)
}

@Test func discardUnstagedPreservesIndexAndDiscardAllRestoresHead() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("[x] notes.txt", "original\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try f.write("[x] notes.txt", "staged\n")
    try await f.git.stage(try #require(try await f.git.load().files.first))
    try f.write("[x] notes.txt", "unstaged\n")
    var file = try #require(try await f.git.load().files.first)
    try await f.git.discard(file, includingStaged: false)
    #expect(try String(contentsOf: f.url.appendingPathComponent(file.path), encoding: .utf8) == "staged\n")
    file = try #require(try await f.git.load().files.first)
    #expect(file.isStaged && !file.hasUnstagedChanges)
    try await f.git.discard(file, includingStaged: true)
    #expect(try String(contentsOf: f.url.appendingPathComponent(file.path), encoding: .utf8) == "original\n")
    #expect(try await f.git.load().files.isEmpty)
    _ = try await f.git.run(["mv", "[x] notes.txt", "renamed.txt"])
    try await f.git.discard(try #require(try await f.git.load().files.first), includingStaged: true)
    #expect(try await f.git.load().files.isEmpty)
    #expect(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("[x] notes.txt").path))
    #expect(!FileManager.default.fileExists(atPath: f.url.appendingPathComponent("renamed.txt").path))
}

@Test func discardNewFilesMovesTheirContentsToTrash() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("Silver-discard-\(UUID().uuidString).txt", "preserve this")
    let first = try #require(try await f.git.load().files.first)
    let firstTrash = try #require(try await f.git.discard(first, includingStaged: false))
    defer { try? FileManager.default.removeItem(at: firstTrash) }
    #expect(try String(contentsOf: firstTrash, encoding: .utf8) == "preserve this")
    #expect(try await f.git.load().files.isEmpty)
    try f.write("Silver-staged-discard-\(UUID().uuidString).txt", "staged new file")
    try await f.git.stage(try #require(try await f.git.load().files.first))
    let staged = try #require(try await f.git.load().files.first)
    let stagedTrash = try #require(try await f.git.discard(staged, includingStaged: true))
    defer { try? FileManager.default.removeItem(at: stagedTrash) }
    #expect(try String(contentsOf: stagedTrash, encoding: .utf8) == "staged new file")
    #expect(try await f.git.load().files.isEmpty)
}

@Test func mergeCommitDiffUsesFirstParent() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("main.txt", "initial")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try await f.git.createBranch("feature")
    try f.write("feature.txt", "feature")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Feature", body: "")
    try await f.git.switchBranch("main")
    _ = try await f.git.run(["merge", "--no-ff", "feature", "-m", "Merge feature"])
    let commit = try #require(try await f.git.load().commits.first)
    #expect(commit.parents.count == 2)
    #expect(try await f.git.files(in: commit).map(\.path) == ["feature.txt"])
    #expect(try await f.git.diff(commit: commit).contains("+feature"))
}

@Test func diffLineNumbersAndSideBySideAlignment() {
    let patch = "diff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -10,4 +20,5 @@\n same\n-old one\n-old two\n+new one\n+new two\n+new three\n tail\n\\ No newline at end of file\n"
    let inline = DiffLayout(text: patch, sideBySide: false)
    let deleted = inline.rows.compactMap(\.left).filter { $0.kind == .deletion }
    let added = inline.rows.compactMap(\.left).filter { $0.kind == .addition }
    #expect(deleted.map(\.oldNumber) == [11, 12])
    #expect(deleted.allSatisfy { $0.newNumber == nil })
    #expect(added.map(\.newNumber) == [21, 22, 23])
    #expect(added.allSatisfy { $0.oldNumber == nil })
    let split = DiffLayout(text: patch, sideBySide: true)
    let pairs = split.rows.filter { $0.left?.kind == .deletion || $0.right?.kind == .addition }
    #expect(pairs.count == 3)
    #expect(pairs[0].left?.content == "old one")
    #expect(pairs[0].right?.content == "new one")
    #expect(pairs[2].left == nil)
    #expect(pairs[2].right?.newNumber == 23)
    let tail = split.rows.first { $0.left?.content == "tail" }
    #expect(tail?.left?.oldNumber == 13 && tail?.right?.newNumber == 24)
    let twoFiles = DiffLayout(text: patch + "diff --git a/next b/next\n--- /dev/null\n+++ b/next\n@@ -0,0 +1,1 @@\n++++ code\n", sideBySide: false)
    #expect(twoFiles.rows.compactMap(\.left).last { $0.kind == .addition }?.newNumber == 1)
    #expect(twoFiles.rows.compactMap(\.left).last { $0.kind == .addition }?.content == "+++ code")
}

@Test func changeSelectionDefaultsAndRefresh() {
    var selection = ChangeSelection()
    selection.reconcile(paths: ["a", "b"])
    #expect(selection.checked == ["a", "b"])
    selection.set("b", checked: false)
    selection.reconcile(paths: ["a", "b", "c"])
    #expect(selection.checked == ["a", "c"])
    selection.setAll(false)
    selection.reconcile(paths: ["a", "b", "c"])
    #expect(selection.checked.isEmpty)
    selection.setAll(true)
    selection.reconcile(paths: ["b"])
    #expect(selection.checked == ["b"])
}

@Test func selectedCommitPreservesExcludedStagedAndUnstagedWork() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("included.txt", "original")
    try f.write("excluded.txt", "original")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try f.write("included.txt", "selected change")
    try f.write("excluded.txt", "staged excluded")
    let excluded = try #require(try await f.git.load().files.first { $0.path == "excluded.txt" })
    try await f.git.stage(excluded)
    try f.write("excluded.txt", "unstaged excluded")
    try f.write("[new]*.txt", "selected new file\n")
    let snapshot = try await f.git.load()
    let selected = snapshot.files.filter { $0.path != "excluded.txt" }
    let indexBefore = try await f.git.run(["show", ":excluded.txt"])
    try await f.git.commit(files: selected, summary: "Selected files", body: "Only the checked files.")
    let result = try await f.git.load()
    #expect(result.files.map(\.path) == ["excluded.txt"])
    #expect(result.files[0].isStaged && result.files[0].hasUnstagedChanges)
    #expect(try await f.git.run(["show", ":excluded.txt"]) == indexBefore)
    #expect(try await f.git.run(["show", "HEAD:excluded.txt"]) == "original")
    #expect(try String(contentsOf: f.url.appendingPathComponent("excluded.txt"), encoding: .utf8) == "unstaged excluded")
    let commit = try #require(result.commits.first)
    #expect(Set(try await f.git.files(in: commit).map(\.path)) == ["included.txt", "[new]*.txt"])
}

@Test func selectedInitialCommitAndRename() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("first.txt", "first\n")
    try f.write("leave.txt", "leave\n")
    let first = try #require(try await f.git.load().files.first { $0.path == "first.txt" })
    let preview = try await f.git.selectedDiff(files: [first])
    #expect(preview.contains("+first") && !preview.contains("leave.txt"))
    let numbered = DiffLayout(text: preview, sideBySide: false).rows.compactMap(\.left).filter { $0.kind == .addition }
    #expect(numbered.first?.newNumber == 1)
    try await f.git.commit(files: [first], summary: "First file", body: "")
    #expect(try await f.git.load().files.map(\.path) == ["leave.txt"])
    _ = try await f.git.run(["mv", "first.txt", "renamed.txt"])
    let rename = try #require(try await f.git.load().files.first { $0.path == "renamed.txt" })
    try await f.git.commit(files: [rename], summary: "Rename first", body: "")
    #expect(try await f.git.load().files.map(\.path) == ["leave.txt"])
    #expect(try await f.git.run(["ls-tree", "--name-only", "HEAD"]).contains("renamed.txt"))
}

@Test func bringChangesPreservesContentAndExistingStash() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("file.txt", "original\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try await f.git.createBranch("destination")
    try f.write("destination.txt", "destination")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Destination", body: "")
    try await f.git.switchBranch("main")
    try f.write("file.txt", "old stash\n")
    _ = try await f.git.run(["stash", "push", "-m", "Existing stash"])
    let existing = try await f.git.run(["rev-parse", "refs/stash"])
    try f.write("file.txt", "carry this\n")
    try await f.git.stage(try #require(try await f.git.load().files.first))
    try f.write("untracked.txt", "carry new file")
    #expect(try await f.git.bringChanges(to: "destination") == nil)
    let result = try await f.git.load()
    #expect(result.branch == "destination")
    #expect(result.files.first { $0.path == "file.txt" }?.isStaged == true)
    #expect(result.files.first { $0.path == "untracked.txt" }?.isUntracked == true)
    #expect(try String(contentsOf: f.url.appendingPathComponent("file.txt"), encoding: .utf8) == "carry this\n")
    #expect(try await f.git.run(["rev-parse", "refs/stash"]) == existing)
}

@Test func bringConflictingChangesKeepsBackup() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("file.txt", "original\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try await f.git.createBranch("destination")
    try f.write("file.txt", "destination\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Destination", body: "")
    try await f.git.switchBranch("main")
    try f.write("file.txt", "local work\n")
    await #expect(throws: (any Error).self) { try await f.git.switchBranch("destination") }
    let notice = try await f.git.bringChanges(to: "destination")
    #expect(notice?.contains("preserved in stash") == true)
    let snapshot = try await f.git.load()
    #expect(snapshot.branch == "destination")
    #expect(snapshot.files.contains { $0.isConflicted })
    #expect(try await f.git.run(["stash", "show", "-p"]).contains("+local work"))
    let content = try String(contentsOf: f.url.appendingPathComponent("file.txt"), encoding: .utf8)
    #expect(content.contains("local work") && content.contains("destination"))
}

@Test func failedBranchCarryRestoresOriginalWork() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    try f.write("file.txt", "original\n")
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Initial", body: "")
    try f.write("file.txt", "keep this\n")
    try await f.git.stage(try #require(try await f.git.load().files.first))
    try f.write("new.txt", "new content")
    await #expect(throws: (any Error).self) { try await f.git.bringChanges(to: "missing-branch") }
    let snapshot = try await f.git.load()
    #expect(snapshot.branch == "main")
    #expect(snapshot.files.first { $0.path == "file.txt" }?.isStaged == true)
    #expect(snapshot.files.first { $0.path == "new.txt" }?.isUntracked == true)
    #expect(try String(contentsOf: f.url.appendingPathComponent("file.txt"), encoding: .utf8) == "keep this\n")
}

@Test func diffPresentationHidesGitHeadersAndSeparatesSections() {
    let patch = "diff --git a/first.swift b/first.swift\nindex abc..def 100644\n--- a/first.swift\n+++ b/first.swift\n@@ -1,2 +1,2 @@\n-old\n+new\n context\n@@ -30,1 +30,1 @@\n-last\n+latest\ndiff --git a/second.txt b/second.txt\nnew file mode 100644\n--- /dev/null\n+++ b/second.txt\n@@ -0,0 +1,1 @@\n+second file\n"
    for split in [false, true] {
        let presentation = DiffLayout(text: patch, sideBySide: split).displayRows
        let text = presentation.flatMap { [$0.left?.text, $0.right?.text].compactMap { $0 } }
        #expect(!text.contains { $0.hasPrefix("diff --git") || $0.hasPrefix("@@") || $0.hasPrefix("index ") || $0.hasPrefix("--- ") || $0.hasPrefix("+++ ") })
        #expect(presentation.compactMap(\.left).filter { $0.kind == .file }.map(\.text) == ["first.swift", "second.txt"])
        #expect(presentation.filter { $0.left?.kind == .hunk }.count == 1)
        #expect(presentation.contains { $0.left?.content == "new" || $0.right?.content == "new" })
    }
}

private func mediaFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func mediaKindsAndNativeImageDecoding() throws {
    #expect(MediaKind.detect(path: "PHOTO.PNG") == .image)
    #expect(MediaKind.detect(path: "song.mp3") == .audio)
    #expect(MediaKind.detect(path: "song.wav") == .audio)
    #expect(MediaKind.detect(path: "song.m4a") == .audio)
    #expect(MediaKind.detect(path: "code.swift") == nil)
    let before = try MediaImageDecoder.decode(mediaFixture("before.png"))
    let after = try MediaImageDecoder.decode(mediaFixture("after.png"))
    #expect(before.width == 32 && before.height == 24)
    #expect(after.width == 48 && after.height == 24)
    #expect(before.image.width == 32 && after.image.width == 48)
    #expect(throws: (any Error).self) { try MediaImageDecoder.decode(Data("not an image".utf8)) }
}

@Test func mediaPreviewPreservesBinaryDataAndUsesWorkingVersion() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    let before = try mediaFixture("before.png")
    let after = try mediaFixture("after.png")
    let path = "picture [1]*.png"
    try before.write(to: f.url.appendingPathComponent(path))
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Add image", body: "")
    try after.write(to: f.url.appendingPathComponent(path))
    let file = try #require(try await f.git.load().files.first)
    let comparison = try #require(await f.git.mediaComparison(file: file))
    #expect(comparison.kind == .image)
    #expect(comparison.before.data == before)
    #expect(comparison.after.data == after)
    #expect(try await GitRunner.runData(["show", "HEAD:" + path], at: f.url) == before)
    await #expect(throws: (any Error).self) { try await GitRunner.runData(["show", "HEAD:" + path], at: f.url, maximumBytes: 10) }
    try await f.git.stage(file)
    try before.write(to: f.url.appendingPathComponent(path))
    let changed = try #require(try await f.git.load().files.first)
    let working = try #require(await f.git.mediaComparison(file: changed))
    #expect(working.after.data == before)
    #expect(try await GitRunner.runData(["show", ":" + path], at: f.url) == after)
}

@Test func mediaPreviewHandlesAdditionsDeletionsAndRootCommits() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    let data = try mediaFixture("before.png")
    let url = f.url.appendingPathComponent("new.png")
    try data.write(to: url)
    let new = try #require(try await f.git.load().files.first)
    let untracked = try #require(await f.git.mediaComparison(file: new))
    if case .absent = untracked.before {} else { Issue.record("New files have no old version") }
    #expect(untracked.after.data == data)
    try await f.git.commit(files: [new], summary: "Add image", body: "")
    let initial = try #require(try await f.git.load().commits.first)
    let added = try #require(try await f.git.files(in: initial).first)
    let root = try #require(await f.git.mediaComparison(commit: initial, file: added))
    if case .absent = root.before {} else { Issue.record("Root commits have no old version") }
    #expect(root.after.data == data)
    try FileManager.default.removeItem(at: url)
    let removed = try #require(try await f.git.load().files.first)
    let deleted = try #require(await f.git.mediaComparison(file: removed))
    #expect(deleted.before.data == data)
    if case .absent = deleted.after {} else { Issue.record("Deleted files have no working version") }
    try await f.git.commit(files: [removed], summary: "Remove image", body: "")
    let deletion = try #require(try await f.git.load().commits.first)
    let deletedFile = try #require(try await f.git.files(in: deletion).first)
    let history = try #require(await f.git.mediaComparison(commit: deletion, file: deletedFile))
    #expect(history.before.data == data)
    if case .absent = history.after {} else { Issue.record("Deletion commits have no new version") }
}

@Test func renamedMediaUsesOriginalPathInWorkingTreeAndHistory() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    let data = try mediaFixture("before.wav")
    try data.write(to: f.url.appendingPathComponent("old sound.wav"))
    _ = try await f.git.run(["add", "--all"])
    try await f.git.commit(summary: "Add sound", body: "")
    _ = try await f.git.run(["mv", "old sound.wav", "new sound.wav"])
    let file = try #require(try await f.git.load().files.first)
    let working = try #require(await f.git.mediaComparison(file: file))
    #expect(working.kind == .audio)
    #expect(working.before.data == data && working.after.data == data)
    try await f.git.commit(files: [file], summary: "Rename sound", body: "")
    let commit = try #require(try await f.git.load().commits.first)
    let renamed = try #require(try await f.git.files(in: commit).first)
    #expect(renamed.originalPath == "old sound.wav")
    let history = try #require(await f.git.mediaComparison(commit: commit, file: renamed))
    #expect(history.before.data == data && history.after.data == data)
}

@Test func mediaPreviewAvoidsSymlinksAndOversizedFiles() async throws {
    let f = try await Fixture.make()
    defer { f.clean() }
    let source = try #require(Bundle.module.url(forResource: "before.png", withExtension: nil, subdirectory: "Fixtures"))
    try FileManager.default.createSymbolicLink(at: f.url.appendingPathComponent("link.png"), withDestinationURL: source)
    let link = try #require(try await f.git.load().files.first)
    let linked = try #require(await f.git.mediaComparison(file: link))
    if case .unavailable = linked.after {} else { Issue.record("Media previews must not follow symbolic links") }
    let large = f.url.appendingPathComponent("large.wav")
    FileManager.default.createFile(atPath: large.path, contents: nil)
    let handle = try FileHandle(forWritingTo: large)
    try handle.truncate(atOffset: UInt64(GitRepository.mediaPreviewLimit + 1))
    try handle.close()
    let file = try #require(try await f.git.load().files.first { $0.path == "large.wav" })
    let comparison = try #require(await f.git.mediaComparison(file: file))
    if case .unavailable(let message) = comparison.after { #expect(message.contains("128 MB")) }
    else { Issue.record("Oversized files should not be loaded into memory") }
}

@Test func fullScreenHeaderInsetsDoNotApplyWindowedOffset() {
    #expect(WindowHeaderInsets(fullScreen: false, measuredTitlebar: 52).contentOverlap == 52)
    #expect(WindowHeaderInsets(fullScreen: false, measuredTitlebar: 52).sidebarTop == 52)
    #expect(WindowHeaderInsets(fullScreen: true, measuredTitlebar: 52).contentOverlap == 0)
    #expect(WindowHeaderInsets(fullScreen: true, measuredTitlebar: 52).sidebarTop == 0)
    #expect(WindowHeaderInsets(fullScreen: false, measuredTitlebar: -10).contentOverlap == 0)
    #expect(WindowHeaderInsets(fullScreen: false, measuredTitlebar: .nan).contentOverlap == 0)
}
