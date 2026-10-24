// MARK: - Selection

extension PhysicalPlanner {
    private static func selectionRange(
        for target: LogicalStep.SelectionTarget,
        model: TextModel,
        at position: Int,
        context: Context
    ) -> Range<Int>? {
        switch target {
        case .span(let destination, let inclusive):
            guard var end = resolve(destination, model: model, from: position) else { return nil }
            if inclusive { end = model.visibleOffset(model.advance(end, byGraphemes: 1)) }
            let start = model.visibleOffset(position)
            return min(start, end)..<max(start, end)
        case .lineSpan(let destination, let extent):
            guard let end = resolve(destination, model: model, from: position) else { return nil }
            return model.lineSpan(from: position, to: end, extent: extent)
        case .lines(let count, let extent):
            return model.lines(from: position, count: count, extent: extent)
        case .textObject(let object, let count):
            guard case .word(let big) = object.kind else { return nil }
            var range = model.wordObject(at: position, around: object.scope == .around, big: big)
            for _ in 1..<max(1, count) {
                let next = model.wordObject(at: range.upperBound, around: object.scope == .around, big: big)
                // At the text's end the next object adds nothing, and no later one does.
                guard next.upperBound > range.upperBound else { break }
                range = range.lowerBound..<next.upperBound
            }
            return model.visibleOffset(range.lowerBound)..<model.visibleOffset(range.upperBound)
        case .toLineEnd:
            return position..<model.lineEnd(of: position)
        case .current:
            guard let selection = context.selection, !selection.isEmpty else { return nil }
            return selection
        case .remembered(let memory):
            let range = model.clamp(memory.range.lowerBound)..<model.clamp(memory.range.upperBound)
            return model.visibleOffset(range.lowerBound)..<model.visibleOffset(range.upperBound)
        }
    }

    private static func blindSelectKeys(_ target: LogicalStep.SelectionTarget) -> [PhysicalStep]? {
        switch target {
        case .span(let destination, _):
            guard case .motion(let motion, let count) = destination,
                  let blind = blindMoveChord(motion), !blind.counted || repeats(count) else { return nil }
            return [.press(blind.chord.shifted, count: blind.counted ? count : 1)]
        case .lines(let count, let extent):
            guard repeats(count) else { return nil }
            if extent == .interior {
                var steps: [PhysicalStep] = [.press(.lineStart, count: 1)]
                if count > 1 { steps.append(.press(.selectDown, count: count - 1)) }
                steps.append(.press(.selectLineEnd, count: 1))
                return steps
            }
            return [.press(.lineStart, count: 1), .press(.selectDown, count: count)]
        case .toLineEnd:
            return [.press(.selectLineEnd, count: 1)]
        case .textObject(let object, _):
            guard case .word = object.kind else { return nil }
            return [.press(.wordLeft, count: 1), .press(.selectWordRight, count: 1)]
        case .lineSpan(let destination, let extent):
            // `dj`, `dG`: whole lines from here through the destination's
            // line. Only vertical destinations have a blind spelling — a
            // lineSpan to a mark has none and rings.
            guard case .motion(let motion, let count) = destination else { return nil }
            let interior = extent == .interior
            var steps: [PhysicalStep] = [.press(.lineStart, count: 1)]
            switch motion {
            case .line(.down, _):
                guard repeats(count) else { return nil }
                // count lines below, plus the caret's own.
                steps.append(.press(.selectDown, count: interior ? count : count + 1))
            case .fileEnd:
                steps.append(.press(Chord.documentEnd.shifted, count: 1))
            default:
                return nil
            }
            if interior, case .line = motion {
                steps.append(.press(.selectLineEnd, count: 1))
            }
            return steps
        case .current:
            return []   // whatever is on screen is the operand
        case .remembered:
            return nil
        }
    }

    static func lowerSelect(
        _ target: LogicalStep.SelectionTarget,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        context.breakAbove = nil
        return appSelect(target, context: &context, profile: profile)
            .or { exactSelect(target, context: &context, profile: profile) }
            .or { blindSelect(target, context: &context) }
            .lowered
    }

