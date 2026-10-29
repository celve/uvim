// MARK: - Planning context

extension PhysicalPlanner {
    /// The predicted field: seeded from the snapshot, mutated as the plan is
    /// simulated. `selection == nil` means unknown; `selectionOpaque` means a
    /// selection exists on screen but its offsets are unknown (made blind).
    struct Context {
        var text: String?
        var selection: Range<Int>?
        var selectionOpaque = false
        var selectionWise: VisualKind?
        var anchor: Int?
        var nextSlot = 0

        /// Visual mode, whose selection is its own even where a block crossing left it no `anchor`.
        var visual = false

        /// The selection is lines that end the text, and a delete takes this line break above them too.
        var breakAbove: Range<Int>?

        /// The plan deletes lines that end the text.
        var collapsesToEnd = false

        /// Non-nil when the snapshot's selection is our drawn block cursor:
        /// the gap to collapse to before the plan acts.
        var cursorCollapse: Int?

        /// The last predicted edit's range, in field offsets — the one in flight if the plan dies.
        var operand: Range<Int>?

        /// Posted events not yet settled, which an AX write would overtake at the window server.
        var keysQueued = false

        /// Optional routes that missed at this field's rung, where counting takes over again (LIN-1686).
        var missed: Set<Route> = []

        mutating func queue(_ steps: [PhysicalStep]) {
            for step in steps {
                switch step {
                case .press, .typeText, .clipboardCut, .clipboardCopy, .clipboardInsert: keysQueued = true
                case .settle, .softSettle: keysQueued = false
                default: break
                }
            }
        }

        let webContent: Bool

        /// Everything else is in `AXValue` offsets; ranges leave for the field through these.
        var breaks: ParagraphBreaks?

        /// What the edits so far left settles unable to check.
        var unknown: Set<Unknown> = []

        enum Unknown {
            case selection, length, edge
        }

        /// `text` less `AXValue`, whose length settles check: the empty paragraphs put back, less the lines folded out.
        let valueGap: Int

        /// Emptying or filling a line changes which lines `AXValue` shows beside it.
        let reshapes: Bool

        var textlessLeaves = false

        /// ⇧⌃E may extend a folded write's selection to a line's end.
        let lineEndKey: Bool

        init(snapshot: FieldSnapshot) {
            text = snapshot.text
            lineEndKey = snapshot.capabilities.has(.lineEndKey)
            selection = snapshot.selection
            anchor = snapshot.anchor
            webContent = snapshot.webContent
            breaks = snapshot.breaks
            emptyParagraphCaret = snapshot.caretInEmptyParagraph ? snapshot.selection : nil
            textlessLeaves = snapshot.textlessLeaves
            valueGap = snapshot.valueGap - snapshot.foldedLength
            reshapes = snapshot.holdsEmptyParagraphs || snapshot.foldedLength > 0
            if snapshot.holdsChips || snapshot.holdsDrawnCaret { unknown.insert(.length) }
            drawnBreak = snapshot.drawnBreak
            if let caret = snapshot.selection?.lowerBound { startsInTable = inTable(caret) }
            if let cursor = snapshot.cursor, !cursor.isEmpty, cursor == snapshot.selection {
                // The engine plans from the collapsed gap, not the block.
                let gap = cursor.lowerBound
                selection = gap..<gap
                cursorCollapse = gap
            }
        }

        var model: TextModel? { text.map { TextModel($0, atoms: atoms, paragraphBreaks: breaks.map { Set($0.offsets) }) } }

        func field(_ range: Range<Int>) -> Range<Int> {
            breaks?.fieldRange(range) ?? range
        }

        /// The model holds folded text, where Linear lands a write by where the caret came from (LIN-1652).
        var folded: Bool { !(breaks?.hidden.allSatisfy(\.isBlock) ?? true) }

