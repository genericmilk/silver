import Foundation

public struct DiffBlock: Identifiable, Sendable {
    public let id: Int
    public let lines: [String]
    public let isFoldable: Bool
    public let contextLines: Int
    public var hiddenLineCount: Int { max(0, lines.count - contextLines * 2) }
}

public struct DiffDocument: Sendable {
    public let blocks: [DiffBlock]
    public let truncated: Bool

    public init(text: String, contextLines: Int = 3, limit: Int = 500_000) {
        truncated = text.count > limit
        let lines = String(text.prefix(limit)).components(separatedBy: "\n")
        var blocks: [DiffBlock] = []
        var pending: [String] = []
        var isContext = false
        func flush() {
            guard !pending.isEmpty else { return }
            let edge = max(0, contextLines)
            blocks.append(DiffBlock(id: blocks.count, lines: pending, isFoldable: isContext && pending.count > edge * 2 + 2, contextLines: edge))
            pending = []
        }
        for line in lines {
            let context = line.hasPrefix(" ")
            if context != isContext { flush(); isContext = context }
            pending.append(line)
        }
        flush()
        self.blocks = blocks
    }
}
