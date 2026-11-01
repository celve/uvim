// MARK: - Lanes

extension PhysicalPlanner {
    /// A lane's answer for a step: its steps, `next` where it does not apply, or `reject`, which rings the plan.
    enum Lane {
        case steps([PhysicalStep])
        case next
        case reject

        func or(_ lane: () -> Lane) -> Lane {
            guard case .next = self else { return self }
            return lane()
        }

        /// A `lower*` function's answer: nil where a lane rejected, or where no lane applied.
        var lowered: [PhysicalStep]? {
            guard case .steps(let steps) = self else { return nil }
            return steps
        }
    }

    /// Whether a lane may repeat a key, a paste or a copy `count` times on the count alone: past the limit it does not apply.
    static func repeats(_ count: Int) -> Bool {
        count <= Count.repeatLimit
    }
}

// MARK: - Destinations

extension PhysicalPlanner {
    /// Never among the invisible characters ending a line, which are its break's (LIN-1978).
    static func resolve(_ destination: LogicalStep.Destination, model: TextModel, from position: Int) -> Int? {
        switch destination {
        case .motion(let motion, let count):
            return model.destination(of: motion, from: position, count: count).map(model.visibleOffset)
        case .offset(let offset):
            return model.visibleOffset(model.clamp(offset))
        case .mark(let point, let lineWise):
            guard model.isValid(point) else { return nil }   // stale mark: reject, never jump wrong
            return lineWise ? model.firstNonBlank(inLineOf: point.offset) : model.visibleOffset(model.clamp(point.offset))
        }
    }

    /// Lane B's actuator: exact target, dumb keys. Deterministic regardless
    /// of the app's column memory — vertical first, then home, then right.
    ///
    /// Its cross-line branch stays correct under a block-scoped field: this
    /// is only ever reached through a model that already passed the
    /// `wholeDocument` gate, so either the span is same-line or the block
    /// has real internal geography (a Notion code block).
    static func keyPath(from selection: Range<Int>, to: Int, model: TextModel, context: Context) -> [PhysicalStep] {
        let selecting = context.arrowsSelect
        // ← collapses a selection to its start from either end.
        var presses: [PhysicalStep] = selection.isEmpty ? [] : [.press(.left, count: 1)]
        let from = selection.lowerBound
        if !selection.isEmpty, context.normalizes(from) { presses += outside }
        guard from != to else { return presses }
        let fromLine = model.lineStart(of: from)
        let toLine = model.lineStart(of: to)
        if fromLine == toLine {
            let count = model.graphemes(in: min(from, to)..<max(from, to))
            return presses + run(to > from ? .right : .left, count: count, selecting: selecting, normalizing: context.normalizes(to))
        }
        if let walk = tableWalk(from: from, to: toLine, model: model, context: context) {
            presses += counted(walk)
            if context.normalizes(toLine) { presses += outside }
            let column = model.graphemes(in: toLine..<to)
            return column > 0 ? presses + run(.right, count: column, selecting: selecting, normalizing: false) : presses
        }
        let lines = model.newlineCount(in: min(fromLine, toLine)..<max(fromLine, toLine))
        // ↓ or ↑ across a line that starts after a block or rule a stop is beside stops there first.
        let way: KeyModel.Way = toLine > fromLine ? .down : .up
        let navigation = context.navigation
        let stops = context.stops.filter { min(fromLine, toLine) < $0.key && $0.key <= max(fromLine, toLine) }
            .values.reduce(0) { $0 + $1.filter { navigation.visits($0, way) }.count }
        presses.append(.press(toLine > fromLine ? .down : .up, count: lines + stops))
        // Past a rule ↓ lands at the textblock's start, where ⌘← or ⇧← would leave it for the rule above.
        var landing = context.keys(model.text, at: from)
        let vertical: Chord = toLine > fromLine ? .down : .up
        let placed = context.stops[toLine]?.last == .rule
            && (0..<(lines + stops)).allSatisfy { _ in landing.press(vertical) } && landing.focus == toLine && !landing.inGap
        if !placed {
            presses.append(.press(.lineStart, count: 1))
            if context.normalizes(toLine) { presses += outside }
        }
        let column = model.graphemes(in: toLine..<to)
        if column > 0 {
            presses += run(.right, count: column, selecting: selecting, normalizing: false)
        }
        return presses
    }

