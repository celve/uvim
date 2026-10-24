// MARK: - The app's keys

/// Every landing is checked against p, the caret the field reported.
extension PhysicalPlanner {
    private struct AppKey {
        let chord: Chord
        let forward: Bool
        /// Demoted when the key misbehaves; nil where staying put is legitimate.
        let atom: Capability?
    }

    private static func appKey(_ motion: Motion) -> AppKey? {
        switch motion {
        case .word(.forward, _, false): return AppKey(chord: .wordRight, forward: true, atom: .wordKeys)
        case .word(.backward, false, false): return AppKey(chord: .wordLeft, forward: false, atom: .wordKeys)
        case .paragraph(.forward): return AppKey(chord: .paragraphForward, forward: true, atom: .paragraphKeys)
        case .paragraph(.backward): return AppKey(chord: .paragraphBackward, forward: false, atom: .paragraphKeys)
        case .displayLine(.down): return AppKey(chord: .down, forward: true, atom: nil)
        case .displayLine(.up): return AppKey(chord: .up, forward: false, atom: nil)
        case .page(.forward, false): return AppKey(chord: .pageForward, forward: true, atom: nil)
        case .page(.backward, false): return AppKey(chord: .pageBackward, forward: false, atom: nil)
        case .line(.down, false): return AppKey(chord: .down, forward: true, atom: nil)
        case .line(.up, false): return AppKey(chord: .up, forward: false, atom: nil)
        default: return nil
        }
    }

    private static func mustMove(from p: Int, forward: Bool, model: TextModel) -> Bool {
        forward ? p < model.length : p > 0
    }

    /// Exempt in web content: raw reads cannot tell a key that did nothing (LIN-1564).
    private static func wordBlame(_ blame: Expectation.Blame?, context: Context) -> Expectation.Blame? {
        guard context.webContent, let blame else { return blame }
        return Expectation.Blame(capability: blame.capability, unmoved: blame.unmoved, leavesCaret: blame.leavesCaret,
                                 selects: blame.selects, offTarget: blame.offTarget, exemptions: [.init(.webContent, all: true)])
    }

    /// `j`/`k` press ↓/↑ only where neither a write nor ⌃E/⌃A can land a line.
    private static func movesByRow(_ motion: Motion, profile: CapabilityProfile) -> Bool {
        guard case .line(let direction, false) = motion else { return false }
        return !profile.has(.writeSelection) && !profile.has(direction == .down ? .lineEndKey : .lineStartKey)
    }

    private static func isBlank(_ o: Int, in model: TextModel) -> Bool {
        model.substring(o..<model.advance(o, byGraphemes: 1)).first?.isWhitespace ?? true
    }

    /// No app word crosses a blank, so this run bounds any word at `o`.
    private static func run(at o: Int, in model: TextModel) -> Range<Int> {
        guard !isBlank(o, in: model) else { return o..<o }
        var lower = o, upper = o
        while lower > 0, !isBlank(model.advance(lower, byGraphemes: -1), in: model) { lower = model.advance(lower, byGraphemes: -1) }
        while upper < model.length, !isBlank(upper, in: model) { upper = model.advance(upper, byGraphemes: 1) }
        return lower..<upper
    }

    private static func isWordCharacter(_ o: Int, in model: TextModel) -> Bool {
        model.substring(o..<model.advance(o, byGraphemes: 1)).first.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
    }

