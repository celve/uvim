// MARK: - The learner

public extension Sim {
    /// The Controller's learner for one field.
    struct Learner: Equatable, Sendable {
        public var store: BeliefStore
        public var rung: String
        public var versions: Versions
        public var chromium: Bool
        public var probed: CapabilityProfile
        public var config: [Capability: ConfigChoice] = [:]
        public var sampling = OffsetsSampling()
        public var tally = Tally()
        public var strikes = Strikes()
        public internal(set) var resolved: ResolvedBeliefs?
        /// What each snapshot's reads said.
        public internal(set) var evidence: [Evidence] = []
        public internal(set) var lessons: [Learning.Lesson] = []

        public init(
            store: BeliefStore = BeliefStore(), rung: String = "sim|role:AXTextArea", versions: Versions = Versions(app: "1"),
            chromium: Bool = false, probed: CapabilityProfile
        ) {
            self.store = store
            self.rung = rung
            self.versions = versions
            self.chromium = chromium
            self.probed = probed
            // A policy the profile leaves out is seeded off, as `nativeMotions` is everywhere.
            for policy in Capability.allCases where policy.species == .policy && !probed.has(policy) {
                config[policy] = ConfigChoice(seededOff: true)
            }
        }

        public var model: ReadModel { resolved?.readModel ?? ReadModel(answer: chromium ? .textContent : .value) }
    }
}

extension Sim {
    /// The fake field's reads, which the learner observes here.
    mutating func read() -> (reads: FieldSnapshot.Reads, observed: Learning.Observation) {
        let (current, source) = learner.map { $0.model.reading(chromium: $0.chromium, children: hasChildren) }
            ?? (readModel, .start)
        let plain = readSelection
        var sampled = false
        var reads = FieldSnapshot.Reads(
            field: FieldReads(text: shownValue, plain: plain, selectedText: readSelectedText), length: fieldLength,
            webContent: webContent || self.reads != nil || emptyParagraphs, blocks: blocks
        )
        reads.roots = roots
        reads.proseMirror = listLines != nil
        if showsPlaceholder {
            // What the Snapshotter makes of a field its scan finds shows only generated text (LIN-1930).
            reads = FieldSnapshot.Reads(
                generatedOnly: FieldReads(text: shownValue, plain: plain, selectedText: readSelectedText), length: fieldLength,
                webContent: reads.webContent, blocks: blocks, markers: (markers || emptyParagraphs) && current != .value
            )
        } else if emptyParagraphs {
            let value = chromium.shown.value
            let text = chromium.shown.markers + (endsInTextlessLeaf ? "\u{FFFC}" : "")
            var memo: EmptyParagraphs.Memo?
            var unreachable: UnreachableLines.Memo?
            let aligned = FieldSnapshot.Step.run(taking: { take($0, into: &reads, memo: &memo, unreachable: &unreachable) }) {
                MarkerReads.aligning(value: value, range: plain, text: text, sides: reads.sides)
            }
            reads.field = FieldReads(text: value, plain: plain, selectedText: readSelectedText, markers: aligned.reads)
            reads.marked = plain
            reads.markerText = aligned.text
        } else {
            sampled = current == .value && source.observes && learner?.sampling.samples(text: text, plain: plain) == true
            if markers && (current != .value || sampled) { reads.field.markers = markerReads }
        }
        let field = reads.field
        var observed = Learning.Observation(before: current, source: source)
        if var learner {
            observed = Learning.observe(field, before: current, source: source, newEngine: learner.model.newEngine)
            if sampled { learner.sampling.sampled(markers: markers, evidence: observed.evidence, text: text, plain: plain) }
            if let evidence = observed.evidence {
                learner.tally.count(evidence)
                learner.evidence.append(evidence)
            }
            self.learner = learner
        }
        return (reads, observed)
    }

