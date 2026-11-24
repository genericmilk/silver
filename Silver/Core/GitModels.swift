import Foundation

public struct GitFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct GitCommit: Identifiable, Hashable, Sendable {
    public let id: String
    public let parents: [String]
    public let author: String
    public let email: String
    public let date: Date
    public let subject: String
    public let body: String
    public let decorations: String
    public var shortID: String { String(id.prefix(7)) }
}

public struct GitBranch: Identifiable, Hashable, Sendable {
    public let name: String
    public let current: Bool
    public let remote: Bool
    public let upstream: String
    public var id: String { name }
}

public struct GitFile: Identifiable, Hashable, Sendable {
    public let path: String
    public let originalPath: String?
    public let indexStatus: Character
    public let worktreeStatus: Character
    public var id: String { path }
    public var isUntracked: Bool { indexStatus == "?" }
    public var isStaged: Bool { indexStatus != " " && indexStatus != "?" }
    public var hasUnstagedChanges: Bool { worktreeStatus != " " || isUntracked }
    public var isConflicted: Bool {
        ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains("\(indexStatus)\(worktreeStatus)")
    }
    public var status: String {
        if isConflicted { return "Conflict" }
        if isUntracked { return "New" }
        let codes = "\(indexStatus)\(worktreeStatus)"
        if codes.contains("R") { return "Renamed" }
        if codes.contains("D") { return "Deleted" }
        if codes.contains("A") { return "Added" }
        return "Modified"
    }
}

public struct CommitFile: Identifiable, Hashable, Sendable {
    public let path: String
    public let status: String
    public var originalPath: String? = nil
    public var id: String { path }
}

public struct RepositorySnapshot: Sendable {
    public let root: URL
    public let branch: String
    public let commits: [GitCommit]
    public let branches: [GitBranch]
    public let files: [GitFile]
    public let ahead: Int
    public let behind: Int
}

public enum GitParser {
    public static func status(_ output: String) -> [GitFile] {
        let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var files: [GitFile] = []
        var i = 0
        while i < records.count {
            let chars = Array(records[i])
            guard chars.count >= 4 else { i += 1; continue }
            let path = String(chars.dropFirst(3))
            let renamed = chars[0] == "R" || chars[1] == "R" || chars[0] == "C" || chars[1] == "C"
            let original = renamed && i + 1 < records.count ? records[i + 1] : nil
            files.append(GitFile(path: path, originalPath: original, indexStatus: chars[0], worktreeStatus: chars[1]))
            i += original == nil ? 1 : 2
        }
        return files
    }

    public static func history(_ output: String) -> [GitCommit] {
        let fields = output.components(separatedBy: "\0")
        var result: [GitCommit] = []
        var i = 0
        while i + 7 < fields.count {
            result.append(GitCommit(
                id: fields[i], parents: fields[i + 1].split(separator: " ").map(String.init),
                author: fields[i + 2], email: fields[i + 3],
                date: Date(timeIntervalSince1970: Double(fields[i + 4]) ?? 0),
                subject: fields[i + 5], body: fields[i + 6].trimmingCharacters(in: .whitespacesAndNewlines),
                decorations: fields[i + 7]
            ))
            i += 8
        }
        return result
    }

    public static func branches(_ output: String) -> [GitBranch] {
        output.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\t")
            guard f.count == 4 else { return nil }
            return GitBranch(name: f[0], current: f[1] == "*", remote: f[2].hasPrefix("refs/remotes/"), upstream: f[3])
        }
    }

    public static func commitFiles(_ output: String) -> [CommitFile] {
        let fields = output.split(separator: "\0").map(String.init)
        var files: [CommitFile] = []
        var i = 0
        while i + 1 < fields.count {
            let status = fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let renamed = status.hasPrefix("R") || status.hasPrefix("C")
            let offset = renamed ? 2 : 1
            guard i + offset < fields.count else { break }
            files.append(CommitFile(path: fields[i + offset], status: status, originalPath: renamed ? fields[i + 1] : nil))
            i += offset + 1
        }
        return files
    }
}