        /// A non-empty line's start with nothing folded at or beside it, where a write lands as where nothing is folded.
        func plainStart(_ offset: Int, in model: TextModel) -> Bool {
            // A stop folds no text, so a quote's first line after one takes a write as any paragraph's does.
            let folded = breaks?.hidden.contains { !$0.isBlock && (offset - 1...offset + 1).contains($0.at) } ?? false
            return model.lineBreak(of: offset) > offset && !folded
        }

        /// Chromium rich text, where a plain arrow at a Linear code span's edge can stay put (LIN-1683).
        var arrowsSelect: Bool { breaks != nil }

        /// The `<br>` after a caret Linear draws at a paragraph's end, which only a write before the caret moves meets.
        var drawnBreak: Int?

        /// Nothing has pressed or written yet, so the caret is still the snapshot's, wherever it came from.
        var unmoved = true

        /// `range` in field offsets as a write meets them: past that `<br>`, one more while it is there.
        func written(_ range: Range<Int>) -> Range<Int> {
            let written = field(range)
            guard let drawnBreak, let breaks else { return written }
            let end = breaks.valueOffsets(drawnBreak).lowerBound
            return (range.lowerBound > end ? written.lowerBound + 1 : written.lowerBound)
                ..< (range.upperBound > end ? written.upperBound + 1 : written.upperBound)
        }

        /// Model offsets of the chips, which keys cross in one step.
        var atoms: Set<Int> { breaks?.atoms ?? [] }

        /// Starts of lines right after a list, code block or quote's end, where a plain → ↓ from above or ↑ from them stops first.
        var gaps: Set<Int> { breaks?.gaps ?? [] }

        /// Each line's stops, top first: beside Linear's blocks and rules (LIN-1780).
        var stops: [Int: [Linear.Stop]] { breaks?.stops ?? [:] }

        /// Table lines, and the first lines of tables' last rows.
        var cells: Set<Int> { breaks?.cells ?? [] }
        var lastRows: Set<Int> { breaks?.lastRows ?? [] }

        /// Linear's keys over `text` from `position`, with this field's chips, stops and tables.
        func keys(_ text: String, at position: Int) -> KeyModel {
            KeyModel(
                text: text, anchor: position, focus: position, atoms: atoms, gaps: gaps, stops: stops, cells: cells,
                lastRows: lastRows
            )
        }

        func isAtom(_ offset: Int) -> Bool { breaks?.isAtom(offset) ?? false }

        /// A register's text for `range`, each chip's label whole and no line ending in invisible characters (LIN-1978).
        func content(_ range: Range<Int>, _ text: String) -> String {
            guard let model else { return breaks?.withAtoms(text, at: range) ?? text }
            return model.visibleParts(of: range).map { breaks?.withAtoms(model.substring($0), at: $0) ?? model.substring($0) }.joined()
        }

        /// The snapshot's caret when it is in an empty paragraph, which `AXValue` can leave out and read beside, so a
        /// key pressed from it can seem to do nothing when it did.
        let emptyParagraphCaret: Range<Int>?

        /// Typing over `range` would drop a break bounding an `<hr>` or a table cell, or a chip: no typed text rebuilds them.
        func retypesStructure(_ range: Range<Int>) -> Bool {
            textlessLeaves && (breaks?.offsets.contains { range.contains($0) } ?? false) || (breaks?.coversAtom(range) ?? false)
        }

        /// A caret here may be inside a code span's start; ←, ⌘← and writes land outside one at a paragraph's start.
        func normalizes(_ offset: Int) -> Bool {
            arrowsSelect && offset > 0 && edge(offset) != .paragraphStart
        }

        /// Which side of a paragraph boundary `offset` is on; nil off a boundary.
        func edge(_ offset: Int) -> Expectation.Edge? {
            guard let breaks else { return nil }
            let candidates = breaks.valueOffsets(breaks.fieldOffset(offset))
            guard candidates.count > 1 else { return nil }
            // Between two breaks is a line Chromium makes for a text-less or uneditable element, past the paragraph's end.
            return offset == candidates.lowerBound ? .paragraphEnd : .paragraphStart
        }

