// MARK: - Native keys

extension PhysicalPlanner {
    /// Chords pressed together, then one settle; a group that blames a key holds that key alone.
    typealias KeyGroup = (chords: [Chord], blame: Capability?)

    /// Moves by native line and document keys, counting only the column; `next` where lane B counts it all.
    static func nativeMove(
        _ destination: LogicalStep.Destination?, to target: Int, model: TextModel,
        context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard let position = context.position else { return .next }
        let line = model.lineStart(of: position)
        let targetLine = model.lineStart(of: target)
        let stops = context.stops
        let cells = context.cells
        let lastRows = context.lastRows
        let shape = context
        // Linear's stops and tables take keys of their own; any other field's line takes → down, or ← and ⌃A up.
        let linear = !stops.isEmpty || !cells.isEmpty
        func hops(_ count: Int) -> [[Chord]] {
            linear ? Linear.hops(from: line, count: count, model: model, stops: stops, cells: cells, profile: profile)
                : Array(repeating: [.right], count: count)
        }
        func upward(_ count: Int) -> (chords: [Chord], endsLeft: Bool) {
            linear ? Linear.upward(from: line, count: count, model: model, stops: stops, cells: cells, lastRows: lastRows,
                                   profile: profile)
                : (repeated([.left, .paragraphStart], count), count > 0)
        }
        // The way to the target's line, and for `j`/`k` an optional one to its end; the column is counted from where each lands.
        var way: [KeyGroup]
        var end: (way: [KeyGroup], route: Route)?
        switch destination {
        case .motion(.lineStart, _)?:
            guard profile.has(.lineStartKey) else { return .next }
            way = [([.paragraphStart], .lineStartKey)]
        case .motion(.lineEnd, let count)?:
            guard profile.has(.lineEndKey), repeats(count) else { return .next }
            way = [([.paragraphEnd], .lineEndKey), (hops(count - 1).flatMap { $0 + [.paragraphEnd] }, nil)]
        case .motion(.fileStart, _)?:
            guard profile.has(.documentStartKey) else { return .next }
            way = [([.documentStart], .documentStartKey)]
        case .motion(.fileEnd, _)?:
            guard profile.has(.documentEndKey), profile.has(.lineStartKey) else { return .next }
            way = [([.documentEnd], .documentEndKey), ([.paragraphStart], .lineStartKey)]
        default:
            // `j`/`k` press their key even where the caret stays put, so a settle checks the line they start from.
            var vertical: Direction?
            if case .motion(.line(let direction, _), _)? = destination { vertical = direction }
            guard targetLine != line || vertical != nil else { return .next }
            if targetLine > line || vertical == .down {
                guard profile.has(.lineEndKey) else { return .next }
                let lines = model.newlineCount(in: line..<targetLine)
                let down = hops(lines).enumerated().flatMap { ($0.offset > 0 ? [Chord.paragraphEnd] : []) + $0.element }
                way = [([.paragraphEnd], .lineEndKey), (down, nil)]
                if lines > 0, !context.missed.contains(.lineEnd) {
                    end = ([([.paragraphEnd], .lineEndKey), (down + [.paragraphEnd], nil)], .lineEnd)
                }
            } else {
                guard profile.has(.lineStartKey) else { return .next }
                let lines = model.newlineCount(in: targetLine..<line)
                let up = upward(lines)
                way = [([.paragraphStart], .lineStartKey), (up.chords, nil)]
                // The last ← already lands at the line's end.
                if lines > 0, up.endsLeft, !context.missed.contains(.lineStart) {
                    end = ([([.paragraphStart], .lineStartKey), (Array(up.chords.dropLast()), nil)], .lineStart)
                }
            }
        }
        let selecting = context.arrowsSelect
        let normalizing = context.normalizes(target)
        // Only the column is counted, in its own settle so the line the field reports decides it.
        func counted(_ way: [KeyGroup]) -> [KeyGroup]? {
            var landing = shape.keys(model.text, at: position)
            guard way.flatMap(\.chords).allSatisfy({ landing.press($0) }),
                  model.lineStart(of: landing.focus) == targetLine else { return nil }
            let reached = landing.focus
            let column = model.graphemes(in: min(reached, target)..<max(reached, target))
            return way + [(column > 0 ? arrows(target > reached ? .right : .left, count: column, selecting: selecting,
                                               normalizing: normalizing) : [], nil)]
        }
        guard var groups = counted(way) else { return .next }
        var route: Route?
        // From the line's end only where that presses fewer keys, which a walk from the target no longer than them shows.
        let presses = groups.flatMap(\.chords).count
        if let end, model.graphemes(from: target, toLineEnd: true, atMost: presses - end.way.flatMap(\.chords).count - 1) != nil,
           let fromEnd = counted(end.way), fromEnd.flatMap(\.chords).count < presses {
            (groups, route) = (fromEnd, end.route)
        }
        return pressing(groups, to: target..<target, context: &context, profile: profile, route: route)
    }

