/// Lowers a `LogicalPlan` into a `PhysicalPlan` for one field, under one
/// capability profile.
///
/// The planner is a **simulator, not a translator**: it walks the logical
/// steps carrying a predicted field state (the context), and for each step
/// picks the first lane that applies, emits concrete steps, updates the
/// prediction, and derives the settle expectation from that same
/// prediction. `lowerMove` and `lowerSelect` try the lanes in this order:
///
/// 1. **The app's keys**, under `nativeMotions`: its word, paragraph, row
///    and page keys, landing wherever the app decides.
/// 2. **Native line and document keys**, where selections cannot be
///    written: ⌃A ⌃E ⌘↑ ⌘↓, shifted to select, with only a column counted;
///    and ⌃A or ⌃E to a line's start or end that a folded field's write
///    would reach only with arrows after it.
/// 3. **A** (AX write): compute exact offsets with `TextModel`, set ranges,
///    adding arrow keys at a Chromium paragraph end, where a write lands on
///    the next paragraph. Or **B** (read, no write): the same exact math,
///    actuated as counted keystrokes and verified by read-back — reads
///    turn key synthesis into a dumb actuator. Lanes 2 and B take a
///    `Route` where it presses fewer keys than counting, until it misses.
/// 4. **C** (blind): Cocoa-approximate chords plus clipboard captures for
///    anything needing content.
///
/// A lane that does not apply leaves the step to the next one, and none
/// applies to a count that would repeat its keys more than
/// `Count.repeatLimit` times with no text to stop them. A lane that
/// applies but cannot realize the step rejects it, as running out of lanes
/// does, and a rejected step rejects the whole plan: `[.bell]`,
/// all-or-nothing, mirroring vim's execute-or-bell. The planner is pure —
/// it never talks to AX, and it writes no state (it only *authors* commit
/// steps for the reducer).
public enum PhysicalPlanner {
    /// Out-of-band, so the plan still stores only the program; only the step's type says which lowering rejected.
    public struct Rejection: Equatable, Sendable {
        public let index: Int
        public let step: LogicalStep

        public init(index: Int, step: LogicalStep) {
            self.index = index
            self.step = step
        }
    }

    /// Out-of-band for the same reason `Rejection` is: the plan stores only the program.
    public struct Planning: Equatable, Sendable {
        public let plan: PhysicalPlan
        public let rejection: Rejection?

        /// The range the plan meant to replace, in field offsets; nil in the blind lane, which has no offsets.
        public let operand: Range<Int>?

        /// The run deletes lines that end the text, so a selection it strands collapses to its end, on the last line.
        public let collapsesToEnd: Bool

        public init(plan: PhysicalPlan, rejection: Rejection?, operand: Range<Int>?, collapsesToEnd: Bool = false) {
            self.plan = plan
            self.rejection = rejection
            self.operand = operand
            self.collapsesToEnd = collapsesToEnd
        }

        /// Whether the run died checking the selected text: other text is selected, however its offsets read.
        public func abortedAtTextCheck(_ index: Int?) -> Bool {
            guard let index, plan.steps.indices.contains(index),
                  case .settle(let expectation) = plan.steps[index] else { return false }
            return expectation.selectedText != nil
        }
    }

    /// The plan alone — tests and any caller with no use for the rest.
    public static func plan(_ logical: LogicalPlan, snapshot: FieldSnapshot) -> PhysicalPlan {
        planning(logical, snapshot: snapshot).plan
    }