        /// The snapshot's caret was in a table.
        var startsInTable = false

        /// `offset` is on a table line.
        func inTable(_ offset: Int) -> Bool {
            guard let breaks, !breaks.cells.isEmpty, let model else { return false }
            return breaks.cells.contains(model.lineStart(of: model.clamp(offset)))
        }

        /// Every settle's expectation: a landing in `AXValue` offsets leaves in the field's, less what is unknown.
        func expectation(
            _ landing: Landing, blame: Expectation.Blame? = nil, selectedText: String? = nil,
            keeps: Int? = nil, within: Range<Int>? = nil, profile: CapabilityProfile
        ) -> Expectation {
            // Linear shows a table's controls as `AXValue` lines while the caret is in it, once keys brought it there.
            let at: Int?
            switch landing {
            case .exact(let range): at = range.upperBound
            case .caretAfter(let offset, _), .caretBefore(let offset, _): at = offset
            case .caretWithin(let range): at = range.lowerBound
            case .between: at = nil
            }
            let inTables = startsInTable || at.map(inTable) == true
            let length = profile.has(.readLength) && !unknown.contains(.length) && !inTables
                ? text.map { $0.utf16.count - valueGap } : nil
            // Without a landing no selection is read, so its edge and slots would check nothing.
            guard !unknown.contains(.selection) else {
                return Expectation(landing: nil, length: length, blame: blame, selectedText: selectedText)
            }
            let read: Landing
            var side: Expectation.Edge?
            switch landing {
            case .exact(let range):
                read = .exact(field(range))
                side = unknown.contains(.edge) ? nil : edge(range.upperBound)
            case .caretAfter(let o, let strict):
                read = .caretAfter(field(o..<o).lowerBound, strict: strict)
            case .caretBefore(let o, let strict):
                read = .caretBefore(field(o..<o).lowerBound, strict: strict)
            case .caretWithin(let range):
                let lower = field(range.lowerBound..<range.lowerBound).lowerBound
                read = .caretWithin(lower...max(lower, field(range.upperBound..<range.upperBound).lowerBound))
            case .between:
                read = landing
            }
            var expectation = Expectation(landing: read, length: length, edge: side, blame: blame, selectedText: selectedText)
            expectation.within = within.map(field)
            expectation.longest = expectation.within?.count
            expectation.keeps = keeps
            expectation.equivalences = equivalences
            return expectation
        }

        /// The folded markers and labels in field offsets, where a caret can read before one, the same place as after it.
        var equivalences: [Expectation.Equivalence] {
            guard let breaks else { return [] }
            return breaks.hidden.filter(\.isMarker).map { hidden in
                let end = breaks.fieldOffset(hidden.at)
                let start = end - hidden.text.utf16.count
                return Expectation.Equivalence(run: start..<end, afterBreak: start > 0)
            }
        }

        /// The model, but only where its geography is trustworthy.
        ///
        /// A block-scoped field's text is locally true and globally false:
        /// exact within the caret's block, a lie about everything past it.
        /// This cannot be folded into `model` — its consumers span three
        /// trust classes (geography, local content, staleness witnesses),
        /// and blanket-nilling would demote the field to lane C, killing
        /// `ciw`, `x`, `dw`, `f` and all register fidelity to fix a `j` bug.
        /// The trust decision is inherently per-destination.
        func model(for destination: LogicalStep.Destination, _ profile: CapabilityProfile) -> TextModel? {
            guard profile.has(.wholeDocument) || !PhysicalPlanner.isDocumentScoped(destination) else {
                return nil
            }
            return model
        }

        func model(for target: LogicalStep.SelectionTarget, _ profile: CapabilityProfile) -> TextModel? {
            guard profile.has(.wholeDocument) || !PhysicalPlanner.isDocumentScoped(target) else {
                return nil
            }
            return model
        }

