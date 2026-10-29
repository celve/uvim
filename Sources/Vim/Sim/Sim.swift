/// A simulated field: an in-memory text field that the `CommandLoop` runs commands against, as it does a real field through the
/// Controller.
///
/// The Sim feeds tokens through the monitor and hands each command to the loop, carries out the physical steps `StepRunner`
/// walks by string surgery, verifies settles against itself, and hands commits to the reducer. That closes the loop entirely in
/// pure code: end-to-end goldens of the form `(text, caret, keystrokes) → (text′, caret′, state′)` run under `make test`, and
/// later the flight recorder can replay through the same machine.
///
/// It executes lane-A/B AX and clipboard steps exactly — including the
/// modeled pasteboard, written by `clipboardCut`/`clipboardCopy` and read
/// by `clipboardInsert(nil)`, which makes the clipboard=unnamed contract
/// pure-testable. Of Cocoa's keys it emulates, through `KeyModel`, the
/// ones lane B counts with, and every one the model knows under
/// `emulatesKeys`; any other `press` (the blind lane's chords, undo) counts
/// as `unsupportedSteps`, because the Sim can only prove we emit the plans
/// we designed, never that a blind plan works in a real app.
///
/// Its faults are the only way a golden reaches the abort path at all.
public struct Sim {
    public internal(set) var text: String
    public internal(set) var selection: Range<Int>
    public private(set) var state: VimState
    /// The modeled system pasteboard — the blind lanes' register.
    public private(set) var pasteboard: String?
    public var profile: CapabilityProfile

    /// Accepts `AXSelectedText` and does nothing — the Chromium contenteditable.
    public var swallowsReplace = false

    /// The same lie about `AXSelectedTextRange` — what a `writeSelection` demotion leaves.
    public var swallowsSelect = false
    /// The same, for the writes of a landing after `u` alone (LIN-2104).
    public var swallowsLandingSelect = false
    private var landing = false

    /// Settle and repair reads get no `AXSelectedTextRange`; the snapshot's read still answers.
    public var unreadableSelection = false

    /// Makes the field a Chromium contenteditable: `AXSelectedTextRange` starts at `reads` of the selection's
    /// start and is as long as `AXSelectedText`, the true selected text less its paragraph breaks (LIN-1533).
    public var reads: ((_ offset: Int, _ text: String) -> Int)?

    /// Chromium rich text whose every `\n` ends a paragraph, as Chrome 153 shows it: see `ChromiumParagraphs` (LIN-1612).
    public var emptyParagraphs = false

    /// Off, discovery fails and the snapshot keeps `AXValue`'s lines.
    public var findsEmptyParagraphs = true

    /// In Chromium modes, the field ends in an inline icon: a U+FFFC only the marker text has.
    public var endsInTextlessLeaf = false

    /// With `emptyParagraphs`, Linear's editor: blocks each line draws before its text, and each U+2060 a chip.
    public var listLines: [ListLine]?
    /// The editor is Quill's, whose `listLines` markers have no space after them (LIN-2329).
    public var quill = false

    /// Off, discovery of list markers and chips fails, and they stay lines.
    public var findsUnreachable = true

    /// A caret written at a chip's start, where Linear's next arrow does nothing.
    var atChipStart = false

    /// With `listLines`, Linear's inline code spans: a caret at an edge is inside or outside one, and drawn (LIN-1683).
    public var codeSpans: [Range<Int>] = []

    /// A caret at a code span's edge is inside it; a plain arrow from the edge's near side only crosses the edge.
    var codeInside = false

    /// A caret written at a code span's end, where Linear's next ← or ⇧← can do nothing.
    var atWrittenCodeEnd = false

    /// The stop between two blocks the caret is at, before the line after it.
    var inListGap: KeyModel.Stop?

