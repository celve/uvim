/// What one walk over a Chromium field's tree finds, the field model's document (softlash/LIN-2329 field-model.md §5): its
/// empty paragraphs and its runs no caret reaches, from which `EmptyParagraphs.restore` and `UnreachableLines.fold` make the
/// text model and its breaks.
public struct FieldDocument: Equatable, Sendable {
    /// C6: ascending plain offsets of the `<br>`s of empty paragraphs that start a line; nil where the walk could not tell.
    public let emptyParagraphs: [Int]?
    /// The lines the text says are worth confirming, from the text with its empty paragraphs put back.
    public let candidates: UnreachableLines.Candidates
    /// C1, C2 and C4 runs, drawn carets and Linear's P1 stops and P2 labels; nil where the walk could not tell.
    public let found: UnreachableLines.Found?
    /// Which parts ran out of reads, rather than failing one.
    public let exhausted: Parts
    /// The reads the walk spent.
    public let reads: Int

    public struct Parts: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let emptyParagraphs = Parts(rawValue: 1)
        public static let found = Parts(rawValue: 2)
    }

    public init(
        emptyParagraphs: [Int]?, candidates: UnreachableLines.Candidates = UnreachableLines.Candidates(markers: [], chips: []),
        found: UnreachableLines.Found?, exhausted: Parts = [], reads: Int = 0
    ) {
        self.emptyParagraphs = emptyParagraphs
        self.candidates = candidates
        self.found = found
        self.exhausted = exhausted
        self.reads = reads
    }

    /// The most AX reads one walk may spend; the empty paragraphs, read first, may take only theirs of it, so the runs always
    /// get as many as before the two shared one walk.
    public static let readBudget = EmptyParagraphs.readBudget + UnreachableLines.readBudget

    /// What a snapshot asks the walk for: one field text, with what decides which of its lines are worth reading.
    public struct Request: Equatable, Sendable {
        public let value: String
        /// The raw marker text, U+FFFCs included.
        public let markers: String
        /// `value` aligned with the plain marker text.
        public let aligned: ParagraphBreaks
        /// A collapsed marker selection, in plain offsets.
        public let caret: Int?
        public let proseMirror: Bool
        /// The caret is read, so runs no caret reaches are folded out of the model.
        public let folds: Bool

        public init(value: String, markers: String, aligned: ParagraphBreaks, caret: Int?, proseMirror: Bool, folds: Bool) {
            self.value = value
            self.markers = markers
            self.aligned = aligned
            self.caret = caret
            self.proseMirror = proseMirror
            self.folds = folds
        }

        var plain: [UInt16] { Array(FieldReads.withoutAttachments(markers).utf16) }

        /// Nothing to read: no line break for an empty paragraph, and no line the text says to confirm.
        public var isIdle: Bool {
            !plain.contains(10) && (!folds || candidates(restoring: []).isEmpty)
        }

        /// The candidates in the text with `found`'s empty paragraphs put back, or in `value`'s lines where they do not fit.
        func candidates(restoring found: [Int]?) -> UnreachableLines.Candidates {
            let restored = found.flatMap {
                EmptyParagraphs.restore(value: value, fieldText: FieldReads.withoutAttachments(markers), aligned: aligned, found: $0)
            }
            return UnreachableLines.candidates(
                text: restored?.text ?? value, breaks: restored?.breaks ?? aligned, raw: markers, caret: caret,
                proseMirror: proseMirror
            )
        }

        /// Only the caret moved, to where `candidates` would gain nothing: none were, or it is beside no text-less leaf.
        func onlyMoved(from old: Request, candidates: UnreachableLines.Candidates) -> Bool {
            guard value == old.value, markers == old.markers, aligned == old.aligned, proseMirror == old.proseMirror,
                  folds == old.folds else { return false }
            guard caret != old.caret, folds, candidates.isEmpty, let caret else { return true }
            return UnreachableLines.leafCounts(markers)[caret] == nil
        }
    }

    /// The walk: the empty paragraphs first, then the runs among the lines they leave, both answered by `parts`.
    static func build(
        _ request: Request, emptyParagraphs: ([UInt16]) -> (found: [Int]?, exhausted: Bool),
        runs: (UnreachableLines.Candidates) -> (found: UnreachableLines.Found?, exhausted: Bool)
    ) -> FieldDocument {
        var exhausted: Parts = []
        var empty: [Int]? = []
        let plain = request.plain
        if plain.contains(10) {
            let walked = emptyParagraphs(plain)
            empty = walked.found
            if walked.exhausted { exhausted.insert(.emptyParagraphs) }
        }
        guard request.folds else { return FieldDocument(emptyParagraphs: empty, found: nil, exhausted: exhausted) }
        let candidates = request.candidates(restoring: empty)
        guard !candidates.isEmpty else {
            return FieldDocument(
                emptyParagraphs: empty, candidates: candidates, found: UnreachableLines.Found(markers: [], chips: []),
                exhausted: exhausted
            )
        }
        let walked = runs(candidates)
        if walked.exhausted { exhausted.insert(.found) }
        return FieldDocument(emptyParagraphs: empty, candidates: candidates, found: walked.found, exhausted: exhausted)
    }

    /// The walk over a tree, both parts reading through `tree`; `roots` is read once, where a part needs it.
    public static func walk<Node>(_ request: Request, roots: () -> [Node]?, tree: TreeReads<Node>) -> FieldDocument {
        var known: [Node]??
        func root() -> [Node]? {
            if known == nil { known = .some(roots()) }
            return known!
        }
        let document = build(request, emptyParagraphs: { plain in
            guard let blocks = root() else { return (nil, false) }
            tree.limit = min(tree.budget, EmptyParagraphs.readBudget - 2)
            var scan = EmptyBlockScan(tree: tree)
            return (scan.run(blocks: blocks, plain: plain), scan.exhausted)
        }, runs: { candidates in
            guard let blocks = root() else { return (nil, false) }
            tree.limit = tree.budget
            var scan = UnreachableScan(tree: tree)
            return (scan.run(blocks: blocks, candidates: candidates), scan.exhausted)
        })
        return FieldDocument(
            emptyParagraphs: document.emptyParagraphs, candidates: document.candidates, found: document.found,
            exhausted: document.exhausted, reads: tree.reads
        )
    }
}