    /// ↓ and ↑ go by rows in a table, so lane B crosses one line by line as `j` and `k` do, ⌘→ and ⌘← for ⌃E and ⌃A, from
    /// `from` to the start of the line `toLine`; nil where no table line is crossed or the key model cannot follow the walk.
    private static func tableWalk(from: Int, to toLine: Int, model: TextModel, context: Context) -> [Chord]? {
        let fromLine = model.lineStart(of: from)
        let low = min(fromLine, toLine), high = max(fromLine, toLine)
        guard context.cells.contains(where: { low <= $0 && $0 <= high }) else { return nil }
        let navigation = context.navigation
        let noKeys = CapabilityProfile(available: [])
        func lineKeys(_ chords: [Chord]) -> [Chord] {
            chords.map { $0 == .paragraphEnd ? Chord.lineEnd : $0 == .paragraphStart ? .lineStart : $0 }
        }
        var keys = context.keys(model.text, at: from)
        var walk: [Chord] = []
        if toLine < fromLine {
            walk = lineKeys([.paragraphStart] + navigation.upward(
                from: fromLine, count: model.newlineCount(in: low..<high), model: model, stops: context.stops,
                cells: context.cells, lastRows: context.lastRows, profile: noKeys
            ).chords)
            guard walk.allSatisfy({ keys.press($0) }) else { return nil }
        }
        var line = fromLine
        while line < toLine {
            let next = model.lineBreak(of: line) + 1
            if context.cells.contains(line), !context.cells.contains(next) {
                // Chromium's own → out of a table's last cell can land before the table (LIN-2389), where ↓ leaves it below.
                let crossed = (context.stops[next] ?? []).filter { navigation.visits($0, .down) }.count
                walk += Array(repeating: .down, count: crossed + 1) + (context.stops[next]?.last == .rule ? [] : [.lineStart])
                keys = context.keys(model.text, at: next)
            } else {
                let hop = lineKeys([.paragraphEnd] + (navigation.hops(
                    from: line, count: 1, model: model, stops: context.stops, cells: context.cells, profile: noKeys
                ).first ?? []))
                walk += hop
                guard hop.allSatisfy({ keys.press($0) }), keys.focus == next, !keys.inGap else { return nil }
            }
            line = next
        }
        guard keys.focus == toLine, !keys.inGap else { return nil }
        return walk
    }

    /// `arrows` as presses; a run inside one grapheme presses nothing.
    static func run(_ arrow: Chord, count: Int, selecting: Bool, normalizing: Bool) -> [PhysicalStep] {
        selecting && count > 0 ? counted(arrows(arrow, count: count, selecting: true, normalizing: normalizing))
            : [.press(arrow, count: count)]
    }

    /// `count` arrows, or shifted ones and a collapse no code edge holds up, leftward stepping out of a span it starts.
    static func arrows(_ arrow: Chord, count: Int, selecting: Bool, normalizing: Bool) -> [Chord] {
        guard selecting else { return Array(repeating: arrow, count: count) }
        let run = Array(repeating: arrow.shifted, count: count) + [arrow]
        return arrow == .left && normalizing ? run + [.selectLeft, .right] : run
    }

    /// ⇧← then →, which leaves a caret where it was, outside a code span it starts (LIN-1683).
    static let outside: [PhysicalStep] = [.press(.selectLeft, count: 1), .press(.right, count: 1)]

    /// What goes before ⇧→ or ⇧⌃E from `caret`; at a paragraph's start only ⇧⌃E sticks, and ⌃A or ⇧→ ← lands outside.
    static func outside(before chord: Chord, at caret: Int, context: Context, profile: CapabilityProfile) -> [PhysicalStep]? {
        guard context.arrowsSelect, [.selectRight, Chord.paragraphEnd.shifted].contains(chord) else { return nil }
        guard caret == 0 || context.edge(caret) == .paragraphStart else { return outside }
        guard chord != .selectRight, let model = context.model, model.lineBreak(of: caret) > caret else { return nil }
        return profile.has(.lineStartKey) ? [.press(.paragraphStart, count: 1)]
            : [.press(.selectRight, count: 1), .press(.left, count: 1)]
    }

    /// One press per run of the same chord.
    static func counted(_ chords: [Chord]) -> [PhysicalStep] {
        var steps: [PhysicalStep] = []
        for chord in chords {
            if case .press(chord, let count)? = steps.last {
                steps[steps.count - 1] = .press(chord, count: count + 1)
            } else {
                steps.append(.press(chord, count: 1))
            }
        }
        return steps
    }