    /// What ⌘Z leaves selected of the text it puts back, as measured: all of it in AppKit, through its first line break
    /// in Chrome's textarea, up to that break in Chrome's rich text; `start`, a caret at the text's start, no host measured.
    public enum UndoSelection: Equatable, Sendable { case restored, throughBreak, toBreak, start }
    public var undoSelection = UndoSelection.restored

    /// Each undo group's text before it and its first edit's offset, newest last, as the host's undo stack holds them.
    var undoGroups: [UndoGroup] = []
    typealias UndoGroup = (before: String, at: Int, listLines: [ListLine]?, codeSpans: [Range<Int>])

    /// Groups ⌘Z undid, with the text each left, which ⇧⌘Z puts back until a new edit.
    var redoGroups: [(group: UndoGroup, after: String, listLines: [ListLine]?, codeSpans: [Range<Int>])] = []

    /// Hosts group consecutive typed edits for undo until the caret moves some other way.
    var coalescing = false

    /// Chrome's ⌘Z and ⇧⌘Z, as measured: a key sent right behind one runs first, and a read or write waits for it.
    public var undoesLate = false
    var lateHistory: [Chord] = []

    /// ⌘Z and ⇧⌘Z shown only after the Controller's wait for them ends, at the next key or click (LIN-2104).
    public var undoesAfterWait = false
    var heldHistory: [Chord] = []

    /// With `undoesAfterWait`, shown no sooner than the next command's own wait for them.
    public var undoesInNextWait = false

    /// How many plans of a landing after `u` run before the Controller's deadline cuts it, as slow live faults showed.
    public var plansBeforeDeadline: Int?
    /// The plans the current landing attempt has left.
    private var plansLeft: Int?

    /// Snapshots taken aside, as a landing's, whose `AXSelectedTextRange` goes unanswered, one fewer each.
    public var unansweredSelectionsAside = 0

    /// Linear draws the caret 20–160 ms after it arrives, so a quick command's snapshot can come first.
    public var drawsLate = false
    var snapshotting = false

    /// Text the page generates while the field is empty, as ChatGPT's box shows "Ask anything" (LIN-1930).
    public var placeholder: String?

    /// Where in the placeholder the caret reads: its start in some editors, its end or near it in others.
    public var placeholderCaret = 0

    var showsPlaceholder: Bool { placeholder != nil && text.isEmpty }

    public var readSelection: Range<Int> {
        if showsPlaceholder { return placeholderCaret..<placeholderCaret }
        // Quill reads a caret at the field's start before its first marker.
        if emptyParagraphs { return quill && selection == 0..<0 ? 0..<0 : chromium.field(selection) }
        guard let reads else { return selection }
        let start = reads(selection.lowerBound, text)
        return start..<start + readSelectedText.utf16.count
    }

    public var readSelectedText: String {
        if showsPlaceholder { return "" }
        if emptyParagraphs {
            let markers = Array(chromium.plainMarkers.utf16)
            let range = readSelection
            return String(decoding: markers[range.clamped(to: 0..<markers.count)], as: UTF16.self)
        }
        let selected = TextModel(text).substring(selection)
        return reads == nil ? selected : selected.filter { $0 != "\n" }
    }

    /// The field answers text-marker reads: the real selection, every `\n` a generated break.
    public var markers = false

    /// Selection writes land in `reads`' coordinates, as Chromium's do.
    public var writesInReadOffsets = false

    public var hasChildren = true

    /// Used only when no learner runs.
    public var readModel: OffsetsAnswer = .value

    /// Learns from each command and re-resolves `profile` from its beliefs.
    public internal(set) var learner: Learner?

    /// Where the last command's run ended early, if it did.
    public private(set) var abortedStep: PhysicalStep?

    /// Every key `KeyModel` knows runs, not only the ones lane B counts with.
    public var emulatesKeys = false

    /// The field is web content; a Chromium read fault (`reads`) implies it.
    public var webContent = false

    /// Graphemes per visual row for ↓ ↑ ⌘← ⌘→; nil puts each line on one row.
    public var wrapWidth: Int?