public extension FieldDocument {
    /// The walk for one field text, kept until the text, its blocks or its roots change, or replayed across typing (LIN-1874).
    struct Memo: Equatable, Sendable {
        public let request: Request
        public let blocks: Int?
        /// The root blocks' identities, hashed with the containers the walk judged stops among, where read (LIN-1780).
        public let roots: Int?
        public let document: FieldDocument
        /// What the walk read, nil where none were kept.
        public let reads: Discovery.Reads?
        public let origin: Discovery.Origin

        public init(
            request: Request, blocks: Int?, roots: Int? = nil, document: FieldDocument, reads: Discovery.Reads? = nil,
            origin: Discovery.Origin = .walked(.first)
        ) {
            self.request = request
            self.blocks = blocks
            self.roots = roots
            self.document = document
            self.reads = reads
            self.origin = origin
        }

        public func holds(_ request: Request, blocks: Int?, roots: Int?) -> Bool {
            self.blocks == blocks && self.roots == roots && request.onlyMoved(from: self.request, candidates: document.candidates)
        }

        /// Itself while it holds, else its walk replayed across the one run typed since, or why the walk runs again.
        public func carried(_ request: Request, blocks: Int?, roots: Int?) -> Result<Memo, Discovery.Rewalk> {
            if holds(request, blocks: blocks, roots: roots) { return .success(self) }
            guard let blocks, self.blocks == blocks else { return .failure(.blocks) }
            guard self.roots == roots, roots != nil || !request.proseMirror else { return .failure(.roots) }
            let old = self.request
            // The caret came beside a text-less leaf where no line was worth confirming, or the asking changed.
            guard request.value != old.value || request.markers != old.markers, request.proseMirror == old.proseMirror,
                  request.folds == old.folds else { return .failure(.candidates) }
            return Discovery.run(markers: old.markers, value: old.value, to: request.markers, value: request.value).flatMap { edit in
                guard document.emptyParagraphs != nil || document.exhausted.contains(.emptyParagraphs),
                      document.found != nil || document.exhausted.contains(.found) || !request.folds
                else { return .failure(.failed) }
                guard let reads else { return .failure(.unread) }
                guard let lines = Discovery.Lines(value: old.value, markers: old.markers, shown: edit.shown) else {
                    return .failure(.boundary)
                }
                let replay = Discovery.Replay(reads.moved(across: edit.run, lines: lines))
                let tree = TreeReads<[Int]>(budget: reads.budget, block: replay.block, offset: replay.offset)
                let walked = FieldDocument.walk(request, roots: { replay.roots(blocks) }, tree: tree)
                // The page can make a paragraph a list item with one run of marker text, a change no kept read shows.
                guard document.candidates.carry(to: walked.candidates, across: edit.run, lines: lines) else {
                    return .failure(.candidates)
                }
                if let why = replay.refusal { return .failure(why) }
                return .success(Memo(
                    request: request, blocks: blocks, roots: roots, document: walked, reads: replay.reads,
                    origin: .shifted(edit.run)
                ))
            }
        }
    }
}

/// One walk's reads of a tree by path, each read once and counted against one budget.
public final class TreeReads<Node> {
    /// Nil when a read fails for any reason but the attribute's absence. One read.
    private let readBlock: (Node) -> EmptyBlockScan<Node>.Block?
    /// A node's plain offset from the field's start, at its start or its end; nil on a failed read. Two reads.
    private let readOffset: (Node, _ end: Bool) -> Int?
    public let budget: Int
    /// What the part reading now may spend in all, at most `budget`.
    var limit: Int {
        didSet { exhausted = reads > limit }
    }
    public private(set) var reads = 0
    /// The part reading now ran out of reads.
    public private(set) var exhausted = false

    private var blocks: [[Int]: EmptyBlockScan<Node>.Block] = [:]
    private var starts: [[Int]: Int] = [:]
    private var ends: [[Int]: Int] = [:]

    public init(
        budget: Int, block: @escaping (Node) -> EmptyBlockScan<Node>.Block?, offset: @escaping (Node, _ end: Bool) -> Int?
    ) {
        self.budget = budget
        limit = budget
        readBlock = block
        readOffset = offset
    }

    /// A part about to read `count` nodes it has none of yet may: false, and out of reads, past its limit.
    func affords(_ count: Int) -> Bool {
        exhausted = reads + count > limit
        return !exhausted
    }

    func read(_ node: Node, at path: [Int]) -> EmptyBlockScan<Node>.Block? {
        if let known = blocks[path] { return known }
        guard spend(1), let read = readBlock(node) else { return nil }
        blocks[path] = read
        return read
    }

    func start(of node: Node, at path: [Int]) -> Int? {
        if let known = starts[path] { return known }
        guard spend(2), let start = readOffset(node, false) else { return nil }
        starts[path] = start
        return start
    }

    func end(of node: Node, at path: [Int]) -> Int? {
        if let known = ends[path] { return known }
        guard spend(2), let end = readOffset(node, true) else { return nil }
        ends[path] = end
        return end
    }

    private func spend(_ count: Int) -> Bool {
        reads += count
        exhausted = reads > limit
        return !exhausted
    }
}