    private static func hasWord(_ run: Range<Int>, in model: TextModel) -> Bool {
        model.substring(run).contains { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func wordRunBefore(_ c: Int, in model: TextModel) -> Int {
        guard c > 0 else { return 0 }
        let found = run(at: model.advance(c, byGraphemes: -1), in: model)
        return hasWord(found, in: model) ? found.count : 0
    }

    /// How far `words` app words reach; like the keys, it skips punctuation-only runs.
    private static func wordReach(from o: Int, words: Int, forward: Bool, in model: TextModel) -> Int {
        var at = o
        for _ in 0..<max(1, words) {
            while true {
                let blanksDone: Int
                if forward {
                    var next = at
                    while next < model.length, isBlank(next, in: model) { next = model.advance(next, byGraphemes: 1) }
                    blanksDone = next
                    guard blanksDone < model.length else { at = model.length; break }
                    let found = run(at: blanksDone, in: model)
                    at = found.upperBound
                    if hasWord(found, in: model) { break }
                } else {
                    var next = at
                    while next > 0, isBlank(model.advance(next, byGraphemes: -1), in: model) { next = model.advance(next, byGraphemes: -1) }
                    blanksDone = next
                    guard blanksDone > 0 else { at = 0; break }
                    let found = run(at: model.advance(blanksDone, byGraphemes: -1), in: model)
                    at = found.lowerBound
                    if hasWord(found, in: model) { break }
                }
            }
        }
        return abs(at - o)
    }

    /// Where ⌥→ ⌥← from a blank lands.
    private static func nextWordStart(after o: Int, in model: TextModel) -> Int? {
        var at = o
        while at < model.length {
            if isWordCharacter(at, in: model) { return at }
            at = model.advance(at, byGraphemes: 1)
        }
        return nil
    }

    /// What `iw` finds at p; `trailing` is blanks to the text's end.
    private enum Under: Equatable {
        case letter
        case blank(nextWord: Int)
        case trailing
    }

    private static func under(_ c: Int, in model: TextModel) -> Under {
        guard isBlank(c, in: model) else { return .letter }
        return nextWordStart(after: c, in: model).map { .blank(nextWord: $0) } ?? .trailing
    }

    /// The word p is in or starts, else the one ending at p.
    private static func wordKeys(
        after under: Under, at p: Int, model: TextModel, context: Context, profile: CapabilityProfile
    ) -> [PhysicalStep] {
        let before = p > 0 ? run(at: model.advance(p, byGraphemes: -1), in: model) : p..<p
        switch under {
        case .letter:
            return selectBack(to: .caretAfter(p, strict: true), within: run(at: p, in: model), context: context, profile: profile)
        case .blank:
            return [.press(.wordLeft, count: 1),
                    appSettle(.caretBefore(p, strict: true), blame: nil, keeps: 0, context: context, profile: profile)]
                + selectBack(to: .exact(p..<p), within: before, context: context, profile: profile)
        case .trailing:
            return selectBack(to: .exact(p..<p), within: before, context: context, profile: profile)
        }
    }

    /// The selection must be exactly the kept span, inside `within`.
    private static func selectBack(to end: Landing, within: Range<Int>, context: Context, profile: CapabilityProfile) -> [PhysicalStep] {
        [.press(.wordRight, count: 1),
         appSettle(end, blame: nil, keeps: 1, context: context, profile: profile),
         .press(.selectWordLeft, count: 1),
         appSettle(.between(0, 1), blame: wordBlame(Expectation.Blame(capability: .wordKeys, unmoved: []), context: context),
                   within: within, context: context, profile: profile)]
    }

    /// Scripts written without spaces, where one run holds many words.
    private static func isUnspaced(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    private enum Edge { case start, end }

    private static func edge(at c: Int, in model: TextModel) -> Edge? {
        let before = c > 0 && isWordCharacter(model.advance(c, byGraphemes: -1), in: model)
        let after = isWordCharacter(c, in: model)
        return before == after ? nil : after ? .start : .end
    }

    /// Whether the reach ends a plain word run, so the span is known exactly.
    private static func oneWordRun(_ reached: Range<Int>, forward: Bool, in model: TextModel) -> Bool {
        let characters = Array(model.substring(reached))
        let word = { (c: Character) in c.isLetter || c.isNumber || c == "_" }
        let rest = forward ? Array(characters.drop { !word($0) }) : Array(characters.reversed().drop { !word($0) })
        return !rest.isEmpty && rest.allSatisfy(word)
    }

    /// Out and back to p with the unshifted keys; the selection must be exactly their span.
    private static func exactSpanKeys(
        _ p: Int, forward: Bool, fromStart: Bool, count: Int, reached: Range<Int>, context: Context, profile: CapabilityProfile
    ) -> [PhysicalStep] {
        let (out, back): (Chord, Chord) = forward ? (.wordRight, .wordLeft) : (.wordLeft, .wordRight)
        let (far, near) = forward ? (1, 0) : (0, 1)
        let leaves = forward == fromStart
        return [.press(out, count: count),
                appSettle(forward ? .caretAfter(p, strict: true) : .caretBefore(p, strict: true), blame: nil, keeps: far,
                          context: context, profile: profile)]
            // From the other edge: one word further back, then one out.
            + (leaves ? [.press(back, count: count)] : [.press(back, count: count + 1), .press(out, count: 1)])
            + [appSettle(.exact(p..<p), blame: nil, keeps: near, context: context, profile: profile),
                .press(forward ? .selectWordRight : .selectWordLeft, count: count),
                appSettle(.between(0, 1), blame: wordBlame(Expectation.Blame(capability: .wordKeys, unmoved: []), context: context),
                          within: reached, context: context, profile: profile)]
    }

    /// Where ⌥→ ⌥← lands: exactly on the next word from a blank, else at or before p.
    private static func roundTripLanding(_ under: Under, at p: Int) -> Landing {
        if case .blank(let next) = under { return .exact(next..<next) }
        return .caretBefore(p, strict: false)
    }

    /// Checks precede selections, so a failure strands a caret, not a selection.
    private static func wordAtCaretKeys(_ p: Int, model: TextModel, context: Context, profile: CapabilityProfile) -> [PhysicalStep]? {
        let under = under(p, in: model)
        if under != .letter, wordRunBefore(p, in: model) == 0 { return nil }
        return [.press(.wordRight, count: 1), .press(.wordLeft, count: 1),
                appSettle(roundTripLanding(under, at: p), blame: nil, keeps: 0, context: context, profile: profile)]
            + wordKeys(after: under, at: p, model: model, context: context, profile: profile)
    }

    private static func appSettle(
        _ landing: Landing, blame: Expectation.Blame?, keeps: Int? = nil, within: Range<Int>? = nil,
        context: Context, profile: CapabilityProfile
    ) -> PhysicalStep {
        .settle(context.expectation(landing, blame: blame, keeps: keeps, within: within, profile: profile))
    }

    /// Blamed only if the field still reads p after the keys.
    private static func stuck(_ atom: Capability?, at p: Int, context: Context) -> Expectation.Blame? {
        atom.map { Expectation.Blame(capability: $0, unmoved: [context.field(p..<p)]) }
    }

    /// A key may land across paragraph breaks alone, which the field's offsets skip.
    private static func mayCrossOnlyBreaks(from p: Int, forward: Bool, context: Context) -> Bool {
        context.breaks?.offsets.contains(forward ? p : p - 1) ?? false
    }

    static func appMove(
        _ destination: LogicalStep.Destination, context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard profile.has(.nativeMotions), case .motion(let motion, let count) = destination,
              let key = appKey(motion), repeats(count) else { return .next }
        guard let model = context.model(for: destination, profile), let selection = context.selection,
              profile.has(.readCaret) else {
            // Lane C already maps words and lines.
            if key.atom == .wordKeys { return .next }
            if case .line = motion { return .next }
            context.selection = nil
            context.selectionOpaque = false
            return .steps([.press(key.chord, count: count)])
        }
        // The app's own keys land past invisible characters ending a line, so the model's lanes take every motion they compute.
        if model.endsLinesInvisibly, resolve(destination, model: model, from: selection.lowerBound) != nil { return .next }
        // Exact fields keep vim's words.
        if key.atom == .wordKeys, profile.has(.writeSelection) { return .next }
        if case .line = motion, !movesByRow(motion, profile: profile) { return .next }
        if let atom = key.atom, !profile.has(atom) { return .next }
        let p = selection.lowerBound
        let strict = mustMove(from: p, forward: key.forward, model: model)
            && !mayCrossOnlyBreaks(from: p, forward: key.forward, context: context)
        let landing: Landing = key.forward ? .caretAfter(p, strict: strict) : .caretBefore(p, strict: strict)
        context.selection = nil
        context.selectionOpaque = false
        return .steps((selection.isEmpty ? [] : [.press(.left, count: 1)]) + [
            .press(key.chord, count: count),
            // Blamed for leaving a selection, or, outside web content, for staying put.
            appSettle(landing, blame: key.atom.map {
                let stuck = strict ? [context.field(p..<p)] : []
                return context.webContent
                    ? Expectation.Blame(capability: $0, unmoved: [], leavesCaret: true,
                                        exemptions: stuck.isEmpty ? [] : [.init(.webContent, unmoved: stuck)])
                    : Expectation.Blame(capability: $0, unmoved: stuck, leavesCaret: true)
            }, context: context, profile: profile),
        ])
    }

    /// Rejects a selection its keys cannot prove, since vim's words may not be the app's.
    static func appSelect(
        _ target: LogicalStep.SelectionTarget, context: inout Context, profile: CapabilityProfile
    ) -> Lane {
        guard profile.has(.nativeMotions) else { return .next }
        let span: AppKey?
        switch target {
        case .textObject(TextObject(scope: .inner, kind: .word(bigWord: false)), 1):
            span = nil
        case .span(.motion(let motion, let count), _):
            guard let key = appKey(motion), key.atom == .wordKeys, repeats(count) else { return .next }
            span = key
        default:
            return .next
        }
        guard let model = context.model(for: target, profile), let selection = context.selection,
              profile.has(.readCaret) else {
            // ⌥→ first, so a caret at a word's start stays in that word.
            guard span == nil else { return .next }
            context.selection = nil
            context.selectionOpaque = true
            context.selectionWise = .character
            return .steps([.press(.wordRight, count: 1), .press(.wordLeft, count: 1), .press(.selectWordRight, count: 1)])
        }
        guard !profile.has(.writeSelection), profile.has(.wordKeys), !model.endsLinesInvisibly else { return .next }
        let p = selection.lowerBound
        var steps: [PhysicalStep] = selection.isEmpty ? [] : [.press(.left, count: 1)]
        if let key = span, case .span(.motion(_, let count), _) = target {
            let reach = wordReach(from: p, words: count, forward: key.forward, in: model)
            let reached = key.forward ? p..<min(model.length, p + reach) : max(0, p - reach)..<p
            // Proven at an edge, predicted in a plain word, else refused.
            if let edge = edge(at: p, in: model) {
                steps += exactSpanKeys(p, forward: key.forward, fromStart: edge == .start, count: count, reached: reached,
                                       context: context, profile: profile)
            } else if model.substring(reached).contains(where: isUnspaced) {
                // The app may see a word edge here the model cannot; it rings if not.
                steps += exactSpanKeys(p, forward: key.forward, fromStart: key.forward, count: count, reached: reached,
                                       context: context, profile: profile)
            } else if oneWordRun(reached, forward: key.forward, in: model) {
                steps.append(.press(key.forward ? .selectWordRight : .selectWordLeft, count: count))
                let blame = wordBlame(stuck(.wordKeys, at: p, context: context), context: context)
                steps.append(appSettle(.exact(reached), blame: blame, context: context, profile: profile))
            } else {
                return .reject
            }
        } else {
            guard let keys = wordAtCaretKeys(p, model: model, context: context, profile: profile) else { return .reject }
            steps += keys
        }
        context.selection = nil
        context.selectionOpaque = true
        context.selectionWise = .character
        return .steps(steps)
    }
}
