/// Confirms in a Chromium field's tree which lines are list markers and which are chips, with their paragraphs (LIN-1652).
public struct UnreachableScan<Node> {
    /// Nil when a read fails for any reason but the attribute's absence. One read.
    private let block: (Node) -> EmptyBlockScan<Node>.Block?
    /// A node's plain offset from the field's start, at its start or its end; nil on a failed read. Two reads.
    private let offset: (Node, _ end: Bool) -> Int?
    private let budget: Int
    public private(set) var reads = 0
    /// The scan failed by running out of reads, not on a read.
    public private(set) var exhausted = false

    /// Reads by tree path, so candidates in one list or paragraph share them.
    private var blocks: [[Int]: EmptyBlockScan<Node>.Block] = [:]
    private var starts: [[Int]: Int] = [:]
    private var ends: [[Int]: Int] = [:]

    public init(
        budget: Int, block: @escaping (Node) -> EmptyBlockScan<Node>.Block?, offset: @escaping (Node, _ end: Bool) -> Int?
    ) {
        self.budget = budget
        self.block = block
        self.offset = offset
    }

    /// Nil on any failed read or past the budget.
    public mutating func run(blocks roots: [Node], candidates: UnreachableLines.Candidates) -> UnreachableLines.Found? {
        var markers: [Int] = []
        var chips: [UnreachableLines.Chip] = []
        var carets: [UnreachableLines.Caret] = []
        for candidate in candidates.markers {
            guard let hit = descend(to: candidate, in: roots) else { return nil }
            if case .marker = hit { markers.append(candidate.lowerBound) }
        }
        for candidate in candidates.chips {
            guard let hit = descend(to: candidate, in: roots) else { return nil }
            if case .chip(let range, let paragraph) = hit { chips.append(UnreachableLines.Chip(range: range, paragraph: paragraph)) }
        }
        for candidate in candidates.carets {
            guard let hit = caret(at: candidate, in: roots, path: [], ancestors: []) else { return nil }
            if let found = hit { carets.append(found) }
        }
        // Last, so running out of reads here loses only these, and Linear's blocks' reads after the lists', which lose only theirs.
        let lists = candidates.roots ? listJoins(in: roots) : nil
        var blocks: Blocks?
        if candidates.stops {
            var found = Blocks()
            if stops(among: roots, path: [], level: 0, into: &found) { blocks = found }
        }
        return UnreachableLines.Found(
            markers: markers, chips: chips, carets: carets, joins: Array(Set((lists ?? []) + (blocks?.joins ?? []))).sorted(),
            controls: blocks?.controls ?? [], stops: blocks?.stops ?? [], tables: blocks?.tables ?? [],
            containers: blocks?.containers ?? []
        )
    }

    /// Plain starts of root lists that follow another root list; nil on a failed read or past the budget.
    private mutating func listJoins(in roots: [Node]) -> [Int]? {
        var joins: [Int] = []
        var afterList = false
        for (index, root) in roots.enumerated() {
            guard let read = read(root, at: [index]) else { return nil }
            let list = read.role == "AXList"
            if list, afterList {
                guard let start = start(of: root, at: [index]) else { return nil }
                joins.append(start)
            }
            afterList = list
        }
        return joins
    }

    /// What Linear's own blocks add: joins as the lists', code blocks' controls, other stops and tables (LIN-1726, LIN-1780).
    private struct Blocks {
        var joins: [Int] = []
        var controls: [Range<Int>] = []
        var stops: [UnreachableLines.Stop] = []
        var tables: [UnreachableLines.Table] = []
        var containers: [[Int]] = []
        /// A root carries one of Linear's classes, without which a rule is not known to be Linear's.
        var linear = false
    }

    /// A block as its own classes tell it.
    private enum Kind: Equatable {
        case list, quote, code, table, rule, other
        case section(open: Bool)

        /// Linear stops between two adjacent blocks closed where they meet; a collapsed section only for ↑ from below.
        var closedEnd: Bool { [.list, .quote, .code, .table, .section(open: true)].contains(self) }
        var closedStart: Bool { closedEnd || self == .section(open: false) }
    }