    /// `plan` plus what only the planner knows: why it rejected, and the operand; `missed` routes are planned without.
    public static func planning(
        _ logical: LogicalPlan, snapshot: FieldSnapshot, missed: Set<Route> = [], visual: Bool = false
    ) -> Planning {
        let profile = snapshot.capabilities
        var context = Context(snapshot: snapshot)
        context.missed = missed
        context.visual = visual
        var steps: [PhysicalStep] = []
        // Writes in a folded field mix with keys at its line edges (LIN-1685).
        let foldedWrites = profile.has(.writeSelection) && context.folded
        // The field shows our block cursor: physically collapse it to its
        // gap before the plan acts, so no step ever operates on the
        // presentation selection. Empty and bell-only plans skip this —
        // they touch nothing and the cursor stays up.
        var uncover: [PhysicalStep] = []
        if let gap = context.cursorCollapse, !logical.steps.isEmpty, !isBellOnly(logical) {
            uncover = collapse(to: gap, context: context, profile: profile)
            context.queue(uncover)
            context.drawnBreak = nil
            context.unmoved = false
        }
        for (index, step) in logical.steps.enumerated() {
            let caret = context.unmoved ? context.caret : nil
            // An AX write would overtake keys still queued, so a write after them waits for them to settle.
            let barrier = foldedWrites && context.keysQueued ? settle(context, profile: profile) : []
            let folded = context.folded
            guard var lowered = lower(step, context: &context, profile: profile) else {
                return Planning(plan: .rejected, rejection: Rejection(index: index, step: step), operand: nil)
            }
            // A folded write's keys work around the app's own line edges, whose misses say nothing of the write (LIN-1979).
            if !folded { lowered = checkingWrites(lowered) }
            // ⇧→ and ⇧⌃E do nothing from inside a code span's start, which a caret uvim did not place may be (LIN-1683).
            if let caret, let first = lowered.firstIndex(where: moves), case .press(let chord, _) = lowered[first],
               let prefix = outside(before: chord, at: caret, context: context, profile: profile) {
                lowered.insert(contentsOf: prefix, at: first)
            }
            if let first = lowered.first(where: moves), isWrite(first) {
                lowered.insert(contentsOf: barrier, at: 0)
            }
            steps.append(contentsOf: lowered)
            context.queue(lowered)
            if lowered.contains(where: moves) {
                context.drawnBreak = nil
                context.unmoved = false
            }
        }
        // ⌃A and ⌃E land alike from the cursor's one character, so a plan they start leaves it be.
        if foldedWrites, let first = steps.first(where: moves), case .press(let chord, _) = first,
           [.paragraphStart, .paragraphEnd].contains(chord) {
            uncover = []
        }
        return Planning(
            plan: PhysicalPlan(steps: uncover + steps), rejection: nil, operand: context.operand, collapsesToEnd: context.collapsesToEnd
        )
    }

    /// Marks the first settle after a selection write and the keys `write` added to finish it, which checks that write.
    static func checkingWrites(_ steps: [PhysicalStep]) -> [PhysicalStep] {
        var written = false
        var pressed = false
        return steps.map { step in
            switch step {
            case .setSelection:
                (written, pressed) = (true, false)
            case .press:
                pressed = written
            case .settle(var expectation) where pressed:
                expectation.checksWrite = true
                (written, pressed) = (false, false)
                return .settle(expectation)
            default:
                (written, pressed) = (false, false)
            }
            return step
        }
    }

    static func isWrite(_ step: PhysicalStep) -> Bool {
        switch step {
        case .setSelection, .replaceSelection: true
        default: false
        }
    }

    /// A step that can take the caret from where the snapshot saw it.
    static func moves(_ step: PhysicalStep) -> Bool {
        switch step {
        case .setSelection, .replaceSelection, .press, .typeText, .clipboardCut, .clipboardInsert: true
        default: false
        }
    }

    private static func isBellOnly(_ logical: LogicalPlan) -> Bool {
        logical.steps.allSatisfy { step in
            if case .bell = step { return true }
            return false
        }
    }
}

// MARK: - Repair and release

public extension PhysicalPlanner {
    /// The most keys one landing plan after `u` presses, as an app can take seconds to handle a long run of them (LIN-2104).
    static let undoKeys = 50

    /// The logical planner's landing after `u` on the `lines` put back since `before`, told from equal ones by `near`, with `ending`
    /// those lines where they end the text, for `undoFallback`; nil for any other undo.
    static func undoLanding(
        before: String, snapshot: FieldSnapshot, near: Range<Int>? = nil
    ) -> (plan: PhysicalPlan, ending: Range<Int>?, lines: Range<Int>)? {
        guard let model = Context(snapshot: snapshot).model,
              let (lines, ending) = model.restoredLines(from: before, selection: near ?? snapshot.selection) else { return nil }
        let logical = LogicalPlanner.undoLanding(
            firstNonBlank: model.firstNonBlank(inLineOf: lines.lowerBound),
            linesBelow: ending ? model.newlineCount(in: lines.lowerBound..<model.length) : nil
        )
        let landing = planning(logical, snapshot: snapshot)
        return landing.rejection == nil ? (landing.plan, ending ? lines : nil, lines) : nil
    }