    /// Keys this field ignores, as an app that rebinds them would.
    public var ignoredChords: Set<Chord> = []

    /// Keys this field treats as others, as an app that rebinds ⌃A to select-all would.
    public var reboundChords: [Chord: Chord] = [:]

    /// Lark's editor: a selection end just past the invisible character closing a line, its newline, moves before it (LIN-1975).
    public var pullsBackFromLineEnds = false

    /// → from a caret at a line's end does nothing, as the live fault host's `right-at-line-end` (LIN-2104).
    public var holdsRightAtLineEnds = false

    /// Lark's editor: ⌫ at a line's start deletes the line above's closing invisible characters with the `\n`, as its newline.
    public var runsAreNewlines = false

    /// An input method is selected, so what Insert-mode keys type is not what the typed log says.
    public var inputMethod = false

    /// Letters the input method holds pending, ending at the caret; `compose` types them.
    public private(set) var composing: Range<Int>?

    /// Off, the reads cannot tell, as in Chromium with an input method that shows no candidate list there.
    public var readsComposition = true

    /// The input method ignores the commit key, so its letters stay pending.
    public var ignoresCommit = false

    /// The reads fail once the commit key is sent, so nothing reads the commit.
    public var failsReadAfterCommit = false

    /// After this many more keys reach the field the focus moves, and the executor's reads see that only `unseen` keys
    /// later. Those keys are addressed to the field's app (LIN-1105): after a click they reach another of its fields,
    /// and after another app's activation they reach this one, which then takes plain keys but no ⌘ menu equivalent.
    public var focusLeaves: (after: Int, unseen: Int, by: KeyDestination.Departure)?

    /// Why the last command stopped posting keys, as the executor's run says.
    public internal(set) var departure: KeyDestination.Departure?

    /// The running command's, as the Controller hands it to the executor.
    var destination: KeyDestination?

    /// What the executor's read of the field's app says.
    var appActive = true

    /// The field takes the key the check before it let go: after the focus left, keys reach another field or no menu.
    private var takesKey = true

    /// A key of the press under way the Sim cannot emulate, which makes the rest of its keys no-ops.
    private var pressUnsupported = false

    /// Keys the failed settles blamed, in order.
    public internal(set) var blamed: [Capability] = []

    public private(set) var bells = 0
    public internal(set) var settleFailures = 0
    /// Soft settles that missed, which ring nothing and abort nothing, as the executor logs them.
    public internal(set) var softMisses = 0
    public private(set) var unsupportedSteps = 0
    /// Keys pressed, ignored ones included.
    public private(set) var presses = 0

    /// The last command's evidence from its settles.
    public internal(set) var attribution = RunAttribution()

    private var monitor = RawMonitor()

    /// The field's button events so far, which the Controller reads from the window server.
    var buttonEvents: UInt32 = 0

    /// The focus is the selection's lower bound.
    var backward = false

    /// The open change for `.` and the landing pending after `u`.
    var loop = CommandLoop<Sim>()

    /// The last snapshot's, to convert the drawn cursor at unbind.
    private var fieldBreaks: ParagraphBreaks?

    /// The last snapshot's discoveries, found again when the text changes.
    private var foundEmptyParagraphs: EmptyParagraphs.Memo?
    private var foundUnreachable: UnreachableLines.Memo?

    public init(
        text: String,
        caret: Int = 0,
        state: VimState = .initial,
        profile: CapabilityProfile
    ) {
        self.text = text
        let clamped = TextModel(text).clamp(caret)
        self.selection = clamped..<clamped
        self.state = state
        self.profile = profile
    }

    public var caret: Int { selection.lowerBound }

    public mutating func learn(with learner: Learner) {
        self.learner = learner
        resolveBeliefs()
    }

