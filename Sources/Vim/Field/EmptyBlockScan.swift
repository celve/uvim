/// Finds a field's empty blocks from the `\n`s of its plain marker text, each a `<br>`: an empty block's, or a soft
/// break's in a block with text. Pure over its reads, so `make test` drives it with a fake tree (LIN-1612).
public struct EmptyBlockScan<Node> {
    /// One node's role, subrole and children, with its DOM classes, how many quotes it is in and whether the page generates it,
    /// read together.
    public struct Block {
        public let role: String?
        public let subrole: String?
        public let children: [Node]
        public let classes: [String]
        public let quoteLevel: Int
        /// Chromium gives the node a negative `ChromeAXNodeId`, as no DOM node backs it (LIN-1930).
        public let generated: Bool

        public init(
            role: String?, subrole: String?, children: [Node], classes: [String] = [], quoteLevel: Int = 0, generated: Bool = false
        ) {
            self.role = role
            self.subrole = subrole
            self.children = children
            self.classes = classes
            self.quoteLevel = quoteLevel
            self.generated = generated
        }
    }

    private let tree: TreeReads<Node>
    public var reads: Int { tree.reads }
    /// The scan failed by running out of reads, not on a read.
    public var exhausted: Bool { tree.exhausted }

    /// `block` is nil when a read fails for any reason but the attribute's absence, one read; `offset` a node's plain offset
    /// from the field's start, at its start or its end, nil on a failed read, two reads.
    public init(budget: Int, block: @escaping (Node) -> Block?, offset: @escaping (Node, _ end: Bool) -> Int?) {
        tree = TreeReads(budget: budget, block: block, offset: offset)
    }

    /// Reading through a walk's `tree`, which the scan shares with the runs' (LIN-2388).
    init(tree: TreeReads<Node>) {
        self.tree = tree
    }

    private enum Verdict {
        case line
        /// An empty list item's paragraph, which shares its marker's line.
        case item
        case text(end: Int)
    }

    /// Ascending plain offsets of the `<br>`s of empty blocks that start a line; nil on any failed read or past the budget.
    public mutating func run(blocks: [Node], plain: [UInt16]) -> [Int]? {
        let candidates = plain.indices.filter { plain[$0] == 10 }
        guard !candidates.isEmpty else { return [] }
        guard tree.affords(blocks.count) else { return nil }
        var found: [Int] = []
        for (index, node) in blocks.enumerated() {
            guard let read = tree.read(node, at: [index]) else { return nil }
            guard read.isEmptyBlock else { continue }
            guard let start = tree.start(of: node, at: [index]) else { return nil }
            if plain.indices.contains(start), plain[start] == 10 { found.append(start) }
        }
        // The rest are soft breaks or blocks nested in a quote, a table or a list.
        let known = Set(found)
        var covered = 0
        for b in candidates where b >= covered && !known.contains(b) {
            switch classify(b, in: blocks) {
            case nil: return nil
            case .line?: found.append(b)
            case .item?: break
            case .text(let end)?: covered = end
            }
        }
        return found.sorted()
    }

    /// Descends through the children holding plain offset `b`, found by binary search on their starts.
    private mutating func classify(_ b: Int, in blocks: [Node]) -> Verdict? {
        var siblings = blocks
        var path: [Int] = []
        var parent: String?
        for _ in 0..<16 {
            var low = 0
            var high = siblings.count - 1
            var hit: (index: Int, start: Int)?
            while low <= high {
                let middle = (low + high) / 2
                guard let start = tree.start(of: siblings[middle], at: path + [middle]) else { return nil }
                if start <= b {
                    hit = (middle, start)
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            guard let hit else { return .text(end: b + 1) }
            let node = siblings[hit.index]
            let here = path + [hit.index]
            guard let read = tree.read(node, at: here) else { return nil }
            if read.isEmptyBlock {
                guard hit.start == b else { return .text(end: b + 1) }
                // A caret drawn at a code span's end is followed by the `<br>` of the paragraph it ends (LIN-1683).
                if DrawnCaret.isCaret(parent: parent, previous: nil, next: nil) { return .text(end: b + 1) }
                guard hit.index > 0 else { return .line }
                guard let previous = tree.read(siblings[hit.index - 1], at: path + [hit.index - 1]) else { return nil }
                // After a chip it is the image Linear puts there while the caret is beside it (LIN-1652).
                let drawn = DrawnCaret.isCaret(parent: nil, previous: previous.subrole, next: nil)
                if previous.isChip || drawn { return .text(end: b + 1) }
                return previous.isListMarker ? .item : .line
            }
            if read.isLeaf {
                guard let end = tree.end(of: node, at: here) else { return nil }
                return .text(end: max(end, b + 1))
            }
            siblings = read.children
            path = here
            parent = read.subrole
        }
        return nil
    }
}