    /// An optional route: ⌃A or ⌃E, then arrows to a target on the caret's line, where that presses fewer keys than counting.
    static func sameLine(to target: Int, model: TextModel, context: inout Context, profile: CapabilityProfile) -> Lane {
        guard !profile.has(.writeSelection), let position = context.position else { return .next }
        let low = min(position, target), high = max(position, target)
        guard model.newlineCount(in: low..<high) == 0 else { return .next }
        let selecting = context.arrowsSelect
        let normalizing = context.normalizes(target)
        func presses(_ arrow: Chord, _ count: Int) -> Int {
            count > 0 ? count + arrows(arrow, count: 0, selecting: selecting, normalizing: normalizing).count : 0
        }
        let toward: Chord = target > position ? .right : .left
        let counting = presses(toward, model.graphemes(in: low..<high))
            + prefixCount(selecting ? toward.shifted : toward, context: context, profile: profile)
        // The line key and then fewer arrows than counting presses, which bounds the walk from the target.
        let limit = counting - 2
        var best: (key: Chord, route: Route, back: Chord, count: Int)?
        for (key, needs, route, back) in [(Chord.paragraphStart, Capability.lineStartKey, Route.lineStart, Chord.right),
                                          (.paragraphEnd, .lineEndKey, .lineEnd, .left)] {
            guard profile.has(needs), !context.missed.contains(route),
                  let count = model.graphemes(from: target, toLineEnd: back == .left, atMost: limit),
                  presses(back, count) <= limit, best.map({ presses(back, count) < presses($0.back, $0.count) }) ?? true
            else { continue }
            best = (key, route, back, count)
        }
        guard let best else { return .next }
        let run = best.count > 0 ? arrows(best.back, count: best.count, selecting: selecting, normalizing: normalizing) : []
        return pressing([([best.key] + run, nil)], to: target..<target, context: &context, profile: profile, route: best.route)
    }

    /// How many keys `planning` puts before `chord` when it is the plan's first actuation, from the caret the snapshot saw.
    static func prefixCount(_ chord: Chord, context: Context, profile: CapabilityProfile) -> Int {
        guard context.unmoved, let caret = context.caret else { return 0 }
        return outside(before: chord, at: caret, context: context, profile: profile)?.count ?? 0
    }

    /// Line-shaped selections by native keys, as many as the command counts, since keys past the end do nothing;
    /// `next` where lane B counts them, as it does past the repeat limit.
    static func nativeSelect(
        _ target: LogicalStep.SelectionTarget, range: Range<Int>,
        context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard !profile.has(.writeSelection) else { return .next }
        let groups: [KeyGroup]
        switch target {
        case .lines(let count, let extent) where repeats(count):
            groups = linesDown(count, newline: extent != .interior)
        case .lineSpan(to: .motion(.line(.down, _), let count), let extent) where repeats(count):
            groups = linesDown(count + 1, newline: extent != .interior)
        case .lineSpan(to: .motion(.line(.up, _), let count), let extent) where repeats(count):
            groups = [([.paragraphEnd], .lineEndKey), (extent == .interior ? [] : [.right, .selectLeft], nil),
                      ([Chord.paragraphStart.shifted], .lineStartKey),
                      (repeated([.selectLeft, Chord.paragraphStart.shifted], count), nil)]
        case .lineSpan(to: .motion(.fileEnd, _), _):
            groups = [([.paragraphStart], .lineStartKey), ([Chord.documentEnd.shifted], .documentEndKey)]
        case .lineSpan(to: .motion(.fileStart, _), let extent):
            groups = [([.paragraphEnd], .lineEndKey), (extent == .interior ? [] : [.right], nil),
                      ([Chord.documentStart.shifted], .documentStartKey)]
        case .toLineEnd:
            groups = [([Chord.paragraphEnd.shifted], .lineEndKey)]
        case .span(to: .motion(.lineEnd, let count), false) where repeats(count):
            groups = [([Chord.paragraphEnd.shifted], .lineEndKey),
                      (repeated([.selectRight, Chord.paragraphEnd.shifted], count - 1), nil)]
        case .span(to: .motion(.lineStart(firstNonBlank: false), _), false):
            groups = [([Chord.paragraphStart.shifted], .lineStartKey)]
        default:
            return .next
        }
        return pressing(groups, to: range, context: &context, profile: profile)
    }

    /// ⌃A, then ⇧⌃E per line with ⇧→ between, and ⇧→ once more for the last newline.
    private static func linesDown(_ count: Int, newline: Bool) -> [KeyGroup] {
        var rest = repeated([.selectRight, Chord.paragraphEnd.shifted], count - 1)
        if newline { rest.append(.selectRight) }
        return [([.paragraphStart], .lineStartKey), ([Chord.paragraphEnd.shifted], .lineEndKey), (rest, nil)]
    }