    public mutating func update(to versions: Versions) {
        learner?.versions = versions
        learner?.sampling = OffsetsSampling()
        resolveBeliefs()
    }

    /// Feed each character of `keys` as one token.
    public mutating func type(_ keys: String) {
        for character in keys {
            feed(String(character))
        }
    }

    public mutating func feed(_ token: String) {
        if !undoesInNextWait { releaseHeldHistory() }
        let mode: RawMonitor.Mode
        switch state.field.mode {
        case .normal: mode = .normal
        case .visual: mode = .visual
        case .insert, .replace: mode = .insert
        }
        if mode == .insert, token == "<Esc>" || token == "<C-[>", CommandLoop.engage(token, host: &self) != nil { return }
        switch monitor.feed(token, mode: mode, clicks: mode == .insert ? nil : buttonEvents) {
        case .pending, .cancelled:
            break
        case .passthrough:
            loop.pendingUndo = nil
            if mode == .insert, inputMethod { monitor.markInsertLogLossy() }
            if token == "<Esc>" { cancelComposition() }
            applyTyping(token)
        case .command(let completed):
            CommandLoop.command(completed, mode: mode, host: &self)
        }
    }

    /// Letters typed through the input method, which holds them pending at the caret.
    public mutating func compose(_ letters: String) {
        for letter in letters {
            let start = composing?.lowerBound ?? caret
            feed(String(letter))
            composing = start..<caret
        }
    }

    /// What the Controller's reads would answer.
    var composition: Composition {
        guard readsComposition else { return .unknown }
        return composing == nil ? .clear : .pending
    }

    /// Esc reached the input method, which drops its pending letters.
    private mutating func cancelComposition() {
        guard let pending = composing else { return }
        composing = nil
        selection = pending
        applyReplace("")
    }

    /// Step-level entry for goldens that exercise the interpreter directly —
    /// blind-lane plans never survive the keystroke loop (`.press` counts as
    /// unsupported), but their clipboard steps still deserve pure coverage.
    @discardableResult
    public mutating func perform(_ steps: [PhysicalStep]) -> Bool {
        execute(steps) == nil
    }

    /// `Controller.rebind`'s pure twin: focus moved, and the transition says
    /// how much of the session survives. Lives here rather than in an
    /// extension because `monitor` and `openChange` are private — and they
    /// are exactly what the paired-halves invariant is about.
    ///
    /// Pass `text` to model a `sameDocument` swap literally: the next block
    /// is different text whose offsets restart at zero, which is precisely
    /// what makes the departing field's offsets fiction.
    public mutating func refocus(_ transition: FocusTransition, text: String? = nil, caret: Int = 0) {
        if !transition.preservesDrawnCursor {
            if let cursor = state.field.cursor,
               let release = PhysicalPlanner.releaseCursor(cursor, breaks: fieldBreaks, profile: profile) {
                executeAside(release)
            }
            fieldBreaks = nil
        }
        if transition != .sameElement {
            foundEmptyParagraphs = nil
            foundUnreachable = nil
        }
        if let text {
            self.text = text
            let clamped = TextModel(text).clamp(caret)
            selection = clamped..<clamped
            inListGap = nil
        }
        state.field = state.field.carried(across: transition)
        if transition.clearsChangeInFlight {
            monitor.reset()
            loop.openChange = nil
        }
    }

    /// A click in the bound field: the caret goes to `offset`, two button events are counted, and `Controller.pointerActed` runs.
    public mutating func click(at offset: Int) {
        releaseHeldHistory()
        let caret = TextModel(text).clamp(offset)
        selection = caret..<caret
        atChipStart = false
        codeInside = false
        atWrittenCodeEnd = false
        inListGap = nil
        backward = false
        buttonEvents &+= 2
        if state.field.mode.isInserting { monitor.markInsertLogLossy() }
    }
}

// MARK: - The loop's host

extension Sim: CommandHost {
    typealias Marked = Void
    typealias Witness = Void
    typealias RunRecord = Void