    /// After a failed landing, keys onto restored `lines` that end the text from where the cursor stopped above: ↓, → and ⌘↓, or,
    /// `selecting`, ⇧↓ and → for a cursor those left above (each crosses the break where others cannot); nil once it is on them.
    static func undoFallback(onto lines: Range<Int>, snapshot: FieldSnapshot, selecting: Bool = false) -> PhysicalPlan? {
        var context = Context(snapshot: snapshot)
        guard let model = context.model else { return nil }
        if let selection = snapshot.selection, selection.lowerBound >= lines.lowerBound { return nil }
        guard snapshot.selection != nil || !selecting else { return nil }
        let above = snapshot.selection?.lowerBound ?? lines.lowerBound - 1
        // Ten of a kind at most, so ⌘↓, which reaches lines that end the text from anywhere, stays within a landing's keys (LIN-2104).
        let down = min(10, max(1, model.newlineCount(in: above..<lines.lowerBound)))
        // ⌘↓ is the chord the blind lane presses for `G` unlearned; the settle, and the selecting stage after it, check what it did.
        // → collapses a selection at its end, where AppKit's ⌘→ took an undo's selection to its first line's end, the line above.
        let keys: [PhysicalStep] = selecting ? [.press(.selectDown, count: down), .press(.right, count: 1)] : [
            .press(.down, count: down),
            .press(.right, count: min(10, max(1, model.graphemes(in: above..<lines.lowerBound)))),
            .press(.documentEnd, count: 1),
        ]
        guard snapshot.selection != nil else { return PhysicalPlan(steps: keys) }
        context.selection = model.length..<model.length
        // Each settle waits for its stage's last key, as ↓ alone can reach the lines with ⌘↓ on its way and the next command then
        // writes under it; ⇧↓'s selection matches no caret until → collapses it.
        return PhysicalPlan(steps: keys + settle(
            context, profile: snapshot.capabilities, hard: false,
            landing: selecting ? .caretWithin(lines.lowerBound...model.length) : nil
        ))
    }

    /// Collapses a selection an aborted run left to its start, or `toEnd` its end, in field offsets; `snapshot` reads the field as it is.
    static func collapse(
        _ selection: Range<Int>, misread: Bool = false, side: ParagraphBreaks.Side? = nil, paragraphs: Bool = false,
        snapshot: FieldSnapshot? = nil, toEnd: Bool = false, profile: CapabilityProfile
    ) -> PhysicalPlan {
        // After a failed text check the offsets name other text than is selected, and ← or → collapses whatever is.
        guard !misread else { return PhysicalPlan(.press(toEnd ? .right : .left, count: 1)) }
        // → needs no paragraph side, which a write would, and a selection it leaves still starts on the lines.
        guard !toEnd else {
            var context = Context(snapshot: FieldSnapshot(
                capabilities: profile, selection: selection.upperBound..<selection.upperBound, breaks: paragraphs ? ParagraphBreaks() : nil
            ))
            context.unknown.insert(.length)
            return PhysicalPlan(steps: [.press(.right, count: 1)] + settle(context, profile: profile))
        }
        var start = selection.lowerBound
        var field = FieldSnapshot(capabilities: profile, selection: start..<start, breaks: paragraphs ? ParagraphBreaks() : nil)
        // A `<br>` Linear drew for its caret leaves in its own time, and every offset behind it moves then.
        let held = snapshot.flatMap { $0.drawnBreak == nil ? $0 : nil }
        // In `AXValue` offsets a paragraph's end and the next one's start differ, as they do in a command's plan.
        if let held, let breaks = held.breaks, let resolved = breaks.valueRange(start..<start, side: { _ in side }),
           resolved.upperBound <= (held.text?.utf16.count ?? .max) {
            start = resolved.lowerBound
            field = FieldSnapshot(capabilities: profile, text: held.text, selection: resolved, breaks: breaks)
        }
        var context = Context(snapshot: field)
        context.unknown.insert(.length)
        let keys = [.press(.left, count: 1)] + (context.normalizes(start) ? outside : []) + settle(context, profile: profile)
        guard profile.has(.writeSelection) else { return PhysicalPlan(steps: keys) }
        // A folded write plans nothing where the caret is already placed, which a selection there is not.
        context.selection = nil
        let written = write(start..<start, context: context)
        // Where a write needs keys to finish, as at a paragraph's end, ← lands the selection's start itself (LIN-1532).
        return PhysicalPlan(steps: presses(written) ? keys : written)
    }