        /// Line-counting work (`J`, linewise put) needs geography
        /// unconditionally — there is no line-local version of it.
        func linewiseModel(_ profile: CapabilityProfile) -> TextModel? {
            profile.has(.wholeDocument) ? model : nil
        }

        var position: Int? { selection?.lowerBound }
        var caret: Int? { selection.flatMap { $0.isEmpty ? $0.lowerBound : nil } }

        mutating func takeSlot() -> CaptureSlot {
            defer { nextSlot += 1 }
            return CaptureSlot(id: nextSlot)
        }

        /// Apply a predicted edit: text surgery, caret after the replacement.
        mutating func applyEdit(range: Range<Int>, replacement: String) {
            // An empty range is a plain insert, which replaces nothing.
            if !range.isEmpty { operand = field(range) }
            let before = model
            text = model?.replacing(range, with: replacement)
            if reshapes, !replacement.contains("\n"), let before, let after = model {
                let caret = range.lowerBound + replacement.utf16.count
                if before.touchesEmptyLine(range) || after.touchesEmptyLine(range.lowerBound..<caret) {
                    unknown.formUnion([.length, .edge])
                }
            }
            if let current = breaks {
                // Deleting a plain line into a list item leaves the item; otherwise the first line keeps its own.
                let ownRuns = current.hidden.filter { $0.at == range.lowerBound && $0.isStructure }
                let plainLine = replacement.isEmpty && ownRuns.isEmpty && before?.lineStart(of: range.lowerBound) == range.lowerBound
                let ownMarker = ownRuns.contains { !$0.text.isEmpty }
                let coversMarker = current.hidden.contains { range.lowerBound < $0.at && $0.at <= range.upperBound && $0.isMarker }
                let endsLine = model.map { $0.lineEnd(of: range.lowerBound) == range.lowerBound } ?? false
                breaks = current.replacing(range, with: replacement, keepingCovered: plainLine, endsLine: endsLine)
                // A typed `\n` may have made a paragraph or a line break.
                if replacement.contains("\n") { unknown.formUnion([.selection, .edge]) }
                // An item made or merged gains or loses `AXValue` lines, and its list renumbers.
                if current.hidden.contains(where: { !$0.isBlock }), replacement.contains("\n") || current.covers(range) {
                    unknown.insert(.length)
                }
                if coversMarker, !plainLine, !ownMarker { unknown.formUnion([.selection, .edge]) }
            }
            let caretAfter = range.lowerBound + replacement.utf16.count
            selection = caretAfter..<caretAfter
            selectionOpaque = false
        }

        /// The field did something we cannot predict (undo, blind typing).
        mutating func invalidate() {
            text = nil
            selection = nil
            selectionOpaque = false
        }
    }

    /// One settle per state-changing logical step, built from the prediction.
    ///
    /// `hard` follows an AX write: non-convergence aborts and rings. A blind
    /// action passes `hard: false` — the poll still runs as a barrier, but a
    /// mismatch is not a failure (the app, not us, decided what the keystroke
    /// did), so it proceeds instead of aborting the mode change behind it.
    static func settle(
        _ context: Context, profile: CapabilityProfile, hard: Bool = true,
        blame: Expectation.Blame? = nil, selectedText: String? = nil, route: Route? = nil, landing: Landing? = nil,
        deleting held: Expectation? = nil
    ) -> [PhysicalStep] {
        guard profile.has(.readCaret), let selection = context.selection else { return [] }
        var expectation = context.expectation(landing ?? .exact(selection), blame: blame, selectedText: selectedText,
                                              profile: profile)
        expectation.route = route
        expectation.deletes = held?.selection
        expectation.lengthBefore = held?.length
        return [hard ? .settle(expectation) : .softSettle(expectation)]
    }

