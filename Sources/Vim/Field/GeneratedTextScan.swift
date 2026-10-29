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

    /// The page's generated text or a list marker holds all of `run`, in plain offsets: the leaf there, found by binary search
    /// on its siblings' starts; false on a failed read or past the budget.
    public mutating func generates(_ run: Range<Int>, in roots: [Node], offset: (Node, _ end: Bool) -> Int?) -> Bool {
        var siblings = roots
        for _ in 0..<16 {
            var holder: Node?
            var low = 0
            var high = siblings.count - 1
            while low <= high {
                let middle = (low + high) / 2
                reads += 1
                guard reads <= budget, let start = offset(siblings[middle], false) else { return false }
                if start <= run.lowerBound {
                    holder = siblings[middle]
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            reads += 2
            guard let holder, reads <= budget, let end = offset(holder, true), run.upperBound <= end,
                  let read = read(holder) else { return false }
            switch read.role {
            case "AXListMarker"?:
                return true
            case "AXStaticText"?:
                return read.id.map { $0 < 0 } ?? false
            default:
                guard !read.children.isEmpty else { return false }
                siblings = read.children
            }
        }
        return false
    }
}