    mutating func commit(_ effect: VimEffect) {
        state = VimReducer.reduce(state, effect)
    }

    mutating func refuse(_ reason: CommandLoop<Sim>.Refusal) {
        bells += 1
    }

    // MARK: Input methods

    mutating func engage(_ token: String) -> Composition.Engage? {
        guard inputMethod else { return nil }
        return Composition.engage(token, read: { composition }, commit: {
            if !ignoresCommit { composing = nil }
            return failsReadAfterCommit ? .unknown : composition
        })
    }

    mutating func passToInputMethod() {
        monitor.markInsertLogLossy()
        cancelComposition()
    }

    var compositionRead: (() -> Composition)? {
        guard inputMethod else { return nil }
        let composition = composition
        return { composition }
    }

    // MARK: The command

    /// The keys go to the fake field until `focusLeaves` says otherwise.
    mutating func postingKeys<T>(_ body: (inout Sim) -> T) -> T {
        destination = KeyDestination(pid: 0, presses: buttonEvents, active: true)
        departure = nil
        appActive = true
        defer { destination = nil }
        return body(&self)
    }

    mutating func snapshot(anchor: Int?) -> CommandLoop<Sim>.Reading {
        var memo = foundEmptyParagraphs
        var unreachable = foundUnreachable
        func reading() -> (built: (snapshot: FieldSnapshot, memo: EmptyParagraphs.Memo?, unreachable: UnreachableLines.Memo?),
                           observed: Learning.Observation, value: String?) {
            var (reads, observed) = read()
            let built = FieldSnapshot.Step.run(taking: { take($0, into: &reads, memo: &memo, unreachable: &unreachable) }) {
                FieldSnapshot.build(
                    reads, capabilities: profile, answer: observed.after, anchor: anchor, cursor: state.field.cursor, memo: memo,
                    unreachable: unreachable
                )
            }
            return (built, observed, shownValue)
        }
        snapshotting = true
        var (built, observed, value) = reading()
        snapshotting = false
        // The Snapshotter waits for the caret drawn at a code span's end that ends a paragraph, whose `<br>` moves offsets.
        let caret = selection.lowerBound
        if drawsLate, built.snapshot.breaks != nil, !built.snapshot.holdsDrawnCaret, selection.isEmpty,
           isCodeEdge(caret, start: false), TextModel(text).lineBreak(of: caret) == caret {
            (built, observed, value) = reading()
        }
        foundEmptyParagraphs = built.memo
        foundUnreachable = built.unreachable
        fieldBreaks = built.snapshot.breaks
        return CommandLoop.Reading(snapshot: built.snapshot, observed: observed, value: value, generated: showsPlaceholder)
    }

    func missedRoutes(under offsets: OffsetsAnswer) -> Set<Route> {
        learner.map { $0.strikes.missed(judgedUnder: offsets, app: $0.versions.app) } ?? []
    }

    mutating func execute(_ plan: PhysicalPlan, paragraphs: Bool, generated: Bool) -> (executed: Bool, abortedAt: Int?) {
        let abortedAt = execute(plan.steps, generated: generated)
        abortedStep = abortedAt.map { plan.steps[$0] }
        return (abortedAt == nil, abortedAt)
    }

    mutating func record(
        _ completed: RawMonitor.Completed, logical: LogicalPlan, planned: PhysicalPlanner.Planning, from before: VimState.Mode,
        reading: CommandLoop<Sim>.Reading, executed: Bool
    ) {
        learn(from: reading.observed)
    }

    // MARK: The cleanup after a failed command

    func selectionRead(paragraphs: Bool) -> CommandLoop<Sim>.Selection? {
        guard !unreadableSelection else { return nil }
        let marked = paragraphs && (markers || emptyParagraphs)
        return CommandLoop.Selection(range: readSelection, caret: readsCaret(paragraphs: paragraphs), marked: marked ? () : nil)
    }

