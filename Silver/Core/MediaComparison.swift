import Foundation
import UniformTypeIdentifiers

public enum MediaKind: String, Sendable {
    case image, audio
    public static func detect(path: String) -> MediaKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }
}

public enum MediaVersion: Sendable {
    case absent
    case content(Data, path: String)
    case unavailable(String)
    public var data: Data? { if case .content(let data, _) = self { data } else { nil } }
}

public struct MediaComparison: Sendable {
    public let kind: MediaKind
    public let before: MediaVersion
    public let after: MediaVersion
}

extension GitRepository {
    public static let mediaPreviewLimit = 128 * 1_024 * 1_024

    /// Compares HEAD with the current file, matching the selected-file commit preview.
    public func mediaComparison(file: GitFile) async -> MediaComparison? {
        guard let kind = MediaKind.detect(path: file.path) ?? file.originalPath.flatMap({ MediaKind.detect(path: $0) }) else { return nil }
        let head = try? await run(["rev-parse", "--verify", "HEAD"])
        let before = await storedMedia(revision: head?.trimmingCharacters(in: .whitespacesAndNewlines), path: file.originalPath ?? file.path)
        let after = await workingMedia(path: file.path)
        return MediaComparison(kind: kind, before: before, after: after)
    }

    /// Merge commits use the first parent, consistent with text diffs.
    public func mediaComparison(commit: GitCommit, file: CommitFile) async -> MediaComparison? {
        guard let kind = MediaKind.detect(path: file.path) ?? file.originalPath.flatMap({ MediaKind.detect(path: $0) }) else { return nil }
        let before = await storedMedia(revision: commit.parents.first, path: file.originalPath ?? file.path)
        let after = await storedMedia(revision: commit.id, path: file.path)
        return MediaComparison(kind: kind, before: before, after: after)
    }

    private func storedMedia(revision: String?, path: String) async -> MediaVersion {
        guard let revision else { return .absent }
        do {
            // Resolve exact paths with NUL-delimited output instead of constructing revision:path.
            let entries = try await run(["--literal-pathspecs", "ls-tree", "-z", revision, "--", path])
            guard let record = entries.split(separator: "\0").first else { return .absent }
            let metadata = record.split(separator: "\t", maxSplits: 1)[0].split(separator: " ")
            guard metadata.count == 3, metadata[1] == "blob" else { return .unavailable("This entry is not a regular file.") }
            guard metadata[0] != "120000" else { return .unavailable("Symbolic links do not have a media preview.") }
            let data = try await GitRunner.runData(["cat-file", "blob", String(metadata[2])], at: url, maximumBytes: Self.mediaPreviewLimit)
            return .content(data, path: path)
        } catch { return .unavailable(error.localizedDescription) }
    }

    private func workingMedia(path: String) async -> MediaVersion {
        let root = url
        return await Task.detached(priority: .userInitiated) {
            do {
                let file = root.appendingPathComponent(path)
                let values: URLResourceValues
                do { values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .absent }
                guard values.isSymbolicLink != true, values.isRegularFile == true else { return .unavailable("This entry is not a regular media file.") }
                guard (values.fileSize ?? 0) <= Self.mediaPreviewLimit else { return .unavailable("This file exceeds the 128 MB preview limit.") }
                return .content(try Data(contentsOf: file), path: path)
            } catch { return .unavailable(error.localizedDescription) }
        }.value
    }
}