    /// Lanes 2 and 3, which share the model's range: native keys where they select it, else lane A or B.
    private static func exactSelect(
        _ target: LogicalStep.SelectionTarget, context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard let model = context.model(for: target, profile), let selection = context.selection else { return .next }
        guard var range = selectionRange(for: target, model: model, at: selection.lowerBound, context: context) else {
            return .reject
        }
        var target = target
        // Lines that end the text are selected without the line break above them, which the delete takes last.
        if let lines = kept(target), let whole = selectionRange(for: lines, model: model, at: selection.lowerBound, context: context),
           whole.lowerBound > range.lowerBound {
            context.breakAbove = range.lowerBound..<whole.lowerBound
            context.collapsesToEnd = true
            (target, range) = (lines, whole)
        }
        context.selectionWise = target.wise ?? context.selectionWise ?? .character
        context.selectionOpaque = false
        // Pressed even where nothing is to select, so a settle checks the caret the command starts from.
        return nativeSelect(target, range: range, context: &context, profile: profile).or {
            // Outside Visual, a write lane's selection can be a failed command's whose collapse write has yet to show (LIN-1931).
            let collapsing = profile.has(.writeSelection) && !context.visual && !range.isEmpty
            if range == context.selection, !collapsing {
                return .steps([])   // already selected (Visual operators)
            }
            if profile.has(.writeSelection) {
                context.selection = range
                let caret = selection.isEmpty ? selection.lowerBound : nil
                return .steps(write(range, from: caret, context: context) + settle(context, profile: profile))
            }
            return lineSelect(range, model: model, context: &context, profile: profile).or {
                if context.breakAbove != nil {
                    let reaching = keyPath(from: selection, to: range.upperBound, model: model, context: context)
                    return .steps(selectingBack(range, reaching: reaching, model: model, context: &context, profile: profile))
                }
                let keys = selectKeys(range, from: selection, model: model, context: context)
                context.selection = range
                return .steps(keys.presses + settle(context, profile: profile, route: keys.route))
            }
        }
    }

    /// Lines that end the text, selected back from its end once a check finds the caret there, so no partial selection starts above them.
    private static func selectingBack(
        _ range: Range<Int>, reaching: [PhysicalStep], model: TextModel, context: inout Context, profile: CapabilityProfile
    ) -> [PhysicalStep] {
        context.selection = range.upperBound..<range.upperBound
        let reached = reaching + settle(context, profile: profile)
        guard !range.isEmpty else { return reached }
        context.selection = range
        return reached + [.press(.selectLeft, count: model.graphemes(in: range))] + settle(context, profile: profile)
    }

    /// A delete's lines as whole lines, which take the newline after them where the delete takes the one before.
    private static func kept(_ target: LogicalStep.SelectionTarget) -> LogicalStep.SelectionTarget? {
        switch target {
        case .lines(let count, .removed): .lines(count: count, extent: .whole)
        case .lineSpan(let destination, .removed): .lineSpan(to: destination, extent: .whole)
        default: nil
        }
    }

    /// An optional route: ⇧⌃E or ⇧⌃A from a caret at a range's end on its line, then ⇧ arrows back, where that presses fewer.
    private static func lineSelect(_ range: Range<Int>, model: TextModel, context: inout Context, profile: CapabilityProfile) -> Lane {
        guard let caret = context.caret, !range.isEmpty, [range.lowerBound, range.upperBound].contains(caret),
              model.newlineCount(in: range) == 0 else { return .next }
        let forward = caret == range.lowerBound
        let (key, back, needs, route): (Chord, Chord, Capability, Route) = forward
            ? (Chord.paragraphEnd.shifted, .selectLeft, .lineEndKey, .lineEnd)
            : (Chord.paragraphStart.shifted, .selectRight, .lineStartKey, .lineStart)
        let across = model.graphemes(in: range) + prefixCount(forward ? .selectRight : .selectLeft, context: context, profile: profile)
        let limit = across - 2 - prefixCount(key, context: context, profile: profile)
        guard profile.has(needs), !context.missed.contains(route), let count = model.graphemes(
            from: forward ? range.upperBound : range.lowerBound, toLineEnd: forward, atMost: limit
        ) else { return .next }
        return pressing([([key] + Array(repeating: back, count: count), nil)], to: range, context: &context, profile: profile,
                        route: route)
    }