    /// Chromium lands a write at a boundary on the next paragraph, so paragraph ends are reached by keys.
    static func write(_ range: Range<Int>, from current: Int? = nil, context: Context) -> [PhysicalStep] {
        if context.folded, let model = context.model {
            return foldedWrite(range, from: current, model: model, context: context)
        }
        let field = context.written(range)
        if !range.isEmpty, landsPast(range.lowerBound, context: context), let model = context.model {
            return [
                .setSelection(field.lowerBound..<field.lowerBound),
                .press(.left, count: 1),
                .press(.selectRight, count: model.graphemes(in: range)),
            ]
        }
        let step = PhysicalStep.setSelection(field)
        guard landsPast(range.upperBound, context: context) else { return [step] }
        return [step] + back(range.isEmpty, context: context)
    }

    /// A paragraph's end, whose write lands on the next paragraph, unless the `<br>` after a drawn caret still ends it.
    private static func landsPast(_ offset: Int, context: Context) -> Bool {
        context.edge(offset) == .paragraphEnd && context.field(offset..<offset).lowerBound != context.drawnBreak
    }

    /// From the next paragraph's start to this one's end, as a shifted ← and a collapse where a code span can take a plain ←.
    private static func back(_ caret: Bool, context: Context) -> [PhysicalStep] {
        guard caret else { return [.press(.selectLeft, count: 1)] }
        return context.arrowsSelect ? [.press(.selectLeft, count: 1), .press(.left, count: 1)] : [.press(.left, count: 1)]
    }

    /// Linear lands a write at a marker, checkbox or chip by where the caret was, so those boundaries are reached by keys (LIN-1652).
    private static func foldedWrite(
        _ range: Range<Int>, from current: Int? = nil, model: TextModel, context: Context
    ) -> [PhysicalStep] {
        guard range.isEmpty else {
            let ends = [range.lowerBound, range.upperBound]
            let needsKeys = { (end: Int) in
                context.isAtom(end) || model.lineBreak(of: end) == end
                    || model.lineStart(of: end) == end && !context.plainStart(end, in: model)
            }
            guard ends.contains(where: needsKeys) else { return [.setSelection(context.written(range))] }
            let placed = foldedWrite(range.lowerBound..<range.lowerBound, model: model, context: context)
            // A caret already at the start needs no write that takes arrows after it.
            return (current == range.lowerBound ? keyed(placed, or: [], context: context) : placed)
                + extending(range, model: model, context: context)
        }
        let caret = range.lowerBound
        let field = context.written(range)
        if context.isAtom(caret) {
            // Past the run of chips it starts, since each chip's end is the next one's start.
            var end = caret
            while context.isAtom(end) { end += 1 }
            let written = context.written(caret..<end).upperBound
            return [.setSelection(written..<written), .press(.left, count: end - caret)]
        }
        if context.breaks?.endsBeforeBreak(caret) ?? false {
            return [.setSelection(field.lowerBound - 1..<field.lowerBound - 1)]
        }
        let start = model.lineStart(of: caret)
        let end = model.lineBreak(of: caret)
        if caret == end, caret < model.length, start < caret {
            let inside = model.advance(caret, byGraphemes: -1)
            // A plain → from a code span's start only steps into it.
            return foldedWrite(inside..<inside, model: model, context: context)
                + run(.right, count: 1, selecting: context.arrowsSelect, normalizing: false)
        }
        // A line's start sharing its offset with the line above's end, as a to-do's does, takes a write from below there.
        if context.edge(caret) == .paragraphStart, field.lowerBound > 0, !context.plainStart(caret, in: model) {
            let inside = model.advance(caret, byGraphemes: 1)
            guard inside < end, !context.isAtom(inside) else {
                if context.caret == caret { return [] }
                if let from = context.caret, from < caret { return [.setSelection(field)] }
                // First above it, at a letter no line boundary shares, where no caret Linear draws brings a `<br>`.
                let above = letterAbove(caret, in: model) ?? 0
                return [.setSelection(context.written(above..<above)), .setSelection(field)]
            }
            // A caret written at a code span's end takes no ← or ⇧← next, and a collapse onto its start may stay inside.
            return [.setSelection(context.written(inside..<inside))]
                + run(.left, count: 1, selecting: context.arrowsSelect, normalizing: context.normalizes(caret))
        }
        guard landsPast(caret, context: context) else { return [.setSelection(field)] }
        return [.setSelection(field)] + back(true, context: context)
    }