    /// Takes the drawn cursor off a field focus has left, by a write alone: a key would reach the field focus went to.
    static func releaseCursor(_ cursor: Range<Int>, breaks: ParagraphBreaks?, profile: CapabilityProfile) -> PhysicalPlan? {
        guard profile.has(.writeSelection) else { return nil }
        let context = Context(snapshot: FieldSnapshot(capabilities: profile, breaks: breaks))
        return PhysicalPlan(.setSelection(context.field(cursor.lowerBound..<cursor.lowerBound)))
    }
}

// MARK: - Step dispatch

private extension PhysicalPlanner {
    static func lower(
        _ step: LogicalStep,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        switch step {
        case .moveCaret(let destination):
            return lowerMove(destination, context: &context, profile: profile)
        case .select(let target):
            return lowerSelect(target, context: &context, profile: profile)
        case .extendSelection(let destination):
            return lowerExtend(destination, context: &context, profile: profile)
        case .collapseSelection(let edge):
            return lowerCollapse(edge, context: &context, profile: profile)
        case .swapSelectionEnds:
            return nil   // needs Visual-kind context; arrives with visual round 2
        case .deleteSelection(let register):
            return lowerDelete(into: register, context: &context, profile: profile)
        case .yankSelection(let register):
            return lowerYank(into: register, context: &context, profile: profile)
        case .replaceSelection(let replacement):
            return lowerTypeOver(replacement, context: &context, profile: profile)
        case .transformSelection(let transform):
            return lowerTransform(transform, context: &context, profile: profile)
        case .insertText(let insertion):
            return lowerTypeOver(insertion, context: &context, profile: profile)
        case .put(let source, let action, let count):
            return lowerPut(source, action, count: count, context: &context, profile: profile)
        case .joinLines(let count, let keepWhitespace):
            return lowerJoin(count: count, keepWhitespace: keepWhitespace, context: &context, profile: profile)
        case .setMode(let mode):
            return lowerSetMode(mode, context: &context)
        case .setMark(let name):
            return lowerSetMark(name, context: &context)
        case .history(let action):
            context.invalidate()
            switch action {
            case .undo: return [.press(.undo, count: 1)]
            case .redo: return [.press(.redo, count: 1)]
            case .olderTextState, .newerTextState: return nil
            }
        case .commit(let effect):
            return [.commit(effect)]
        case .renderCursor:
            return lowerRenderCursor(context: &context, profile: profile)
        case .bell:
            return [.bell]
        }
    }

    /// Best-effort by design: a cursor that cannot be drawn — or may not be
    /// (`drawCursor` is the standing selection's permission, distinct from
    /// the actuation writes) — is a bare caret, never a bell. No settle —
    /// cosmetic divergence must not abort the plan.
    static func lowerRenderCursor(context: inout Context, profile: CapabilityProfile) -> [PhysicalStep]? {
        guard profile.has(.writeSelection),
              profile.has(.drawCursor),
              let model = context.model,
              let gap = context.caret else {
            return [.commit(.setCursor(nil))]
        }
        let end = model.advance(gap, byGraphemes: 1)
        // A selection written over a chip collapses past it.
        guard end > gap, gap < model.lineEnd(of: gap), !context.isAtom(gap) else {
            return [.commit(.setCursor(nil))]   // end of line/text: nothing to cover
        }
        context.selection = gap..<end
        return write(gap..<end, from: gap, context: context) + [.commit(.setCursor(gap..<end))]
    }
}

// MARK: - State-only steps

private extension PhysicalPlanner {
    static func lowerSetMode(_ mode: LogicalStep.Mode, context: inout Context) -> [PhysicalStep]? {
        switch mode {
        case .normal:
            return [.commit(.setMode(.normal))]
        case .insert:
            return [.commit(.setMode(.insert)), .commit(.setInsertStart(context.caret))]
        case .replace:
            return [.commit(.setMode(.replace)), .commit(.setInsertStart(context.caret))]
        case .visual(let kind):
            guard let anchor = context.position else { return nil }   // no anchor, no Visual
            return [.commit(.setMode(.visual(VimState.VisualContext(kind: kind, anchor: anchor))))]
        }
    }

    static func lowerSetMark(_ name: Character, context: inout Context) -> [PhysicalStep]? {
        guard let model = context.model, let caret = context.caret else { return nil }
        return [.commit(.setMark(name, model.markPoint(at: caret)))]
    }
}
