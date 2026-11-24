import SwiftUI

struct DiffView: View {
    let text: String
    @Environment(Preferences.self) private var preferences
    var body: some View {
        DiffTableView(text: text, expandContext: preferences.layout.expandContext)
    }
}

private final class DiffBoundsObservers: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

private final class DiffContainerView: NSView {
    let left = DiffScrollView()
    let right = DiffScrollView()
    private let divider = NSBox()
    var split = false { didSet { needsLayout = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        divider.boxType = .separator
        addSubview(left); addSubview(right); addSubview(divider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        right.isHidden = !split
        divider.isHidden = !split
        let half = floor(bounds.width / 2)
        left.frame = split ? NSRect(x: 0, y: 0, width: half, height: bounds.height) : bounds
        right.frame = NSRect(x: half + 1, y: 0, width: max(0, bounds.width - half - 1), height: bounds.height)
        divider.frame = NSRect(x: half, y: 0, width: 1, height: bounds.height)
    }
}

private final class DiffScrollView: NSScrollView {
    var onResize: (() -> Void)?
    override func tile() { super.tile(); onResize?() }
}

private struct DiffTableView: NSViewRepresentable {
    @Environment(Preferences.self) private var preferences
    @Environment(\.colorScheme) private var scheme
    let text: String
    let expandContext: Bool

    func makeNSView(context: Context) -> DiffContainerView {
        let container = DiffContainerView()
        let c = context.coordinator
        c.leftScroll = container.left
        c.rightScroll = container.right
        for scroll in [container.left, container.right] {
            let clip = NSClipView()
            clip.postsBoundsChangedNotifications = true
            scroll.contentView = clip
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .noBorder
            let table = NSTableView()
            table.delegate = c
            table.dataSource = c
            table.backgroundColor = .textBackgroundColor
            table.gridStyleMask = [.solidVerticalGridLineMask]
            table.gridColor = .separatorColor.withAlphaComponent(0.35)
            table.intercellSpacing = NSSize(width: 0, height: 0)
            table.selectionHighlightStyle = .none
            table.columnAutoresizingStyle = .noColumnAutoresizing
            table.allowsColumnReordering = false
            table.allowsColumnResizing = false
            table.setAccessibilityLabel(scroll === container.left ? "File changes before" : "File changes after")
            scroll.documentView = table
            if scroll === container.left { c.leftTable = table } else { c.rightTable = table }
            scroll.onResize = { [weak c] in c?.resizeColumns() }
            c.observations.tokens.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak c, weak scroll] _ in
                MainActor.assumeIsolated { if let scroll { c?.syncScroll(from: scroll) } }
            })
        }
        return container
    }

    func updateNSView(_ container: DiffContainerView, context: Context) {
        let c = context.coordinator
        let split = preferences.diffStyle == "split"
        let newSource = c.source != text
        let changed = newSource || c.options != preferences.layout || c.split != split || c.numbers != preferences.lineNumbers || c.expandAll != expandContext || c.scheme != scheme
        guard changed else { return }
        let restructure = c.split != split || c.numbers != preferences.lineNumbers || c.leftTable?.tableColumns.isEmpty == true
        if newSource || c.split != split { c.expanded.removeAll() }
        c.source = text
        c.options = preferences.layout
        c.split = split
        container.split = split
        c.numbers = preferences.lineNumbers
        c.expandAll = expandContext
        c.scheme = scheme
        c.layout = DiffLayout(text: text.isEmpty ? "No textual changes to display." : text, sideBySide: split)
        if restructure { c.configureColumns() }
        c.rebuild()
        if newSource {
            for scroll in [container.left, container.right] { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var leftTable: NSTableView?
        weak var rightTable: NSTableView?
        weak var leftScroll: DiffScrollView?
        weak var rightScroll: DiffScrollView?
        private var tables: [NSTableView] { [leftTable, split ? rightTable : nil].compactMap { $0 } }
        private var syncing = false
        let observations = DiffBoundsObservers()
        var source: String?
        var options = AppearanceOptions()
        var split = false
        var numbers = true
        var expandAll = false
        var scheme: ColorScheme?
        var layout = DiffLayout(text: "", sideBySide: false)
        var expanded: Set<Int> = []
        var visible: [VisibleRow] = []
        private var viewportWidths: [ObjectIdentifier: CGFloat] = [:]
        private var contentWidths: [String: CGFloat] = [:]
        private var resizing = false
        private var gutterWidth: CGFloat {
            let highest = layout.rows.reduce(0) { result, row in max(result, row.left?.oldNumber ?? 0, row.left?.newNumber ?? 0, row.right?.newNumber ?? 0) }
            let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, options.codeSize - 1), weight: .regular)
            return max(25, ceil((String(highest) as NSString).size(withAttributes: [.font: font]).width) + 10)
        }
        private var rowHeight: CGFloat { ceil(options.codeNSFont.ascender - options.codeNSFont.descender + options.codeNSFont.leading + options.codeLineSpacing + 5) }

        struct VisibleRow {
            var row: DiffRow?
            var fold: Int?
            var title: String = ""
        }
        func syncScroll(from source: DiffScrollView) {
            guard split, !syncing, let target = source === leftScroll ? rightScroll : leftScroll else { return }
            guard abs(target.contentView.bounds.minY - source.contentView.bounds.minY) > 0.5 || abs(target.contentView.bounds.minX - source.contentView.bounds.minX) > 0.5 else { return }
            syncing = true
            target.contentView.scroll(to: source.contentView.bounds.origin)
            target.reflectScrolledClipView(target.contentView)
            syncing = false
        }
        func configureColumns() {
            resizing = true
            defer { resizing = false }
            for table in [leftTable, rightTable].compactMap({ $0 }) {
                for column in table.tableColumns { table.removeTableColumn(column) }
                let right = table === rightTable
                let ids = split ? (numbers ? [right ? "newNumber" : "oldNumber", right ? "newText" : "oldText"] : [right ? "newText" : "oldText"]) : (numbers ? ["oldNumber", "newNumber", "text"] : ["text"])
                for id in ids {
                    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                    column.title = id == "oldText" ? "Before" : id == "newText" ? "After" : ""
                    column.minWidth = id.hasSuffix("Number") ? 20 : 100
                    column.maxWidth = 10_000_000
                    table.addTableColumn(column)
                }
                table.headerView = split ? NSTableHeaderView() : nil
            }
            viewportWidths.removeAll()
        }
        func rebuild() {
            let origins = [leftScroll?.contentView.bounds.origin ?? .zero, rightScroll?.contentView.bounds.origin ?? .zero]
            visible = []
            let rows = layout.displayRows
            let edge = max(0, options.contextLines)
            var index = 0
            while index < rows.count {
                guard rows[index].isContext else { visible.append(VisibleRow(row: rows[index])); index += 1; continue }
                let start = index
                while index < rows.count && rows[index].isContext { index += 1 }
                let run = Array(rows[start..<index])
                if run.count > edge * 2 + 2 && !expandAll {
                    if expanded.contains(start) {
                        visible.append(VisibleRow(fold: start, title: "Hide unchanged lines"))
                        visible += run.map { VisibleRow(row: $0) }
                    } else {
                        visible += run.prefix(edge).map { VisibleRow(row: $0) }
                        visible.append(VisibleRow(fold: start, title: "Show \(run.count - edge * 2) unchanged lines"))
                        visible += run.suffix(edge).map { VisibleRow(row: $0) }
                    }
                } else { visible += run.map { VisibleRow(row: $0) } }
            }
            if layout.truncated { visible.append(VisibleRow(title: "Preview truncated. Open the file to see the rest.")) }
            if visible.isEmpty { visible.append(VisibleRow(title: "No textual changes to display.")) }
            contentWidths.removeAll()
            viewportWidths.removeAll()
            for table in tables { table.reloadData() }
            resizeColumns()
            for (index, scroll) in [leftScroll, rightScroll].enumerated() {
                scroll?.contentView.scroll(to: origins[index])
                if let scroll { scroll.reflectScrolledClipView(scroll.contentView) }
            }
        }
        func resizeColumns() {
            guard !resizing else { return }
            resizing = true
            defer { resizing = false }
            var changed = false
            for table in tables {
                guard let scroll = table.enclosingScrollView else { continue }
                let width = scroll.contentSize.width
                let key = ObjectIdentifier(table)
                guard width > 0, abs(width - (viewportWidths[key] ?? -1)) > 0.5 else { continue }
                viewportWidths[key] = width
                changed = true
                let gutter: CGFloat = numbers ? gutterWidth * (split ? 1 : 2) : 0
                let available = max(100, width - gutter)
                for column in table.tableColumns {
                    let id = column.identifier.rawValue
                    if id.hasSuffix("Number") { column.width = gutterWidth; continue }
                    var natural = available
                    if !options.wrapLines {
                        if let cached = contentWidths[id] { natural = max(available, cached) }
                        else {
                            let measured = visible.map { row -> CGFloat in
                                let values = split ? [row.row?.left?.content, row.row?.right?.content, row.title].compactMap { $0 } : [line(for: row.row, column: id)?.content ?? row.title]
                                return values.map { ($0 as NSString).size(withAttributes: [.font: options.codeNSFont]).width + 30 }.max() ?? 0
                            }.max() ?? available
                            contentWidths[id] = measured
                            natural = max(available, measured)
                        }
                    }
                    column.width = natural
                }
            }
            if changed {
                for table in tables { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<visible.count)) }
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        private func line(for row: DiffRow?, column: String) -> DiffLine? {
            guard let row else { return nil }
            return column == "newText" || (split && column == "newNumber") ? row.right : row.left
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if visible.indices.contains(row) {
                if visible[row].row?.left?.kind == .hunk { return 12 }
                if visible[row].row?.left?.kind == .file { return rowHeight + 12 }
            }
            guard options.wrapLines, visible.indices.contains(row), let item = visible[row].row else { return rowHeight }
            var height = rowHeight
            for column in tables.flatMap(\.tableColumns) where !column.identifier.rawValue.hasSuffix("Number") {
                guard let line = line(for: item, column: column.identifier.rawValue) else { continue }
                let rect = (line.content as NSString).boundingRect(with: NSSize(width: max(30, column.width - 20), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: options.codeNSFont, .paragraphStyle: paragraph()])
                height = max(height, ceil(rect.height) + 7)
            }
            return height
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard visible.indices.contains(index), let column = tableColumn else { return nil }
            let id = column.identifier.rawValue
            let item = visible[index]
            let cell = NSTableCellView()
            cell.wantsLayer = true
            if item.row?.left?.kind == .hunk {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(divider)
                NSLayoutConstraint.activate([divider.leadingAnchor.constraint(equalTo: cell.leadingAnchor), divider.trailingAnchor.constraint(equalTo: cell.trailingAnchor), divider.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                return cell
            }
            if let fold = item.fold, !id.hasSuffix("Number") {
                let button = NSButton(title: "⋯  " + item.title, target: self, action: #selector(toggleFold(_:)))
                button.tag = fold
                button.isBordered = false
                button.contentTintColor = .linkColor
                button.alignment = .left
                button.font = options.codeNSFont
                button.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(button)
                NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), button.centerYAnchor.constraint(equalTo: cell.centerYAnchor), button.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6)])
                return cell
            }
            let line = line(for: item.row, column: id)
            let numberColumn = id.hasSuffix("Number")
            let field = NSTextField(wrappingLabelWithString: "")
            field.font = numberColumn ? .monospacedDigitSystemFont(ofSize: max(9, options.codeSize - 1), weight: .regular) : options.codeNSFont
            field.isSelectable = !numberColumn
            field.drawsBackground = false
            field.isBezeled = false
            field.lineBreakMode = options.wrapLines && !numberColumn ? .byWordWrapping : .byClipping
            field.maximumNumberOfLines = options.wrapLines && !numberColumn ? 0 : 1
            field.alignment = numberColumn ? .right : .left
            field.textColor = numberColumn ? .tertiaryLabelColor : .labelColor
            if numberColumn {
                let value = id == "oldNumber" ? line?.oldNumber : line?.newNumber
                field.stringValue = value.map(String.init) ?? ""
                cell.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            } else if let line {
                field.stringValue = split ? line.content : line.text
                switch line.kind {
                case .addition:
                    field.textColor = options.additionColor
                    if options.diffBackgrounds { cell.layer?.backgroundColor = options.additionColor.withAlphaComponent(0.08).cgColor }
                case .deletion:
                    field.textColor = options.deletionColor
                    if options.diffBackgrounds { cell.layer?.backgroundColor = options.deletionColor.withAlphaComponent(0.08).cgColor }
                case .hunk: field.textColor = .systemBlue
                case .metadata, .note: field.textColor = .secondaryLabelColor
                case .file:
                    field.font = .systemFont(ofSize: options.codeSize, weight: .semibold)
                    cell.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                default: break
                }
            } else { field.stringValue = item.title }
            let attributed = NSMutableAttributedString(string: field.stringValue, attributes: [.font: field.font ?? options.codeNSFont, .foregroundColor: field.textColor ?? NSColor.labelColor, .paragraphStyle: paragraph()])
            field.attributedStringValue = attributed
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: numberColumn ? 1 : 10), field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: numberColumn ? -4 : -7), field.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2)])
            return cell
        }
        private func paragraph() -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = options.codeLineSpacing
            p.lineBreakMode = options.wrapLines ? .byWordWrapping : .byClipping
            return p
        }
        @objc private func toggleFold(_ sender: NSButton) {
            if expanded.contains(sender.tag) { expanded.remove(sender.tag) } else { expanded.insert(sender.tag) }
            rebuild()
        }
    }
}