    /// Answers a step's read from the fake field, as `Snapshotter` does over AX.
    func take(
        _ need: FieldSnapshot.Need, into reads: inout FieldSnapshot.Reads, memo: inout EmptyParagraphs.Memo?,
        unreachable: inout UnreachableLines.Memo?
    ) {
        switch need {
        case .side(let end):
            reads.sides.updateValue(chromium.side(end == .upper ? selection.upperBound : selection.lowerBound), forKey: end)
        case .emptyParagraph:
            reads.inEmptyParagraph = chromium.inEmptyParagraph(selection)
        case .emptyParagraphs(let value, let markers, let why):
            let found = findsEmptyParagraphs ? chromium.shown.found : nil
            memo = EmptyParagraphs.Memo(value: value, markers: markers, blocks: blocks, found: found, origin: .walked(why))
        case .unreachable(let value, let markers, let candidates, let why):
            let shown = chromium
            let found = findsUnreachable ? UnreachableLines.Found(
                markers: candidates.markers.map(\.lowerBound).filter(Set(shown.listMarkers).contains),
                chips: shown.chips.filter { chip in
                    candidates.chips.contains { $0.lowerBound == chip.range.lowerBound && chip.range.upperBound <= $0.upperBound }
                },
                carets: shown.drawnCaret.map { candidates.carets.contains($0.offset) ? [$0] : [] } ?? [],
                joins: shown.joins, controls: shown.controls, stops: shown.stops, tables: shown.tables
            ) : nil
            unreachable = UnreachableLines.Memo(
                value: value, markers: markers, blocks: blocks, roots: roots, found: found, origin: .walked(why)
            )
        }
    }

    /// `AXValue`.
    var shownValue: String {
        if showsPlaceholder, let placeholder { return placeholder }
        return emptyParagraphs ? chromium.shown.value : text
    }

    /// `kAXNumberOfCharacters`: `AXValue`'s length.
    var fieldLength: Int { shownValue.utf16.count }

    /// The child count: a block per paragraph.
    var blocks: Int { hasChildren ? text.utf16.filter { $0 == 10 }.count + 1 : 0 }

    /// The roots by identity: a line whose block changes kind is a new root, though the text and the count stay.
    var roots: Int? {
        listLines.map { lines in
            var hasher = Hasher()
            hasher.combine(lines)
            return hasher.finalize()
        }
    }

    var chromium: ChromiumParagraphs {
        let caret = selection.isEmpty ? selection.lowerBound : nil
        let drawn = drawsLate && snapshotting ? nil
            : caret.flatMap { isCodeEdge($0, start: true) || isCodeEdge($0, start: false) ? $0 : nil }
        return ChromiumParagraphs(text: text, lines: listLines, caret: caret, drawn: drawn)
    }

    /// What the caret Linear draws adds to `fieldLength`, which a settle leaves out.
    var drawnLength: Int {
        let shown = chromium
        guard shown.drawnCaret != nil else { return 0 }
        return shown.shown.value.utf16.count
            - ChromiumParagraphs(text: text, lines: listLines, caret: selection.lowerBound).shown.value.utf16.count
    }

    /// The upper end's paragraph side from the Sim's own text, in every Chromium mode.
    var upperSide: ParagraphBreaks.Side? {
        reads != nil || markers || emptyParagraphs ? ChromiumParagraphs.side(selection.upperBound, in: text) : nil
    }

    var markerReads: MarkerReads {
        guard !showsPlaceholder else { return MarkerReads(breaks: ParagraphBreaks(), value: readSelection) }
        return MarkerReads(
            breaks: ParagraphBreaks(value: text, fieldText: text.filter { $0 != "\n" }), value: selection,
            textlessLeaves: endsInTextlessLeaf
        )
    }

    mutating func learn(from observed: Learning.Observation) {
        // The controller's: a run the focus left teaches nothing.
        guard var learner, departure == nil else { return }
        if observed.source.observes {
            for item in attribution.evidence { learner.tally.count(item) }
        }
        if let route = attribution.missedRoute {
            learner.strikes.miss(route, judgedUnder: observed.after, app: learner.versions.app)
        }
        let config = learner.config
        let lesson = Learning.learn(
            store: &learner.store, strikes: &learner.strikes, rung: learner.rung, versions: learner.versions,
            model: learner.model, observed: observed, run: attribution.evidence,
            overridden: { config[$0]?.override != nil }, provenance: Provenance(), tally: learner.tally
        )
        learner.lessons.append(lesson)
        self.learner = learner
        if lesson.republish { resolveBeliefs() }
    }

    mutating func resolveBeliefs() {
        guard var learner else { return }
        let resolved = learner.store.resolve(
            rungs: [learner.rung], rung: learner.rung, versions: learner.versions, chromium: learner.chromium,
            children: hasChildren, userPinsOffsets: learner.config[.readCaret]?.override != nil
        )
        learner.resolved = resolved
        profile = CapabilityResolver.resolve(probed: learner.probed, config: learner.config, beliefs: resolved).profile
        self.learner = learner
    }
}