    /// From a caret at `range`'s start to all of it, by ⇧⌃E over each line's rest it holds whole and ⇧→ elsewhere (LIN-1685).
    private static func extending(_ range: Range<Int>, model: TextModel, context: Context) -> [PhysicalStep] {
        guard context.lineEndKey else { return [.press(.selectRight, count: model.graphemes(in: range))] }
        let atoms = context.atoms
        var steps: [PhysicalStep] = []
        func press(_ chord: Chord, _ count: Int) {
            guard count > 0 else { return }
            guard case .press(chord, let earlier)? = steps.last else { return steps.append(.press(chord, count: count)) }
            steps[steps.count - 1] = .press(chord, count: earlier + count)
        }
        var at = range.lowerBound
        while at < range.upperBound {
            let end = model.lineBreak(of: at)
            let stop = min(end, range.upperBound)
            let graphemes = model.graphemes(in: at..<stop)
            // ⇧⌃E stops at a chip (LIN-1652), and over one character saves nothing.
            if stop == end, graphemes > 1, !atoms.contains(where: { (at..<end).contains($0) }) {
                press(Chord.paragraphEnd.shifted, 1)
            } else {
                press(.selectRight, graphemes)
            }
            guard stop < range.upperBound else { break }
            press(.selectRight, 1)
            at = model.advance(stop, byGraphemes: 1)
        }
        return steps
    }

    /// The last letter of the nearest line above `offset`'s with two or more, strictly inside it.
    private static func letterAbove(_ offset: Int, in model: TextModel) -> Int? {
        var end = model.lineStart(of: offset) - 1
        while end >= 0 {
            let start = model.lineStart(of: end)
            let last = model.advance(model.lineEnd(of: start), byGraphemes: -1)
            if last > start { return last }
            end = start - 1
        }
        return nil
    }

    /// To the caret at `start`, which the context predicts: ← lands a selection's start in every host measured (LIN-1532).
    static func collapse(to start: Int, context: Context, profile: CapabilityProfile) -> [PhysicalStep] {
        let keys = [.press(.left, count: 1)] + (context.normalizes(start) ? outside : [])
        // Settled, so a later AX write cannot overtake the ←; in a write lane `planning` settles before the next write.
        guard profile.has(.writeSelection) else { return keys + settle(context, profile: profile) }
        return keyed(write(start..<start, context: context), or: keys, context: context)
    }

    /// A folded field's write that needs arrows after it gives way to the key lane's `keys` where they press no more (LIN-1685).
    static func keyed(_ written: [PhysicalStep], or keys: [PhysicalStep], context: Context) -> [PhysicalStep] {
        context.folded && presses(written) && pressCount(keys) <= pressCount(written) ? keys : written
    }

    static func presses(_ steps: [PhysicalStep]) -> Bool {
        steps.contains { if case .press = $0 { return true }; return false }
    }

    static func pressCount(_ steps: [PhysicalStep]) -> Int {
        steps.reduce(0) { total, step in
            guard case .press(_, let count) = step else { return total }
            return total + count
        }
    }

    /// A misread caret puts keys and writes on other text while every offset reads back as planned (LIN-1533).
    static func checkSelectedText(
        _ text: String, context: Context, profile: CapabilityProfile
    ) -> [PhysicalStep] {
        guard !text.isEmpty, profile.has(.readSelectedText) else { return [] }
        // `AXSelectedText` omits paragraph breaks.
        let selected = context.selection.flatMap { selection in context.breaks?.fieldText(text, at: selection) } ?? text
        return settle(context, profile: profile, selectedText: selected)
    }
}