    /// Presses the groups from the caret, each then settled, an unblamed one marked for `route`; `next` unless they land on `target`.
    static func pressing(
        _ groups: [KeyGroup], to target: Range<Int>, context original: inout Context, profile: CapabilityProfile,
        route: Route? = nil
    ) -> Lane {
        guard let text = original.text, let position = original.position else { return .next }
        let atoms = Set(groups.compactMap(\.blame))
        guard atoms.allSatisfy(profile.has) else { return .next }
        var context = original
        var steps = collapsing(&context)
        // One model throughout: which end of a selection moves is state the keys build up.
        var model = original.keys(text, at: position)
        let shown = original.model
        var pending: KeyGroup = ([], nil)
        for group in groups where !group.chords.isEmpty {
            for chord in group.chords {
                guard model.press(chord) else { return .next }
            }
            // A merged check names one key, so keys that blame different ones are not merged.
            guard pending.blame == nil || group.blame == nil || pending.blame == group.blame else { return .next }
            let merged: KeyGroup = (pending.chords + group.chords, pending.blame ?? group.blame)
            // Hosts differ on where a key lands among invisible characters ending a line: a caret there is checked on
            // either side of them, and a selection together with the keys after it.
            var checking: Landing?
            let ends = [model.selection.lowerBound, model.selection.upperBound]
            if let shown, let end = ends.first(where: { shown.visibleOffset($0) != $0 }) {
                guard model.selection.isEmpty else {
                    pending = merged
                    continue
                }
                checking = .caretWithin(shown.visibleOffset(end)...shown.lineBreak(of: end))
            }
            pending = ([], nil)
            steps += keys(merged.chords, blaming: merged.blame, to: model.selection, checking: checking, context: &context,
                          profile: profile, route: group.blame == nil ? route : nil)
        }
        guard pending.chords.isEmpty, model.selection == target else { return .next }
        original = context
        return .steps(steps)
    }

    private static func repeated(_ chords: [Chord], _ times: Int) -> [Chord] {
        Array(repeatElement(chords, count: max(0, times)).joined())
    }

    /// Presses `chords`, then settles on `landing`; a named key is blamed if it left a selection where it leaves a caret,
    /// if the field reads as before where it had somewhere to go, or if it landed elsewhere where lines are the model's.
    private static func keys(
        _ chords: [Chord], blaming atom: Capability?, to landing: Range<Int>, checking: Landing? = nil,
        context: inout Context, profile: CapabilityProfile, route: Route? = nil
    ) -> [PhysicalStep] {
        let before = context.selection
        let model = context.model
        context.selection = landing
        context.selectionOpaque = false
        let leavesCaret = chords.allSatisfy { !$0.modifiers.contains(.shift) }
        let blame = atom.flatMap { atom -> Expectation.Blame? in
            guard let before, let model else { return nil }
            let emptyParagraph = before == context.emptyParagraphCaret
            let unmoved = emptyParagraph || mayStayPut(chords, from: before, keys: context.keys(model.text, at: before.lowerBound))
                ? [] : [context.field(before)]
            // Chromium's rich text can split one paragraph into several `AXValue` lines (a mention chip); nothing else does.
            let offTarget = context.breaks == nil
            var exemptions: [Expectation.Exemption] = []
            if emptyParagraph { exemptions.append(.init(.emptyParagraph, unmoved: [context.field(before)])) }
            if !offTarget { exemptions.append(.init(.paragraphLines, offTarget: true)) }
            let selects = !leavesCaret && !emptyParagraph && !context.field(landing).isEmpty
            guard !unmoved.isEmpty || leavesCaret || selects || offTarget || !exemptions.isEmpty else { return nil }
            return Expectation.Blame(
                capability: atom, unmoved: unmoved, leavesCaret: leavesCaret, selects: selects, offTarget: offTarget,
                exemptions: exemptions
            )
        }
        return counted(chords) + settle(context, profile: profile, blame: blame, route: route, landing: checking)
    }

    /// Whether the keys may rightly leave the caret where it was: they had nowhere to go from it.
    private static func mayStayPut(_ chords: [Chord], from read: Range<Int>, keys: KeyModel) -> Bool {
        guard read.isEmpty else { return true }
        var keys = keys
        guard chords.allSatisfy({ keys.press($0) }) else { return true }
        return keys.selection == read
    }

    /// In a field that claims the native keys, a yank within a line takes the text the field selected, which holds
    /// where a misread caret shifts the model's; Chromium's leaves paragraph breaks out, and deletes check it instead.
    static func registersFromField(_ content: String, _ profile: CapabilityProfile) -> Bool {
        !profile.has(.writeSelection) && profile.has(.readSelectedText)
            && Capability.nativeKeys.contains(where: profile.has) && !content.contains("\n")
    }

    /// ← first, so every key starts from a caret (LIN-1532).
    private static func collapsing(_ context: inout Context) -> [PhysicalStep] {
        guard let selection = context.selection, !selection.isEmpty else { return [] }
        context.selection = selection.lowerBound..<selection.lowerBound
        return [.press(.left, count: 1)] + (context.normalizes(selection.lowerBound) ? outside : [])
    }
}
