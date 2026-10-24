/// Linear's entry, the only editor whose blocks uvim measured: how its blocks show in the tree and which have stops beside them.
public enum Linear {
    /// ProseMirror's class on its editor; its gap cursor, Linear's stop, is a plugin another editor may not have.
    public static let editorClass = "ProseMirror"

    /// Linear's own DOM class on a list, which no other editor's list carries.
    public static let listClass = "list-node"

    /// Linear's own DOM class on a code block, a quote and a collapsible section, which no other editor's quote carries.
    public static let blockClass = "block-node"

    /// Linear's classes on a table's root and on a collapsible section (LIN-1780).
    public static let tableClass = "tableContainer"
    public static let sectionClass = "collapsible-section"

    /// Linear's classes on its root blocks; a rule's `AXSplitter` has none, so only a root with one shows a rule is Linear's.
    public static let rootClasses: Set<String> = [listClass, blockClass, tableClass, sectionClass, "text-node", "heading-node"]

    /// Linear's class on the group that holds a code block's language label and buttons, before its code.
    public static let controlsClass = "node-controls"

    /// A caret stop between two lines, which holds no text.
    public enum Stop: Hashable, Sendable {
        /// The line starts a list, code block or quote right after another, and a plain → ↓ or ↑ stops between them first.
        case gap
        /// The same where ⇧→ does not cross it: text-less leaves start the block, as a to-do's checkbox does, or a table is beside it.
        case boxedGap
        /// Only ↑ from the line stops first, as below a collapsed section's title (LIN-1780).
        case upGap
        /// A rule before the line, which every plain arrow from either side selects first.
        case rule
        /// The stop between two rules, which every plain arrow visits.
        case ruleGap
        /// The stop between a table and a rule after it, which only ← and ↑ visit.
        case backGap

        /// A stop → ↓ and ↑ all visit between two blocks, which `KeyModel`'s gaps stand for.
        public var isGap: Bool { self == .gap || self == .boxedGap }
    }

    /// A block as its own classes tell it.
    enum BlockKind: Equatable {
        case list, quote, code, table, rule, other
        case section(open: Bool)

        /// Linear stops between two adjacent blocks closed where they meet; a collapsed section only for ↑ from below.
        var closedEnd: Bool { [.list, .quote, .code, .table, .section(open: true)].contains(self) }
        var closedStart: Bool { closedEnd || self == .section(open: false) }
    }

    /// The stop between two adjacent blocks, of the kinds measured beside each other; a rule meets none but a rule's or a table's.
    static func stop(between previous: BlockKind, and next: BlockKind) -> Stop? {
        switch (previous, next) {
        case (.table, .rule): .backGap
        case (.rule, .rule): .ruleGap
        case (.rule, .table): .boxedGap
        case (.section(open: false), _) where next.closedStart: .upGap
        case _ where previous.closedEnd && next.closedStart: previous == .table || next == .table ? .boxedGap : .gap
        default: nil
        }
    }

    /// A join's stop, none where Chromium's own list marker starts the line, as only Linear's ProseMirror makes one.
    static func joinStop(leaves: Int, prefixed: Bool) -> Stop? {
        prefixed ? nil : joinStop(leaves: leaves)
    }

    /// Boxed where text-less leaves start the block, as a to-do's checkbox does, whether or not `AXValue` gives them lines.
    static func joinStop(leaves: Int) -> Stop {
        leaves > 0 ? .boxedGap : .gap
    }

    /// What its own blocks add: joins as the lists', code blocks' controls, other stops and tables (LIN-1726, LIN-1780).
    struct Blocks {
        var joins: [Int] = []
        var controls: [Range<Int>] = []
        var stops: [UnreachableLines.Stop] = []
        var tables: [UnreachableLines.Table] = []
        var containers: [[Int]] = []
        /// A root carries one of Linear's classes, without which a rule is not known to be Linear's.
        var linear = false
    }

    /// Plain starts of root lists that follow another root list; nil on a failed read or past `scan`'s budget.
    static func listJoins<Node>(in roots: [Node], scan: inout UnreachableScan<Node>) -> [Int]? {
        var joins: [Int] = []
        var afterList = false
        for (index, root) in roots.enumerated() {
            guard let read = scan.read(root, at: [index]) else { return nil }
            let list = read.role == "AXList"
            if list, afterList {
                guard let start = scan.start(of: root, at: [index]) else { return nil }
                joins.append(start)
            }
            afterList = list
        }
        return joins
    }