    func side(of marked: Void) -> ParagraphBreaks.Side? {
        chromium.side(selection.lowerBound)
    }

    func value() -> String? {
        shownValue
    }

    @discardableResult
    mutating func runAside(_ plan: PhysicalPlan, paragraphs: Bool) -> Bool {
        executeAside(plan)
    }

    /// The fake field shows a write as it is made.
    func becomesCaret(paragraphs: Bool) -> Bool {
        readsCaret(paragraphs: paragraphs)
    }

    // MARK: The landing after `u`

    mutating func leftDuringLanding(_ completed: RawMonitor.Completed) -> Bool {
        departs()
    }

    /// The landing's deadline counted in plans.
    mutating func attemptLanding<T>(_ body: (inout Sim) -> T) -> T {
        plansLeft = plansBeforeDeadline ?? .max
        defer { plansLeft = nil }
        return body(&self)
    }

    var witness: Void { () }

    func isField(of witness: Void) -> Bool { true }

    /// A late ⌘Z has landed by now, unless it shows only after the Controller's wait.
    mutating func awaitUndo(from value: String?) -> (shown: String?, waited: (polls: Int, milliseconds: Int)?) {
        (shownValue, nil)
    }

    /// The Controller waits here for a field still showing what `u` found.
    mutating func awaitResumed(_ pending: CommandLoop<Sim>.PendingUndo) -> String? {
        if shownValue == pending.value { releaseHeldHistory() }
        return shownValue
    }

    /// Keys reach the fake field as they are pressed.
    mutating func caretHolds() -> Bool { true }

    /// The field as it reads now, for a repair or a landing: unlike a run's snapshot it teaches nothing and keeps no discovery.
    mutating func snapshotAside() -> FieldSnapshot {
        let learned = learner
        defer { learner = learned }
        var (reads, observed) = read()
        if unansweredSelectionsAside > 0 {
            unansweredSelectionsAside -= 1
            reads.field.plain = nil
        }
        var memo = foundEmptyParagraphs
        var unreachable = foundUnreachable
        return FieldSnapshot.Step.run(taking: { take($0, into: &reads, memo: &memo, unreachable: &unreachable) }) {
            FieldSnapshot.build(
                reads, capabilities: profile, answer: observed.after, anchor: nil, cursor: state.field.cursor, memo: memo,
                unreachable: unreachable
            )
        }.snapshot
    }

    var pastDeadline: Bool { (plansLeft ?? 1) <= 0 }

    /// The deadline the Sim counts cuts plans, never a read.
    var readsRefused: Bool { false }

    mutating func runLanding(_ plan: PhysicalPlan, paragraphs: Bool) -> (ran: Bool, departure: KeyDestination.Departure?) {
        plansLeft = plansLeft.map { $0 - 1 }
        landing = true
        defer { landing = false }
        return (executeAside(plan, keys: PhysicalPlanner.undoKeys), departure)
    }

    var lastRun: Void { () }

    func traceLanding(_ trace: CommandLoop<Sim>.LandingTrace) {}
}

// MARK: - The step runner's host

extension Sim: StepHost {
    /// A settle's read of the fake field, which answers what its expectation does not ask about too.
    struct Read: SettleRead {
        let passed: Bool
        let selection: Range<Int>?
        let length: Int?
        let selectedText: String?
        let misfit: Range<Int>?
    }

    // Each read or write first lands the ⌘Z Chrome runs late, as a key or a commit does not.

