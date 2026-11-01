/// What one walk over a Chromium field's tree finds, the field model's document (softlash/LIN-2329 field-model.md §5): its
/// plain text as runs of five kinds, and its blocks. `EmptyParagraphs.restore` and `UnreachableLines.fold` make the text model
/// and its breaks from `emptyParagraphs` and `found`, which are read off the runs and blocks.
public struct FieldDocument: Equatable, Sendable {
    /// In plain order; text, generated and atom runs and empty paragraphs' `<br>`s tile the plain text, leaves and stops take none.
    public let runs: [Run]
    public let blocks: [Block]
    /// The lines the text says are worth confirming, from the text with its empty paragraphs put back.
    public let candidates: UnreachableLines.Candidates
    /// Tree paths of the quotes and open sections whose children the stops were judged among, which the memo's witness reads.
    public let containers: [[Int]]
    /// The editor facts its stops and tables were read under, which select the field's `Navigation`.
    public let editor: EditorFacts
    /// The parts that could not tell what they read for: a read failed, the budget ran out, or they were not asked.
    public let unknown: Parts
    /// Which of those ran out of reads, rather than failing one.
    public let exhausted: Parts
    /// The reads the walk spent.
    public internal(set) var reads: Int

    public struct Parts: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let emptyParagraphs = Parts(rawValue: 1)
        public static let found = Parts(rawValue: 2)
    }

    /// A plain range of one kind, which the rule in its name made.
    public struct Run: Equatable, Sendable {
        public let range: Range<Int>
        public let kind: Kind

        public enum Kind: Equatable, Sendable {
            /// The page's own text, which a caret reaches.
            case text
            /// Text no caret enters: a C1 or C2 list marker, or a P2 code block's label.
            case generated(Generated)
            /// C4: a chip a caret crosses in one step, with its paragraph and the `<br>` Linear adds after one ending it.
            case atom(paragraph: Range<Int>)
            /// C5: a text-less object, one U+FFFC of the marker text, or the caret Linear draws at a code span's edge.
            case leaf(drawn: UnreachableLines.Caret.Place?)
            /// P1: a caret stop with no text before the line starting here; a join's kind is the fold's to tell from its leaves.
            case stop(Linear.Stop?)
        }

        public enum Generated: Equatable, Sendable {
            case marker
            case label
        }
    }

    public enum Block: Equatable, Sendable {
        /// C6: an empty paragraph, whose `<br>` is at this plain offset.
        case emptyParagraph(Int)
        case table(UnreachableLines.Table)
    }

    /// The document of `markers`, the raw marker text, from what each part of the walk found; nil where a part could not tell.
    public init(
        markers raw: String, emptyParagraphs: [Int]?, candidates: UnreachableLines.Candidates = UnreachableLines.Candidates(markers: [], chips: []),
        found: UnreachableLines.Found?, exhausted: Parts = [], reads: Int = 0
    ) {
        var placed: [Run] = []
        if let found {
            placed += found.markers.map { Run(range: $0, kind: .generated(.marker)) }
            placed += found.controls.map { Run(range: $0, kind: .generated(.label)) }
            placed += found.chips.map { Run(range: $0.range, kind: .atom(paragraph: $0.paragraph)) }
            placed += found.carets.map { Run(range: $0.offset..<$0.offset, kind: .leaf(drawn: $0.place)) }
            placed += found.joins.map { Run(range: $0..<$0, kind: .stop(nil)) }
            placed += found.stops.map { Run(range: $0.at..<$0.at, kind: .stop($0.kind)) }
        }
        let drawn = Dictionary(grouping: found?.carets ?? [], by: \.offset).mapValues(\.count)
        for (at, count) in UnreachableLines.leafCounts(raw).sorted(by: { $0.key < $1.key }) {
            let objects = max(count - (drawn[at] ?? 0), 0)
            placed += Array(repeating: Run(range: at..<at, kind: .leaf(drawn: nil)), count: objects)
        }
        let length = raw.utf16.count - UnreachableLines.leafCounts(raw).values.reduce(0, +)
        var covered = [Bool](repeating: false, count: length)
        for run in placed where !run.range.isEmpty {
            for unit in run.range where covered.indices.contains(unit) { covered[unit] = true }
        }
        for at in emptyParagraphs ?? [] where covered.indices.contains(at) { covered[at] = true }
        // A leaf or stop inside text splits it, so the runs read in order meet it where it is.
        let splits = Set(placed.filter(\.range.isEmpty).map(\.range.lowerBound))
        var start: Int?
        for unit in 0...length {
            if let open = start, unit == length || covered[unit] || splits.contains(unit) {
                placed.append(Run(range: open..<unit, kind: .text))
                start = nil
            }
            if unit < length, !covered[unit] { start = start ?? unit }
        }
        // Stable by where each starts, a stop or leaf before the text there, as the fold inserts stops in this order.
        runs = placed.enumerated().sorted {
            ($0.element.range.lowerBound, $0.element.range.isEmpty ? 0 : 1, $0.offset)
                < ($1.element.range.lowerBound, $1.element.range.isEmpty ? 0 : 1, $1.offset)
        }.map(\.element)
        blocks = (emptyParagraphs ?? []).map(Block.emptyParagraph) + (found?.tables ?? []).map(Block.table)
        self.candidates = candidates
        containers = found?.containers ?? []
        editor = found?.editor ?? []
        var unknown: Parts = []
        if emptyParagraphs == nil { unknown.insert(.emptyParagraphs) }
        if found == nil { unknown.insert(.found) }
        self.unknown = unknown
        self.exhausted = exhausted
        self.reads = reads
    }

    /// C6: ascending plain offsets of the `<br>`s of empty paragraphs that start a line; nil where the walk could not tell.
    public var emptyParagraphs: [Int]? {
        unknown.contains(.emptyParagraphs) ? nil : blocks.compactMap { if case .emptyParagraph(let at) = $0 { at } else { nil } }
    }

    /// The runs no caret reaches as the fold reads them; nil where the walk could not tell.
    public var found: UnreachableLines.Found? {
        guard !unknown.contains(.found) else { return nil }
        var markers: [Range<Int>] = [], controls: [Range<Int>] = [], chips: [UnreachableLines.Chip] = []
        var carets: [UnreachableLines.Caret] = [], joins: [Int] = [], stops: [UnreachableLines.Stop] = []
        for run in runs {
            switch run.kind {
            case .generated(.marker): markers.append(run.range)
            case .generated(.label): controls.append(run.range)
            case .atom(let paragraph): chips.append(UnreachableLines.Chip(range: run.range, paragraph: paragraph))
            case .leaf(let place?): carets.append(UnreachableLines.Caret(offset: run.range.lowerBound, place: place))
            case .stop(nil): joins.append(run.range.lowerBound)
            case .stop(let kind?): stops.append(UnreachableLines.Stop(at: run.range.lowerBound, kind: kind))
            case .text, .leaf(nil): break
            }
        }
        let tables = blocks.compactMap { if case .table(let table) = $0 { table } else { nil } }
        return UnreachableLines.Found(
            markers: markers, chips: chips, carets: carets, joins: joins, controls: controls, stops: stops, tables: tables,
            containers: containers, editor: editor
        )
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
        guard request.folds else {
            return FieldDocument(markers: request.markers, emptyParagraphs: empty, found: nil, exhausted: exhausted)
        }
        let candidates = request.candidates(restoring: empty)
        guard !candidates.isEmpty else {
            return FieldDocument(
                markers: request.markers, emptyParagraphs: empty, candidates: candidates,
                found: UnreachableLines.Found(markers: [], chips: []), exhausted: exhausted
            )
        }
        let walked = runs(candidates)
        if walked.exhausted { exhausted.insert(.found) }
        return FieldDocument(
            markers: request.markers, emptyParagraphs: empty, candidates: candidates, found: walked.found, exhausted: exhausted
        )
    }

    /// The walk over a tree, both parts reading through `tree`; `roots` is read once, where a part needs it.
    public static func walk<Node>(_ request: Request, roots: () -> [Node]?, tree: TreeReads<Node>) -> FieldDocument {
        var known: [Node]??
        func root() -> [Node]? {
            if known == nil { known = .some(roots()) }
            return known!
        }
        var document = build(request, emptyParagraphs: { plain in
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
        document.reads = tree.reads
        return document
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
                guard !document.unknown.subtracting(document.exhausted).contains(.emptyParagraphs),
                      !document.unknown.subtracting(document.exhausted).contains(.found) || !request.folds
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
