import Foundation

public enum DiffLineKind: Sendable { case context, addition, deletion, hunk, metadata, note, file }

public struct DiffLine: Sendable {
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
    public let kind: DiffLineKind
    public var content: String {
        switch kind { case .context, .addition, .deletion: String(text.dropFirst()); default: text }
    }
}

public struct DiffRow: Identifiable, Sendable {
    public let id: Int
    public let left: DiffLine?
    public let right: DiffLine?
    public var isContext: Bool { left?.kind == .context && (right == nil || right?.kind == .context) }
}

public struct DiffLayout: Sendable {
    public let rows: [DiffRow]
    public let truncated: Bool
    public var displayRows: [DiffRow] {
        let multipleFiles = rows.filter { $0.left?.text.hasPrefix("diff --git ") == true }.count > 1
        var result: [DiffRow] = []
        func append(_ text: String, kind: DiffLineKind, source: DiffRow) {
            let line = DiffLine(text: text, oldNumber: nil, newNumber: nil, kind: kind)
            result.append(DiffRow(id: source.id, left: line, right: source.right == nil ? nil : line))
        }
        for (index, row) in rows.enumerated() {
            guard let line = row.left ?? row.right else { continue }
            switch line.kind {
            case .metadata:
                let raw = line.text
                if raw.hasPrefix("diff --git "), multipleFiles {
                    var path: String?
                    for next in rows.dropFirst(index + 1) {
                        guard let value = next.left?.text else { continue }
                        if value.hasPrefix("diff --git ") || next.left?.kind == .hunk { break }
                        if value.hasPrefix("--- a/") { path = String(value.dropFirst(6)) }
                        if value.hasPrefix("+++ b/") { path = String(value.dropFirst(6)); break }
                        if value.hasPrefix("rename to ") { path = String(value.dropFirst(10)) }
                    }
                    append(path ?? "Changed file", kind: .file, source: row)
                } else if raw.hasPrefix("old mode ") {
                    append("File permissions changed", kind: .note, source: row)
                } else if raw.hasPrefix("Binary files ") {
                    append("Binary file", kind: .note, source: row)
                } else if !raw.isEmpty && !["diff --git ", "index ", "--- ", "+++ ", "new file mode ", "deleted file mode ", "new mode ", "similarity index ", "dissimilarity index ", "rename from ", "rename to ", "copy from ", "copy to "].contains(where: raw.hasPrefix) {
                    result.append(row)
                }
            case .hunk:
                if let previous = result.last, previous.left?.kind != .file { append("", kind: .hunk, source: row) }
            case .note:
                append(line.text.hasPrefix("\\ ") ? String(line.text.dropFirst(2)) : line.text, kind: .note, source: row)
            default: result.append(row)
            }
        }
        return result
    }
    public init(text: String, sideBySide: Bool, limit: Int = 500_000) {
        truncated = text.count > limit
        var old = 0, new = 0
        var inHunk = false
        var lines: [DiffLine] = []
        for raw in String(text.prefix(limit)).components(separatedBy: "\n") {
            if raw.hasPrefix("diff --git ") { inHunk = false }
            if raw.hasPrefix("@@ ") {
                let parts = raw.split(separator: " ")
                if parts.count >= 3,
                   let a = parts[1].dropFirst().split(separator: ",").first.flatMap({ Int($0) }),
                   let b = parts[2].dropFirst().split(separator: ",").first.flatMap({ Int($0) }) {
                    old = a; new = b; inHunk = true
                }
                lines.append(DiffLine(text: raw, oldNumber: nil, newNumber: nil, kind: .hunk))
            } else if inHunk && raw.hasPrefix(" ") {
                lines.append(DiffLine(text: raw, oldNumber: old, newNumber: new, kind: .context)); old += 1; new += 1
            } else if inHunk && raw.hasPrefix("-") {
                lines.append(DiffLine(text: raw, oldNumber: old, newNumber: nil, kind: .deletion)); old += 1
            } else if inHunk && raw.hasPrefix("+") {
                lines.append(DiffLine(text: raw, oldNumber: nil, newNumber: new, kind: .addition)); new += 1
            } else {
                lines.append(DiffLine(text: raw, oldNumber: nil, newNumber: nil, kind: raw.hasPrefix("\\") ? .note : .metadata))
            }
        }
        var result: [DiffRow] = []
        var removed: [DiffLine] = [], added: [DiffLine] = []
        func flush() {
            for i in 0..<max(removed.count, added.count) {
                result.append(DiffRow(id: result.count, left: i < removed.count ? removed[i] : nil, right: i < added.count ? added[i] : nil))
            }
            removed.removeAll(); added.removeAll()
        }
        for line in lines {
            if !sideBySide {
                result.append(DiffRow(id: result.count, left: line, right: nil))
            } else {
                switch line.kind {
                case .deletion: removed.append(line)
                case .addition: added.append(line)
                default:
                    flush()
                    result.append(DiffRow(id: result.count, left: line, right: line))
                }
            }
        }
        flush()
        rows = result
    }
}

public struct ChangeSelection: Sendable {
    public private(set) var checked: Set<String> = []
    private var known: Set<String> = []
    public init() {}
    public mutating func reconcile(paths: [String]) {
        let current = Set(paths)
        checked.formIntersection(current)
        checked.formUnion(current.subtracting(known))
        known = current
    }
    public mutating func set(_ path: String, checked value: Bool) {
        if value { checked.insert(path) } else { checked.remove(path) }
    }
    public mutating func setAll(_ value: Bool) { checked = value ? known : [] }
}