    /// Judges `nodes`, a ProseMirror editor's roots or a quote's or open section's children, each by its own classes, and
    /// records the stops between them; false on a failed read or past the budget.
    private mutating func stops(among nodes: [Node], path: [Int], level: Int, into blocks: inout Blocks) -> Bool {
        if path.isEmpty {
            for (index, node) in nodes.enumerated() where !blocks.linear {
                guard let read = read(node, at: [index]) else { return false }
                blocks.linear = !UnreachableLines.rootClasses.isDisjoint(with: read.classes)
            }
        }
        var previous: Kind?
        for (index, node) in nodes.enumerated() {
            let here = path + [index]
            guard let read = read(node, at: here), let kind = kind(of: node, read, at: here, level: level, into: &blocks) else {
                return false
            }
            if let previous {
                // The kinds whose stops were measured beside each other; a rule meets none but another rule's or a table's.
                let stop: ParagraphBreaks.Hidden.Kind?
                switch (previous, kind) {
                case (.table, .rule): stop = .backGap
                case (.rule, .rule): stop = .ruleGap
                case (.rule, .table): stop = .boxedGap
                case (.section(open: false), _) where kind.closedStart: stop = .upGap
                case _ where previous.closedEnd && kind.closedStart: stop = previous == .table || kind == .table ? .boxedGap : .gap
                default: stop = nil
                }
                if let stop {
                    guard let start = start(of: node, at: here) else { return false }
                    if stop == .gap { blocks.joins.append(start) } else { blocks.stops.append(.init(at: start, kind: stop)) }
                }
            }
            if kind == .rule {
                guard let start = start(of: node, at: here) else { return false }
                blocks.stops.append(.init(at: start, kind: .rule))
            }
            // A quote's and an open section's blocks have the same stops among themselves, past the section's heading.
            if kind == .quote || kind == .section(open: true) {
                blocks.containers.append(here)
                guard stops(among: read.children, path: here, level: read.quoteLevel, into: &blocks) else { return false }
            }
            previous = kind
        }
        return true
    }

    /// `read`'s kind, inside a quote of `level`; a code block's controls and a table's rows go into `blocks`. Nil past the budget.
    private mutating func kind(
        of node: Node, _ read: EmptyBlockScan<Node>.Block, at path: [Int], level: Int, into blocks: inout Blocks
    ) -> Kind? {
        if read.role == "AXList" { return read.classes.contains(UnreachableLines.listClass) ? .list : .other }
        if read.role == "AXSplitter" { return blocks.linear ? .rule : .other }
        if read.classes.contains(UnreachableLines.tableClass) {
            guard let table = table(node, read, at: path) else { return nil }
            blocks.tables.append(table)
            return .table
        }
        if read.classes.contains(UnreachableLines.sectionClass) { return .section(open: read.children.count > 1) }
        guard read.classes.contains(UnreachableLines.blockClass) else { return .other }
        // A quote's blocks share its level, so only a deeper one starts a quote of its own.
        if read.quoteLevel > level { return .quote }
        guard read.children.count > 1, let first = read.children.first, let last = read.children.last else { return .other }
        let codePath = path + [read.children.count - 1]
        guard let lead = self.read(first, at: path + [0]), let code = self.read(last, at: codePath) else { return nil }
        // A code block: its controls, then its code, which is an empty group once the code is deleted.
        guard lead.classes.contains(UnreachableLines.controlsClass),
              DrawnCaret.isCode(code.subrole) || DrawnCaret.isEmptyGroup(subrole: code.subrole, children: code.children.count)
        else { return .other }
        guard let lower = start(of: node, at: path), let upper = start(of: last, at: codePath) else { return nil }
        blocks.controls.append(lower..<upper)
        return .code
    }

    /// A table's plain range and where its last row starts, the last `AXRow` under its wrapper's `AXTable`; nil past the budget.
    private mutating func table(_ node: Node, _ read: EmptyBlockScan<Node>.Block, at path: [Int]) -> UnreachableLines.Table? {
        guard let lower = start(of: node, at: path), let upper = end(of: node, at: path) else { return nil }
        var lastRow: Int?
        if let wrapper = read.children.first {
            guard let wrapped = self.read(wrapper, at: path + [0]) else { return nil }
            if let grid = wrapped.children.first {
                guard let table = self.read(grid, at: path + [0, 0]) else { return nil }
                // The rows come before the columns and the header.
                for index in table.children.indices.reversed() where table.role == "AXTable" {
                    let rowPath = path + [0, 0, index]
                    guard let row = self.read(table.children[index], at: rowPath) else { return nil }
                    guard row.role == "AXRow" else { continue }
                    guard let start = start(of: table.children[index], at: rowPath) else { return nil }
                    lastRow = start
                    break
                }
            }
        }
        return UnreachableLines.Table(range: lower..<upper, lastRow: lastRow)
    }

    private enum Hit {
        case marker
        case chip(Range<Int>, paragraph: Range<Int>)
        case neither
    }