    mutating func setSelection(_ range: Range<Int>) -> Int32? {
        landLateHistory()
        guard !swallowsSelect, !(landing && swallowsLandingSelect) else { return nil }
        let model = TextModel(text)
        var lower = model.clamp(landing(range.lowerBound))
        var upper = model.clamp(landing(range.upperBound))
        // Written at a chip's start, a selection's end moves past the chip, and a caret stops the next arrow.
        let atoms = chromium.atoms
        if !range.isEmpty, atoms.contains(lower) { lower += 1 }
        if !range.isEmpty, atoms.contains(upper) { upper += 1 }
        selection = pulledBack(min(lower, upper)..<max(lower, upper))
        atChipStart = selection.isEmpty && atoms.contains(lower)
        // Measured, a caret written at a code span's start lands outside it, one at its end inside.
        codeInside = selection.isEmpty && isCodeEdge(lower, start: false) && !isCodeEdge(lower, start: true)
        atWrittenCodeEnd = codeInside
        inListGap = nil
        backward = false
        coalescing = false
        return nil
    }

    mutating func replaceSelection(_ replacement: String) -> Int32? {
        landLateHistory()
        if !swallowsReplace { applyReplace(replacement) }
        return nil
    }

    mutating func beginPress(_ chord: Chord) -> Bool {
        pressUnsupported = false
        return true
    }

    mutating func sendKey(_ chord: Chord) {
        presses += 1
        guard takesKey, !pressUnsupported, !ignoredChords.contains(chord) else { return }
        if undoesAfterWait, [.undo, .redo].contains(chord) {
            heldHistory.append(chord)
        } else if undoesLate, [.undo, .redo].contains(chord) {
            lateHistory.append(chord)
        } else if !(emulatesKeys || Self.countedKeys.contains(chord) || [.undo, .redo].contains(chord))
                    || !press(reboundChords[chord] ?? chord) {
            unsupportedSteps += 1
            pressUnsupported = true
        }
    }

    mutating func endPress(_ chord: Chord) {
        if !undoesLate || ![.undo, .redo].contains(chord) { landLateHistory() }
    }

    mutating func typeText(_ typed: String) {
        landLateHistory()
        if takesKey { applyReplace(typed) }
    }

    mutating func cut() {
        landLateHistory()
        guard takesKey else { return }
        pasteboard = TextModel(text).substring(selection)
        applyReplace("")
    }

    mutating func copy() {
        landLateHistory()
        if takesKey { pasteboard = TextModel(text).substring(selection) }
    }

    mutating func paste(_ content: String?, at index: Int) -> KeyDestination.Departure? {
        landLateHistory()
        if takesKey { applyReplace(content ?? pasteboard ?? "") }
        return nil
    }

    mutating func selectedText() -> String? {
        landLateHistory()
        return readSelectedText
    }

    mutating func settle(_ expectation: Expectation, at index: Int, generated: Bool) -> Read {
        landLateHistory()
        let (passed, observed, length, misfit) = settles(expectation, generated: generated)
        return Read(passed: passed, selection: observed, length: length, selectedText: readSelectedText, misfit: misfit)
    }

    mutating func generates(_ run: Range<Int>) -> Bool {
        landLateHistory()
        return generatesText(run)
    }

    mutating func departure(fresh: Bool) -> KeyDestination.Departure? {
        departs() ? departure : nil
    }

    /// The executor's check before a key, which counts that key towards `focusLeaves` and decides where it lands.
    mutating func departure(beforeKeyOf step: PhysicalStep) -> KeyDestination.Departure? {
        let menu: Bool
        switch step {
        case .press(let chord, _): menu = Self.menuChords.contains(chord)
        case .typeText: menu = false
        default: menu = true
        }
        guard let takes = posts(menu: menu) else { return departure }
        takesKey = takes
        return nil
    }

    /// The deadline the Sim counts cuts plans, never a key.
    var keysPastDeadline: Bool { false }

    mutating func commit(_ effect: VimEffect, captures: [CaptureSlot: String]) {
        state = VimReducer.reduce(state, effect, captures: captures)
    }

    mutating func bell() {
        landLateHistory()
        bells += 1
    }

    /// The executor beeps here; the Sim counts the failure from the run.
    func refused(_ expectation: Expectation, _ read: Read, soft: Bool) {}
}