    /// ⇧→ across a range from its start; or, as an optional route, ⇧← across one that ends at the caret on its line.
    private static func selectKeys(
        _ range: Range<Int>, from selection: Range<Int>, model: TextModel, context: Context
    ) -> (presses: [PhysicalStep], route: Route?) {
        let count = model.graphemes(in: range)
        if selection.isEmpty, count > 0, selection.lowerBound == range.upperBound, model.newlineCount(in: range) == 0,
           !context.missed.contains(.selectBack) {
            return ([.press(.selectLeft, count: count)], .selectBack)
        }
        return (keyPath(from: selection, to: range.lowerBound, model: model, context: context)
            + (count > 0 ? [.press(.selectRight, count: count)] : []), nil)
    }

    private static func blindSelect(_ target: LogicalStep.SelectionTarget, context: inout Context) -> Lane {
        guard let presses = blindSelectKeys(target) else { return .next }
        context.selection = nil
        context.selectionOpaque = true
        context.selectionWise = target.wise ?? .character
        return .steps(presses)
    }

    static func lowerExtend(
        _ destination: LogicalStep.Destination,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        if let model = context.model(for: destination, profile), let selection = context.selection, let anchor = context.anchor,
           profile.has(.writeSelection) || profile.has(.readCaret) && model.endsLinesInvisibly {
            let start = model.visibleOffset(anchor)
            let head = model.visibleOffset(selection.lowerBound == start ? selection.upperBound : selection.lowerBound)
            guard let target = resolve(destination, model: model, from: head) else { return nil }
            let range = min(start, target)..<max(start, target)
            context.selection = range
            context.selectionOpaque = false
            guard profile.has(.writeSelection) else {
                // The app's own extend lands past invisible characters ending a line, so keys rebuild it from the anchor.
                let count = model.graphemes(in: range)
                return keyPath(from: selection, to: start, model: model, context: context)
                    + (count > 0 ? [.press(target < start ? .selectLeft : .selectRight, count: count)] : [])
                    + settle(context, profile: profile)
            }
            return write(range, context: context) + settle(context, profile: profile)
        }
        // Blind: the app owns the anchor. This deliberately ignores
        // `context.anchor` — mixing a stored engine offset with a live app
        // selection is exactly where this would go silently wrong. The
        // selection becomes opaque, so a following operator takes the
        // clipboard path (`lowerDelete`/`lowerYank` already branch on it).
        guard case .motion(let motion, let count) = destination,
              let blind = blindMoveChord(motion), !blind.counted || repeats(count) else { return nil }
        context.selection = nil
        context.selectionOpaque = true
        return [.press(blind.chord.shifted, count: blind.counted ? count : 1)]
    }

    static func lowerCollapse(
        _ edge: LogicalStep.SelectionEdge,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        if let selection = context.selection {
            guard !selection.isEmpty else { return [] }
            let target: Int
            switch edge {
            case .start:
                target = selection.lowerBound
            case .end:
                target = selection.upperBound
            case .head:
                // With no anchor the app owns the selection and nothing reads its direction, so its start stands in.
                let anchor = context.anchor.map { context.model?.visibleOffset($0) ?? $0 }
                target = anchor == selection.lowerBound ? selection.upperBound : selection.lowerBound
            }
            let towardStart = target == selection.lowerBound
            context.selection = target..<target
            let settled = towardStart && context.normalizes(target) ? outside : []
            let keys = [.press(towardStart ? .left : .right, count: 1)] + settled + settle(context, profile: profile)
            guard profile.has(.writeSelection) else { return keys }
            return keyed(write(target..<target, context: context) + settle(context, profile: profile), or: keys, context: context)
        }
        if context.selectionOpaque {
            context.selectionOpaque = false
            context.selection = nil
            switch edge {
            case .start: return [.press(.left, count: 1)]
            case .end: return [.press(.right, count: 1)]
            case .head: return nil
            }
        }
        return []   // nothing selected, nothing to collapse
    }
}