    /// Descends through the children holding the candidate's start, found by binary search on their starts.
    private mutating func descend(to candidate: Range<Int>, in roots: [Node]) -> Hit? {
        var siblings = roots
        var path: [Int] = []
        var parent: (node: Node, start: Int)?
        var inList = false
        for _ in 0..<16 {
            var low = 0
            var high = siblings.count - 1
            var hit: (index: Int, start: Int)?
            while low <= high {
                let middle = (low + high) / 2
                guard let start = start(of: siblings[middle], at: path + [middle]) else { return nil }
                if start <= candidate.lowerBound {
                    hit = (middle, start)
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            guard let hit else { return .neither }
            let here = path + [hit.index]
            let node = siblings[hit.index]
            guard let read = read(node, at: here) else { return nil }
            if hit.start == candidate.lowerBound, read.subrole == "AXApplicationGroup" {
                guard let parent else { return .neither }
                guard let chipEnd = end(of: node, at: here), let paragraphEnd = end(of: parent.node, at: path) else { return nil }
                // Chromium puts a space after a chip on the chip's line.
                guard chipEnd > candidate.lowerBound + 1, chipEnd <= candidate.upperBound else { return .neither }
                return .chip(hit.start..<chipEnd, paragraph: parent.start..<paragraphEnd)
            }
            if inList, hit.start == candidate.lowerBound, let first = read.children.first {
                var marked = read.children.count > 1
                // An empty item of Chromium's own list holds its marker alone.
                if !marked {
                    guard let child = self.read(first, at: here + [0]) else { return nil }
                    marked = child.role == "AXListMarker"
                }
                if marked {
                    guard let end = end(of: first, at: here + [0]) else { return nil }
                    if end == candidate.upperBound { return .marker }
                }
            }
            if read.role == "AXStaticText" || read.children.isEmpty { return .neither }
            inList = read.role == "AXList"
            parent = (node, hit.start)
            siblings = read.children
            path = here
        }
        return nil
    }

    /// An ancestor of a drawn caret, nearest last: its reads, where it starts, and its place among its siblings.
    private struct Ancestor {
        let read: EmptyBlockScan<Node>.Block
        let start: Int
        let path: [Int]
        let siblings: [Node]

        var inline: Bool { DrawnCaret.isInline(role: read.role, subrole: read.subrole) }
    }

    /// The drawn caret among the nodes holding `p` at either end; `.some(nil)` where there is none, nil on a failed read.
    private mutating func caret(
        at p: Int, in siblings: [Node], path: [Int], ancestors: [Ancestor]
    ) -> UnreachableLines.Caret?? {
        guard ancestors.count < 16 else { return nil }
        var low = 0
        var high = siblings.count - 1
        var last: Int?
        while low <= high {
            let middle = (low + high) / 2
            guard let start = start(of: siblings[middle], at: path + [middle]) else { return nil }
            if start <= p {
                last = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard let last else { return .some(nil) }
        // Siblings are in text order, so those ending at or after `p` run back from the last starting at or before it.
        var first = last
        while first > 0 {
            guard let end = end(of: siblings[first - 1], at: path + [first - 1]) else { return nil }
            guard end >= p else { break }
            first -= 1
        }
        for index in first...last {
            let here = path + [index]
            guard let read = read(siblings[index], at: here) else { return nil }
            if DrawnCaret.isEmptyGroup(subrole: read.subrole, children: read.children.count) {
                guard let start = start(of: siblings[index], at: here) else { return nil }
                guard start == p else { continue }
                guard let place = place(of: here, among: siblings, under: ancestors) else { return nil }
                if let place { return .some(UnreachableLines.Caret(offset: p, place: place)) }
                continue
            }
            guard read.role != "AXStaticText", !read.children.isEmpty else { continue }
            guard let start = start(of: siblings[index], at: here) else { return nil }
            let ancestor = Ancestor(read: read, start: start, path: here, siblings: siblings)
            guard let found = caret(at: p, in: read.children, path: here, ancestors: ancestors + [ancestor]) else { return nil }
            if found != nil { return found }
        }
        return .some(nil)
    }

    /// Where a drawn caret at `path` sits in its paragraph; `.some(nil)` for an empty group that is none, nil on a failed read.
    private mutating func place(
        of path: [Int], among siblings: [Node], under ancestors: [Ancestor]
    ) -> UnreachableLines.Caret.Place?? {
        var drawn = false
        var index = path[path.count - 1]
        var level = siblings
        var levelPath = Array(path.dropLast())
        // Whether the empty group starts, and ends, each node from it up to this level.
        var atStart = true
        var atEnd = true
        var above = ancestors[...]
        while true {
            for (neighbour, touches) in [(index - 1, atStart), (index + 1, atEnd)]
            where touches && !drawn && level.indices.contains(neighbour) {
                guard let beside = read(level[neighbour], at: levelPath + [neighbour]) else { return nil }
                drawn = DrawnCaret.isCode(beside.subrole)
            }
            atStart = atStart && index == 0
            atEnd = atEnd && index == level.count - 1
            guard let parent = above.popLast(), parent.inline else { break }
            drawn = drawn || DrawnCaret.isCode(parent.read.subrole)
            index = parent.path[parent.path.count - 1]
            level = parent.siblings
            levelPath = Array(parent.path.dropLast())
        }
        guard drawn else { return .some(nil) }
        return .some(atStart ? .start : atEnd ? .end : .middle)
    }

    private mutating func start(of node: Node, at path: [Int]) -> Int? {
        if let known = starts[path] { return known }
        guard spend(2), let start = offset(node, false) else { return nil }
        starts[path] = start
        return start
    }

    private mutating func end(of node: Node, at path: [Int]) -> Int? {
        if let known = ends[path] { return known }
        guard spend(2), let end = offset(node, true) else { return nil }
        ends[path] = end
        return end
    }

    private mutating func read(_ node: Node, at path: [Int]) -> EmptyBlockScan<Node>.Block? {
        if let known = blocks[path] { return known }
        guard spend(1), let read = block(node) else { return nil }
        blocks[path] = read
        return read
    }

    private mutating func spend(_ count: Int) -> Bool {
        reads += count
        exhausted = reads > budget
        return !exhausted
    }
}
