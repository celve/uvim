/// The text a page generates in a field, which Chromium gives a negative node id as no DOM node backs it (LIN-1930).
public struct GeneratedTextScan<Node> {
    /// One node's role, `ChromeAXNodeId`, value and children, read together.
    public struct Read {
        public let role: String?
        public let id: Int?
        public let value: String?
        public let children: [Node]

        public init(role: String?, id: Int?, value: String? = nil, children: [Node] = []) {
            self.role = role
            self.id = id
            self.value = value
            self.children = children
        }
    }

    /// Nil on a failed read.
    private let read: (Node) -> Read?
    private let budget: Int
    public private(set) var reads = 0

    public init(budget: Int, read: @escaping (Node) -> Read?) {
        self.budget = budget
        self.read = read
    }

    /// The generated texts in tree order; nil at the page's own text or list marker, on a failed read, or past the budget.
    public mutating func run(roots: [Node]) -> [String]? {
        var texts: [String] = []
        var pending = Array(roots.reversed())
        while let node = pending.popLast() {
            reads += 1
            guard reads <= budget, let read = read(node) else { return nil }
            switch read.role {
            case "AXStaticText"?:
                guard let id = read.id, id < 0, let value = read.value else { return nil }
                texts.append(value)
            case "AXListMarker"?:
                return nil
            default:
                pending += read.children.reversed()
            }
        }
        return texts
    }

    /// The page's generated text or list markers hold all of `run`, in plain offsets: each leaf there, found by binary search on
    /// its siblings' starts; false on a failed read or past the budget.
    public mutating func generates(_ run: Range<Int>, in roots: [Node], offset: (Node, _ end: Bool) -> Int?) -> Bool {
        var from = run.lowerBound
        while from < run.upperBound {
            guard let end = generatedLeaf(at: from, in: roots, offset: offset), end > from else { return false }
            from = end
        }
        return true
    }

    /// The end of the generated leaf holding `start`; nil where the leaf there is the page's own.
    private mutating func generatedLeaf(at start: Int, in roots: [Node], offset: (Node, _ end: Bool) -> Int?) -> Int? {
        var siblings = roots
        for _ in 0..<16 {
            var holder: Node?
            var low = 0
            var high = siblings.count - 1
            while low <= high {
                let middle = (low + high) / 2
                reads += 1
                guard reads <= budget, let begins = offset(siblings[middle], false) else { return nil }
                if begins <= start {
                    holder = siblings[middle]
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            reads += 2
            guard let holder, reads <= budget, let end = offset(holder, true), start < end, let read = read(holder) else { return nil }
            switch read.role {
            case "AXListMarker"?:
                return end
            case "AXStaticText"?:
                return read.id.map { $0 < 0 } == true ? end : nil
            default:
                guard !read.children.isEmpty else { return nil }
                siblings = read.children
            }
        }
        return nil
    }
}