    /// Records the stops among `nodes`, roots or a quote's or open section's children, each judged by its own classes; false on a failed read.
    static func stops<Node>(
        among nodes: [Node], path: [Int], level: Int, into blocks: inout Blocks, scan: inout UnreachableScan<Node>
    ) -> Bool {
        if path.isEmpty {
            for (index, node) in nodes.enumerated() where !blocks.linear {
                guard let read = scan.read(node, at: [index]) else { return false }
                blocks.linear = !rootClasses.isDisjoint(with: read.classes)
            }
        }
        var previous: BlockKind?
        for (index, node) in nodes.enumerated() {
            let here = path + [index]
            guard let read = scan.read(node, at: here),
                  let kind = kind(of: node, read, at: here, level: level, into: &blocks, scan: &scan) else {
                return false
            }
            if let previous, let stop = stop(between: previous, and: kind) {
                guard let start = scan.start(of: node, at: here) else { return false }
                if stop == .gap { blocks.joins.append(start) } else { blocks.stops.append(.init(at: start, kind: stop)) }
            }
            if kind == .rule {
                guard let start = scan.start(of: node, at: here) else { return false }
                blocks.stops.append(.init(at: start, kind: .rule))
            }
            // A quote's and an open section's blocks have the same stops among themselves, past the section's heading.
            if kind == .quote || kind == .section(open: true) {
                blocks.containers.append(here)
                guard stops(among: read.children, path: here, level: read.quoteLevel, into: &blocks, scan: &scan) else {
                    return false
                }
            }
            previous = kind
        }
        return true
    }

    /// `read`'s kind, inside a quote of `level`; a code block's controls and a table's rows go into `blocks`. Nil past the budget.
    private static func kind<Node>(
        of node: Node, _ read: EmptyBlockScan<Node>.Block, at path: [Int], level: Int, into blocks: inout Blocks,
        scan: inout UnreachableScan<Node>
    ) -> BlockKind? {
        if read.role == "AXList" { return read.classes.contains(listClass) ? .list : .other }
        if read.role == "AXSplitter" { return blocks.linear ? .rule : .other }
        if read.classes.contains(tableClass) {
            guard let table = table(node, read, at: path, scan: &scan) else { return nil }
            blocks.tables.append(table)
            return .table
        }
        if read.classes.contains(sectionClass) { return .section(open: read.children.count > 1) }
        guard read.classes.contains(blockClass) else { return .other }
        // A quote's blocks share its level, so only a deeper one starts a quote of its own.
        if read.quoteLevel > level { return .quote }
        guard read.children.count > 1, let first = read.children.first, let last = read.children.last else { return .other }
        let codePath = path + [read.children.count - 1]
        guard let lead = scan.read(first, at: path + [0]), let code = scan.read(last, at: codePath) else { return nil }
        // A code block: its controls, then its code, which is an empty group once the code is deleted.
        guard lead.classes.contains(controlsClass),
              DrawnCaret.isCode(code.subrole) || DrawnCaret.isEmptyGroup(subrole: code.subrole, children: code.children.count)
        else { return .other }
        guard let lower = scan.start(of: node, at: path), let upper = scan.start(of: last, at: codePath) else { return nil }
        blocks.controls.append(lower..<upper)
        return .code
    }

    /// A table's plain range and where its last row starts, the last `AXRow` under its wrapper's `AXTable`; nil past the budget.
    private static func table<Node>(
        _ node: Node, _ read: EmptyBlockScan<Node>.Block, at path: [Int], scan: inout UnreachableScan<Node>
    ) -> UnreachableLines.Table? {
        guard let lower = scan.start(of: node, at: path), let upper = scan.end(of: node, at: path) else { return nil }
        var lastRow: Int?
        if let wrapper = read.children.first {
            guard let wrapped = scan.read(wrapper, at: path + [0]) else { return nil }
            if let grid = wrapped.children.first {
                guard let table = scan.read(grid, at: path + [0, 0]) else { return nil }
                // The rows come before the columns and the header.
                for index in table.children.indices.reversed() where table.role == "AXTable" {
                    let rowPath = path + [0, 0, index]
                    guard let row = scan.read(table.children[index], at: rowPath) else { return nil }
                    guard row.role == "AXRow" else { continue }
                    guard let start = scan.start(of: table.children[index], at: rowPath) else { return nil }
                    lastRow = start
                    break
                }
            }
        }
        return UnreachableLines.Table(range: lower..<upper, lastRow: lastRow)
    }
}