    /// Does resolving this need the model to describe geography beyond the
    /// caret's line?
    ///
    /// Classified by **intent**, not by whether a given resolution happens
    /// to cross a line. `TextModel` classes `\n` as whitespace, so `w`/`b`/
    /// `e` walk across lines — but only incidentally, and inside a block
    /// they are exact, so they stay on the model. `j` is *defined* by the
    /// crossing, so it cannot. At a block boundary `w` merely stalls: a
    /// degradation, not a wrong action.
    private static func isDocumentScoped(_ motion: Motion) -> Bool {
        switch motion {
        case .line(.up, _), .line(.down, _), .displayLine:
            return true
        case .fileStart, .fileEnd, .search:
            return true
        case .paragraph, .sentence, .section, .page, .scrollLine, .screenLine:
            return true
        default:
            // character, word, find, lineStart, lastNonBlank, column,
            // matchingItem, repeatFind, mark, custom — line-local, or
            // resolved away before they reach here.
            return false
        }
    }

    static func isDocumentScoped(_ destination: LogicalStep.Destination) -> Bool {
        switch destination {
        case .motion(.lineEnd, let count):
            return count > 1   // `2$` walks a line down first
        case .motion(let motion, _):
            return isDocumentScoped(motion)
        case .offset, .mark:
            // Absolute offsets against a block-relative model are a category
            // error: `gi` has no staleness witness at all, and a wrong-block
            // jump followed by Insert is the worst failure available.
            return true
        }
    }

    static func isDocumentScoped(_ target: LogicalStep.SelectionTarget) -> Bool {
        switch target {
        case .span(let destination, _):
            return isDocumentScoped(destination)
        case .lineSpan:
            return true
        case .lines(let count, _):
            // `dd` stays exact: blind would select across a block boundary
            // unpredictably AND lose register fidelity. Emptying the block
            // is the lesser, predictable wrong.
            return count > 1
        case .remembered:
            return true   // absolute offsets
        case .textObject, .toLineEnd, .current:
            return false
        }
    }

    /// Lane C's chord table. `counted` is false where repetition is
    /// meaningless (line ends, document ends).
    static func blindMoveChord(_ motion: Motion) -> (chord: Chord, counted: Bool)? {
        switch motion {
        case .character(.left): return (.left, true)
        case .character(.right): return (.right, true)
        case .line(.down, _): return (.down, true)
        case .line(.up, _): return (.up, true)
        case .word(.forward, _, _): return (.wordRight, true)
        case .word(.backward, _, _): return (.wordLeft, true)
        case .lineStart: return (.lineStart, false)
        case .lineEnd, .lastNonBlank: return (.lineEnd, false)
        case .fileStart: return (.documentStart, false)
        case .fileEnd: return (.documentEnd, false)
        default: return nil
        }
    }

    static func lowerMove(
        _ destination: LogicalStep.Destination,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        appMove(destination, context: &context, profile: profile)
            .or { exactMove(destination, context: &context, profile: profile) }
            .or { blindMove(destination, context: &context) }
            .lowered
    }

    /// Lanes 2 and 3, which share the model's target: native keys where they reach it, else lane A or B.
    private static func exactMove(
        _ destination: LogicalStep.Destination, context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard let model = context.model(for: destination, profile), let selection = context.selection else {
            return .next
        }
        guard let target = resolve(destination, model: model, from: selection.lowerBound) else { return .reject }
        let written = profile.has(.writeSelection) ? write(target..<target, context: context) : nil
        let keyed: Lane
        if let written {
            keyed = lineKey(destination, to: target, instead: written, model: model, context: &context, profile: profile)
        } else {
            keyed = nativeMove(destination, to: target, model: model, context: &context, profile: profile).or {
                sameLine(to: target, model: model, context: &context, profile: profile)
            }
        }
        return keyed.or {
            let actuation = written ?? keyPath(from: selection, to: target, model: model, context: context)
            context.selection = target..<target
            context.selectionOpaque = false
            return .steps(actuation + settle(context, profile: profile))
        }
    }

    /// A folded field's write reaches a line's start or end only with arrows after it, where ⌃A or ⌃E may need none (LIN-1685).
    private static func lineKey(
        _ destination: LogicalStep.Destination, to target: Int, instead written: [PhysicalStep], model: TextModel,
        context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        switch destination {
        case .motion(.lineStart, _), .motion(.lineEnd, 1): break
        default: return .next
        }
        guard context.folded, presses(written) else { return .next }
        var keyed = context
        guard case .steps(let keys) = nativeMove(destination, to: target, model: model, context: &keyed, profile: profile),
              pressCount(keys) <= pressCount(written) else { return .next }
        context = keyed
        return .steps(keys)
    }

    private static func blindMove(_ destination: LogicalStep.Destination, context: inout Context) -> Lane {
        guard case .motion(let motion, let count) = destination,
              let blind = blindMoveChord(motion), !blind.counted || repeats(count) else { return .next }
        context.selection = nil
        context.selectionOpaque = false
        return .steps([.press(blind.chord, count: blind.counted ? count : 1)])
    }
}
