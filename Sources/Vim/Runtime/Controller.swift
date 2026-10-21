import AppKit
import ApplicationServices
import Core

/// The runtime loop — `Sim`'s impure twin. Wires the tap's key events
/// through monitor → planners → executor against the currently-bound
/// field, and carries the runtime lore the Sim mirrors in pure form:
/// binding + probing on focus change, dot-body bookkeeping, and the
/// insert-payload commits.
///
/// The per-key path costs zero AX: the `FocusTracker` keeps the binding as
/// event-driven state, and `handle` only reads it (InputHub's contract —
/// the tap handler must return promptly). AX is spent where it counts:
/// focus changes, Esc, and command execution.
@MainActor
public final class Controller {
    public var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            tracker.setEnabled(enabled)
        }
    }

    /// Physical Esc engages Normal mode alongside ⌃[: the menu's Normal Mode Key.
    public var escapeEngages = false

    /// Mode channel for the menu-bar indicator, nil while unbound; setting it publishes the current mode.
    public var onModeChange: ((VimState.Mode?) -> Void)? {
        didSet {
            publishedMode = currentIndicatorMode
            onModeChange?(publishedMode)
        }
    }
    private var publishedMode: VimState.Mode?

    /// Fired whenever the binding changes, mode or no mode.
    ///
    /// The menu used to ride `onModeChange` for this, but `publishMode`
    /// early-returns on an unchanged indicator — so moving between two fields
    /// that are both in Normal fired nothing. That is exactly the case the
    /// capability rows care about: a browser's search box and an `<input>` in
    /// the page are different surfaces, and the menu would have gone on naming
    /// and configuring the one focus had left.
    public var onBindingChange: (() -> Void)?

    private let tracker = FocusTracker()
    private var monitor = RawMonitor()
    private var state = VimState.initial
    private let executor = Executor()

    /// Marker sampling for the bound field; a new element starts over.
    private var sampling = OffsetsSampling()

    /// The bound field's empty paragraphs, found again when its text changes.
    private var emptyParagraphs: EmptyParagraphs.Memo?

    /// Its list markers and chips, found again the same way.
    private var unreachable: UnreachableLines.Memo?

    /// Per-rung evidence this process, stored with the read model.
    private var tallies: [String: Tally] = [:]

    /// Per-rung refuted runs in a row this process; not stored, so a relaunch starts each count over.
    private var strikes: [String: Strikes] = [:]

    /// Mirror of the tracker's binding, held for unbind hygiene.
    private var binding: FocusTracker.Binding?

    /// The recorder's command counter; its other half, the epoch, is on the tracker.
    private var seq: UInt64 = 0

    /// The command that opened the current Insert session, recorded at its Esc.
    private var openChange: (source: String, count: Int?, register: Register?, mutated: Bool)?

    /// The last snapshot's, to convert the drawn cursor at unbind.
    private var fieldBreaks: ParagraphBreaks?

    /// When the app last got a letter in Insert mode, in uptime nanoseconds: an input method shows it pending only later.
    private var letterAt: UInt64?

    /// What a `u` found where its landing did not finish in time, which the next command resumes from `route`, telling the restored
    /// lines apart by `near`, the selection the undo left (LIN-2104).
    private var pendingUndo: (
        before: String, value: String?, sent: Date, route: Int, near: Range<Int>?, element: AXUIElement, clicks: UInt32
    )?

    public init() {
        tracker.onRebind = { [weak self] binding, transition in
            self?.rebind(to: binding, transition: transition)
        }
        tracker.onPointerAction = { [weak self] in self?.pointerActed() }
        // Force the recorder's one store read off the tap callback's first command.
        _ = Diag.recordsText
    }

    /// Starts focus tracking, once. Only with Accessibility granted: its click monitor costs a process without it its tap.
    public func start() {
        tracker.start()
    }

    /// A click in a forced app moved the caret invisibly — Normal-mode
    /// offsets are fiction now. Back to the entry policy.
    private func pointerActed() {
        if state.field.mode.isInserting { monitor.markInsertLogLossy() }
        guard let binding, binding.isForced, state.field.mode != .insert else { return }
        monitor.reset()
        state.field = VimState.Field(mode: .insert)
        openChange = nil
        publishMode()
    }

    /// The disable list changed (menu toggle): re-evaluate the binding now.
    public func refreshPolicy() {
        tracker.refreshPolicy()
    }

    /// The bound field's capability resolution, for the menu's rows; nil when unbound or forced.
    public var capabilityReport: CapabilityReport? { binding?.capabilityReport }

    /// The bound field's beliefs, for the menu's Learned section; nil when unbound or forced.
    public var boundBeliefs: ResolvedBeliefs? { binding?.beliefs }

    /// What the menu configures and names; its bundle ID keeps rows to their own app, since overlays bind across apps.
    public var boundSurface: Surface? { binding?.surface }

    /// A capability override changed (menu): rebuild the binding's profile
    /// now. Deliberately not `refreshPolicy` — its same-element
    /// short-circuit never re-probes.
    public func refreshCapabilities() {
        tracker.reresolveCapabilities()
    }

    /// The menu's On, Off or Auto, written to the beliefs file with the belief it retires.
    public func setOverride(
        _ override: CapabilityConfig.Override?, at rung: String?, on surface: Surface, for capability: Capability
    ) {
        updateBeliefs { contents in
            contents.overrides = CapabilityConfig.setting(
                override, at: rung, on: surface, capability: capability.rawValue, in: contents.overrides
            )
            if override != nil, let role = surface.roleRung { contents.retire(capability, at: role) }
        }
    }

    public func clearOverrides(atAndBelow rung: String, on surface: Surface) {
        updateBeliefs { $0.overrides = CapabilityConfig.clearing(atAndBelow: rung, on: surface, in: $0.overrides) }
    }

    /// The menu's Try Again and Forget.
    public func forget(_ beliefs: [Belief]) {
        updateBeliefs { $0.forget(beliefs) }
    }

    /// The beliefs file, for the menu to open.
    public var beliefsURL: URL { Beliefs.shared.url }

    /// The overrides uvim applies; not from the file while it does not read, but from the last version that did.
    public func appliedOverrides() -> (overrides: SurfaceLadder.UserStore, fromFile: Bool) {
        let current = Beliefs.shared.current()
        return (current.contents.overrides, current.problem == nil)
    }

    private func updateBeliefs(_ change: (inout Beliefs.Contents) -> Void) {
        do {
            try Beliefs.shared.update(change)
        } catch {
            Diag.beliefsFile(error)
        }
    }

    /// The `InputHub` handler: returns the consume verdict. Zero AX on the
    /// steady paths (insert typing, unbound apps, ⌘-chords); one bounded
    /// resolve on Esc and one verify before running a completed command.
    public func handle(_ event: KeyEvent) -> Bool {
        let consumed = route(event)
        // A key the app gets can move the caret or change the text a pending landing was read from.
        if !consumed, event.kind == .keyDown { pendingUndo = nil }
        return consumed
    }

    private func route(_ event: KeyEvent) -> Bool {
        // The user's own paste reads the pasteboard, so it ends a register paste's loan first, even while disabled.
        if event.kind == .keyDown, event.mods.contains(.command), event.characters.lowercased() == "v" || event.keyCode == 9 {
            PasteboardLoan.shared.restore()
        }
        guard enabled, event.kind == .keyDown else { return false }
        // ⌃f/⌃b always tokenize; the field a command runs on may hand them back below.
        guard let token = gate(event, profile: Self.readsAppKeys) else {
            // The app gets this key, so a half-typed command must not outlive
            // it: the app may move the caret, and a later key would complete
            // the command against a position the user never aimed at (`d`,
            // ⌥←, `w` would delete a word somewhere else entirely).
            monitor.cancelPending()
            if state.field.mode.isInserting { monitor.markInsertLogLossy() }
            return false
        }

        // An engage key is where a stale binding has teeth: a rate-limited full re-check.
        if Self.engageTokens.contains(token) { tracker.reverify() }

        guard var binding = tracker.bindingForKeydown() else { return false }

        // Free staleness guard: catches app switches even from apps that
        // never emit AX notifications. Overlay bindings are exempt — their
        // pid legitimately differs from the frontmost app's.
        if !binding.isOverlay,
           binding.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            tracker.scheduleReverify()
            return false
        }

        let mode: RawMonitor.Mode
        switch state.field.mode {
        case .normal: mode = .normal
        case .visual: mode = .visual
        case .insert, .replace: mode = .insert
        }

        if mode == .insert, Self.engageTokens.contains(token), let method = InputSource.selectedMethod(),
           let engaged = engage(token, on: binding, method: method) {
            return engaged
        }

        // Insert-mode non-Esc tokens must keep flowing through the monitor:
        // they build the insert log the dot body replays.
        switch monitor.feed(token, mode: mode, clicks: mode == .insert ? nil : Self.buttonEvents()) {
        case .passthrough:
            if mode == .insert {
                if token.count == 1, token.first?.isASCII == true, token.first?.isLetter == true {
                    letterAt = DispatchTime.now().uptimeNanoseconds
                }
                // An input method turns these keys into text the log cannot say, so `.` must not replay them.
                if InputSource.selectedMethod() != nil { monitor.markInsertLogLossy() }
            }
            return false
        case .pending, .cancelled:
            guard gate(event, profile: binding.capabilities) != nil else {
                monitor.cancelPending()
                return false
            }
            return true
        case .command(let completed):
            // Numbered here, not in `run`, so the three silent drops below are too.
            seq &+= 1
            let commandSeq = seq
            // Read before the checks below, so the focus moving after them stops the command's keys.
            var destination = KeyDestinationReads.verified(binding.pid)
            // Never mutate a field focus has left (an overlay emits no event); an engage key already reverified.
            if !Self.engageTokens.contains(token) {
                if binding.isForced {
                    // AX-silent apps resolve no focused element — the
                    // element check would swallow every command. Verify at
                    // the granularity forced bindings have: (pid, window).
                    guard binding.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                          AX.frontWindow(of: binding.pid)?.id == binding.windowID else {
                        drop(completed, commandSeq, "stale-forced")
                        return refusesForPendingUndo()
                    }
                } else {
                    guard let focused = tracker.focusedField() else {
                        drop(completed, commandSeq, "no-focused-element")
                        return refusesForPendingUndo()
                    }
                    if !CFEqual(focused, binding.element) {
                        // The field moved under us. In a block editor that is
                        // routinely OUR doing — the previous command's blind
                        // chord crossed into the next block — and the AX
                        // notification may not have landed yet. Same document
                        // ⇒ retarget and run; bailing here would both destroy
                        // the command and type its final key into the text.
                        guard let moved = tracker.retarget(to: focused, from: binding) else {
                            // Destroys the command AND swallows its final key.
                            drop(completed, commandSeq, "retarget-failed")
                            return refusesForPendingUndo()
                        }
                        binding = moved
                    }
                }
            }
            guard gate(event, profile: binding.capabilities) != nil else {
                Diag.dropped(tracker.epoch, commandSeq, command: completed.command, reason: "app-key")
                return false
            }
            // Pending letters take the field's keys and selection, so a command would misfire and teach uvim wrong.
            if mode != .insert, let method = InputSource.selectedMethod(), !Composition.runs(completed.command, read: {
                CompositionReads.answer(of: binding, method: method, letter: letterAt)
            }) {
                NSSound.beep()
                Diag.dropped(tracker.epoch, commandSeq, command: completed.command, reason: "composing")
                return true
            }
            // No command plans on the line above lines an undo put back while their landing cannot finish.
            guard landPendingUndo(on: binding, seq: commandSeq, destination: &destination) else {
                NSSound.beep()
                Diag.dropped(tracker.epoch, commandSeq, command: completed.command, reason: "undo-landing")
                return true
            }
            run(completed, on: binding, seq: commandSeq, destination: destination)
            // Publish even on mid-plan aborts: a .setMode commit may have
            // landed before a later step failed.
            publishMode()
            return true
        }
    }

    /// A key whose command uvim drops is refused while a landing after `u` is pending, not typed into the field (LIN-2104).
    private func refusesForPendingUndo() -> Bool {
        guard pendingUndo != nil else { return false }
        NSSound.beep()
        return true
    }

    private static let readsAppKeys = CapabilityProfile(available: [.nativeMotions])

    private static let engageTokens: Set<String> = ["<C-[>", "<Esc>"]

    private func gate(_ event: KeyEvent, profile: CapabilityProfile) -> String? {
        KeyNotation.token(for: event, profile: profile, escapeEngages: escapeEngages)
    }

    /// The session's button presses and releases, which the window server counts in step with the tap's keys, as no monitor does.
    private static func buttonEvents() -> UInt32 {
        [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

    /// A completed command verify-before-run threw away, then handed to its reverify.
    private func drop(_ completed: RawMonitor.Completed, _ seq: UInt64, _ reason: String) {
        Diag.dropped(tracker.epoch, seq, command: completed.command, reason: reason)
        tracker.reverify(force: true)
    }

    /// An engage key in Insert mode with an input method selected: its consume verdict, or nil to enter Normal mode.
    private func engage(_ token: String, on binding: FocusTracker.Binding, method: String) -> Bool? {
        let start = DispatchTime.now().uptimeNanoseconds
        var answers: [Composition] = []
        let engaged = Composition.engage(token, read: {
            answers.append(CompositionReads.answer(of: binding, method: method, letter: letterAt))
            return answers[answers.count - 1]
        }, commit: {
            answers.append(CompositionReads.commit(on: binding, method: method))
            return answers[answers.count - 1]
        })
        Diag.engaged(tracker.epoch, key: token, method: method, answers: answers, engaged, since: start)
        switch engaged {
        case .normal:
            return nil
        case .passThrough:
            monitor.markInsertLogLossy()
            return false
        case .refuse:
            NSSound.beep()
            return true
        }
    }

    /// Focus moved (tracker event). The element plumbing is unconditional;
    /// how much of the *session* survives is the transition's call — see
    /// `FocusTransition`. A block crossing keeps the mode it was in, because
    /// a vim motion causing it is not the user going somewhere new.
    private func rebind(to new: FocusTracker.Binding?, transition: FocusTransition) {
        if !transition.preservesDrawnCursor, let old = binding, let cursor = state.field.cursor,
           let release = PhysicalPlanner.releaseCursor(cursor, breaks: fieldBreaks, profile: old.capabilities) {
            // Through the executor, which owns all field writes; a dead element rejects it harmlessly (and bounded).
            executor.execute(release, on: old.element, state: &state)
        }
        if !transition.preservesDrawnCursor { fieldBreaks = nil }
        if transition != .sameElement {
            pendingUndo = nil
            sampling = OffsetsSampling()
            emptyParagraphs = nil
            unreachable = nil
        }
        binding = new
        Diag.bind(tracker.epoch, transition, new)
        // Keys-in-flight and the open dot body are one unit, and neither
        // holds an offset — a block crossing does not stale them.
        if transition.clearsChangeInFlight {
            monitor.reset()
            openChange = nil
        }
        state.field = state.field.carried(across: transition)
        publishMode()
        // Unconditional, unlike publishMode: a same-mode rebind still changes
        // which surface the menu describes.
        onBindingChange?()
    }

    private var currentIndicatorMode: VimState.Mode? {
        binding == nil ? nil : state.field.mode
    }

    private func publishMode() {
        let mode = currentIndicatorMode
        guard !Self.sameIndicator(mode, publishedMode) else { return }
        publishedMode = mode
        onModeChange?(mode)
    }

    /// Case identity only — visual anchor churn must not re-render the icon.
    private static func sameIndicator(_ a: VimState.Mode?, _ b: VimState.Mode?) -> Bool {
        switch (a, b) {
        case (nil, nil), (.normal?, .normal?), (.insert?, .insert?),
             (.replace?, .replace?), (.visual?, .visual?):
            return true
        default:
            return false
        }
    }

    private func run(
        _ completed: RawMonitor.Completed, on binding: FocusTracker.Binding, seq commandSeq: UInt64, destination: KeyDestination
    ) {
        // Every plan below posts its keys to the bound field's process, and only while the focus stays.
        executor.destination = destination
        defer { executor.destination = nil }
        let command = completed.command
        let logical = LogicalPlanner.plan(command, state: state)
        var anchor: Int?
        var visual = false
        if case .visual(let context) = state.field.mode {
            (anchor, visual) = (context.anchor, true)
        }
        let reading = Snapshotter.snapshot(
            of: binding.element,
            capabilities: binding.capabilities,
            anchor: anchor,
            cursor: state.field.cursor,
            chromium: binding.isChromium,
            model: binding.beliefs?.readModel ?? ReadModel(answer: .value),
            sampling: sampling,
            known: emptyParagraphs,
            knownUnreachable: unreachable
        )
        if reading.emptyParagraphs != emptyParagraphs, let memo = reading.emptyParagraphs {
            Diag.emptyParagraphs(tracker.epoch, commandSeq, memo)
        }
        emptyParagraphs = reading.emptyParagraphs
        if reading.unreachable != unreachable, let memo = reading.unreachable {
            Diag.unreachable(tracker.epoch, commandSeq, memo)
        }
        unreachable = reading.unreachable
        if reading.sampled {
            sampling.sampled(markers: reading.markers, evidence: reading.observed.evidence, text: reading.reads.text,
                             plain: reading.reads.plain)
        }
        let snapshot = reading.snapshot
        fieldBreaks = snapshot.breaks
        let paragraphs = snapshot.breaks != nil
        let planned = PhysicalPlanner.planning(
            logical, snapshot: snapshot, missed: missedRoutes(on: binding, under: reading.observed.after), visual: visual
        )
        let physical = planned.plan
        let epoch = tracker.epoch
        let before = state.field.mode
        let executed = executor.execute(
            physical, on: binding.element, state: &state, paragraphs: paragraphs, generated: reading.generated > 0
        )
        // Harvested before anything else can touch the executor: the abort path
        // below runs `repairStrandedSelection`, which executes its own plan and
        // resets `lastRun` — and that is precisely the path a failed write takes.
        let evidence = executor.lastRun
        // Deferred so it runs after hygiene and the dot bookkeeping, on both
        // paths, and so the republish a commit triggers happens as `run`
        // unwinds rather than re-entering the tracker mid-command.
        defer { learn(from: evidence, reading: reading, on: binding, epoch: epoch, seq: commandSeq) }
        // Declared second so LIFO runs it first, before the republish it may cause.
        defer {
            Diag.command(
                epoch, commandSeq,
                command: command,
                from: before, to: state.field.mode,
                plan: physical,
                rejection: planned.rejection,
                bell: Self.bellReason(logical),
                executed: executed,
                evidence: evidence,
                insertPayload: completed.insertPayload,
                emptyLines: snapshot.valueGap,
                foldedLength: snapshot.foldedLength,
                generated: reading.generated
            )
        }
        guard executed else {
            if planned.abortedAtTextCheck(evidence.abortedAt) {
                // Other text than the plan meant was selected, so the mode it asked for goes too.
                if let read = selection(of: binding.element, paragraphs: paragraphs), !read.caret {
                    let collapse = PhysicalPlanner.collapse(
                        read.range, misread: true, toEnd: planned.collapsesToEnd, profile: binding.capabilities
                    )
                    executor.execute(collapse, on: binding.element, state: &state, paragraphs: paragraphs)
                    _ = becomesCaret(binding.element, paragraphs: paragraphs)
                }
                if state.field.mode.isInserting {
                    executor.commit(.setMode(before.nonVisual), state: &state)
                }
            } else if !repairStrandedSelection(on: binding, operand: planned.operand, toEnd: planned.collapsesToEnd,
                                               reading: reading),
                      state.field.mode.isInserting {
                // A selection we could not collapse is one the app would type over.
                executor.commit(.setMode(before.nonVisual), state: &state)
            }
            // `RawMonitor` drained the payload it will never offer again.
            if let payload = completed.insertPayload, !state.field.mode.isInserting {
                closeInsertSession(payload, lossless: completed.insertPayloadIsLossless)
            }
            recordChange(for: command, from: before, mutated: physical.mutatesText, aborted: true)
            return
        }

        if let payload = completed.insertPayload {
            closeInsertSession(payload, lossless: completed.insertPayloadIsLossless)
        }

        recordChange(for: command, from: before, mutated: physical.mutatesText)
        if logical.steps.contains(.history(.undo)), let text = snapshot.text {
            landUndo(from: text, reading: reading, on: binding, seq: commandSeq)
        }
    }

    /// Puts the cursor on the lines `u` put back, as Vim does, from the field as the undo left it, or leaves that to the next
    /// command where the field has not shown them in time.
    private func landUndo(from before: String, reading: Snapshotter.Reading, on binding: FocusTracker.Binding, seq: UInt64) {
        // Counted before the landing, so a click during it drops what it leaves.
        let (start, clicks) = (Date(), Self.buttonEvents())
        // A read may take the whole messaging timeout, and no key is handled meanwhile (LIN-2104).
        AX.until(start.addingTimeInterval(0.5)) {
            // Chrome can apply ⌘Z after reads that follow it, and a read it cannot answer yet is no change (LIN-1980).
            var waited = 0
            var shown = AX.value(of: binding.element)
            while (shown ?? reading.value) == reading.value, waited < 25, !AX.pastDeadline {
                Thread.sleep(forTimeInterval: 0.01)
                waited += 1
                shown = AX.value(of: binding.element)
            }
            let wait = (waited, Int(Date().timeIntervalSince(start) * 1000))
            // A field that left the last read unanswered would leave a snapshot unanswered too.
            guard shown != nil else {
                pendingUndo = (before, reading.value, start, 0, nil, binding.element, clicks)
                return Diag.undoLanding(
                    tracker.epoch, seq, plan: nil, executed: true, evidence: executor.lastRun, waited: wait,
                    lengths: (before.utf16.count, nil), fallbacks: [], route: 0
                )
            }
            let landed = landRestoredLines(after: before, changed: shown != reading.value, on: binding, seq: seq, waited: wait)
            if !landed.finished {
                pendingUndo = (before, reading.value, start, landed.route, landed.near, binding.element, clicks)
            }
        }
    }

    /// The landing a `u` left to this command, before it plans, its keys going where the command's will; false where it still
    /// cannot finish.
    private func landPendingUndo(on binding: FocusTracker.Binding, seq: UInt64, destination: inout KeyDestination) -> Bool {
        guard let pending = pendingUndo else { return true }
        // A click, or another field, leaves the caret somewhere the undo did not put it.
        guard CFEqual(pending.element, binding.element), pending.clicks == Self.buttonEvents() else {
            pendingUndo = nil
            return true
        }
        executor.destination = destination
        // A focus that left during the landing stops the command's keys from its first.
        defer { (destination, executor.destination) = (executor.destination ?? destination, nil) }
        let start = Date()
        let landed = AX.until(start.addingTimeInterval(0.5)) {
            // An undo can show only after `u` gave up on it, while this key waited behind that `u`; half the time stays to land.
            let shownBy = min(pending.sent.addingTimeInterval(1), start.addingTimeInterval(0.25))
            var shown = AX.value(of: binding.element)
            var waited = 0
            while (shown ?? pending.value) == pending.value, Date() < shownBy, waited < 25 {
                Thread.sleep(forTimeInterval: 0.01)
                waited += 1
                shown = AX.value(of: binding.element)
            }
            guard shown != nil else { return (finished: false, route: pending.route, near: pending.near) }
            return landRestoredLines(
                after: pending.before, changed: true, on: binding, seq: seq, waited: nil, resumed: (pending.route, pending.near)
            )
        }
        if landed.finished {
            pendingUndo = nil
        } else {
            pendingUndo?.route = landed.route
            pendingUndo?.near = landed.near
        }
        return landed.finished
    }

    /// Lands on the lines an undo put back since `before` by its routes in turn, from `resumed`, where a pending landing stopped:
    /// the walk to Vim's place, then for lines that end the text the two fallbacks, each pressing at most `undoKeys` keys. Finished
    /// where the walk lands, a fresh read shows the cursor on those lines, every route ran its course without bringing it nearer,
    /// or the field shows no such lines although it has `changed`; otherwise the result's `route` is the one the next attempt runs,
    /// and `near` the selection that told those lines apart.
    private func landRestoredLines(
        after before: String, changed: Bool, on binding: FocusTracker.Binding, seq: UInt64,
        waited: (polls: Int, milliseconds: Int)?, resumed: (route: Int, near: Range<Int>?)? = nil
    ) -> (finished: Bool, route: Int, near: Range<Int>?) {
        // Only a read that answered the text and, in a field whose caret uvim reads, the caret decides anything.
        func answered(_ field: FieldSnapshot) -> Bool {
            field.text != nil && !AX.pastDeadline && (field.selection != nil || !field.capabilities.has(.readCaret))
        }
        // Keys an earlier attempt sent can still be on their way; a caret holding still is taken as where they leave it.
        let still = resumed == nil || caretHolds(binding)
        let after = snapshotAside(binding)
        // Equal lines are told apart by the selection the undo left, which a landing's keys have since moved.
        let near = resumed?.near ?? after.selection
        let found = still && answered(after) ? PhysicalPlanner.undoLanding(before: before, snapshot: after, near: near) : nil
        func distance(_ field: FieldSnapshot) -> Int? {
            guard let found, let at = field.selection?.lowerBound else { return nil }
            if at < found.lines.lowerBound { return found.lines.lowerBound - at }
            return found.ending == nil ? max(0, at - found.lines.upperBound + 1) : 0
        }
        // A resumed landing can find the cursor on the lines already, where the app showed its last keys late.
        var finished = found == nil ? still && answered(after) && changed : resumed != nil && distance(after) == 0
        var (field, route, routes) = (after, resumed?.route ?? 0, found?.ending == nil ? 1 : 3)
        var (walk, executed, evidence, fallbacks) = (PhysicalPlan?.none, true, executor.lastRun, [PhysicalPlan]())
        while let found, !finished, route < routes, !AX.pastDeadline {
            guard let plan = route == 0 ? found.plan
                    : PhysicalPlanner.undoFallback(onto: found.lines, snapshot: field, selecting: route == 2) else {
                route += 1
                continue
            }
            let ran = AX.keys(PhysicalPlanner.undoKeys) {
                executor.execute(plan, on: binding.element, state: &state, paragraphs: field.breaks != nil)
            }
            if route == 0 { (walk, executed, evidence) = (plan, ran, executor.lastRun) } else { fallbacks.append(plan) }
            // The focus leaving ends the landing as it ends a command, and a click or another field would drop it anyway.
            if let left = executor.lastRun.departure {
                (evidence.departure, finished) = (left, true)
                break
            }
            // The walk's checks put the cursor on Vim's place, and where no caret reads nothing can confirm more, as in #64.
            if route == 0, ran || field.selection == nil {
                finished = true
                break
            }
            guard caretHolds(binding) else { break }
            let now = snapshotAside(binding)
            guard answered(now), let from = distance(field), let to = distance(now) else { break }
            field = now
            // Nearer, the same route again at the next attempt; no nearer, the next route now.
            if to == 0 { finished = true } else if to < from { break } else { route += 1 }
        }
        // Every route ran its course without bringing the cursor nearer, as #64's fallbacks could fail.
        if found != nil, route >= routes { finished = true }
        Diag.undoLanding(
            tracker.epoch, seq, plan: walk, executed: executed, evidence: evidence, waited: waited,
            lengths: (before.utf16.count, after.text?.utf16.count), fallbacks: fallbacks, route: finished ? nil : route
        )
        return (finished, route, found == nil ? resumed?.near : near)
    }

    /// Whether the caret read the same for 60 ms before `AX.until`'s deadline, longer than any gap measured between a route's keys
    /// landing (LIN-2104): a sign, not proof, that the keys a landing sent are handled; true where uvim reads no caret.
    private func caretHolds(_ binding: FocusTracker.Binding) -> Bool {
        guard binding.capabilities.has(.readCaret) else { return true }
        var (last, since) = (AX.selectedRange(of: binding.element), Date())
        while !AX.pastDeadline {
            Thread.sleep(forTimeInterval: 0.02)
            let now = AX.selectedRange(of: binding.element)
            if let now, let last, now.location == last.location, now.length == last.length {
                if Date().timeIntervalSince(since) >= 0.06 { return true }
            } else {
                since = Date()
            }
            last = now
        }
        return false
    }

    /// The field as it reads now, outside a command, as the Sim's `snapshotAside` reads it.
    private func snapshotAside(_ binding: FocusTracker.Binding) -> FieldSnapshot {
        Snapshotter.snapshot(
            of: binding.element, capabilities: binding.capabilities, anchor: nil, cursor: state.field.cursor,
            chromium: binding.isChromium, model: binding.beliefs?.readModel ?? ReadModel(answer: .value),
            sampling: sampling, known: emptyParagraphs, knownUnreachable: unreachable
        ).snapshot
    }

    /// Fold a just-ended Insert session into the dot memories.
    private func closeInsertSession(_ payload: String, lossless: Bool) {
        if !payload.isEmpty {
            executor.commit(.setLastInsert(payload), state: &state)
        }
        guard let change = openChange else { return }
        openChange = nil
        guard lossless else {
            executor.commit(.setLastChange(.unreplayable), state: &state)
            return
        }
        // An empty session is still a change if its entry mutated (`ciw`, `o`).
        guard change.mutated || !payload.isEmpty else { return }
        executor.commit(.setLastChange(VimState.ChangeMemory(
            body: change.source,
            count: change.count,
            register: change.register,
            insert: payload
        )), state: &state)
    }

    /// The lowering drops `BellReason`, but it never had to survive the planner.
    private static func bellReason(_ logical: LogicalPlan) -> LogicalStep.BellReason? {
        for step in logical.steps {
            if case .bell(let reason) = step { return reason }
        }
        return nil
    }

    /// The optional routes to plan without: those that missed at the rung, or all where no rung remembers a miss.
    private func missedRoutes(on binding: FocusTracker.Binding, under offsets: OffsetsAnswer) -> Set<Route> {
        guard binding.beliefs != nil, let rung = binding.surface.roleRung else { return Set(Route.allCases) }
        return strikes[rung]?.missed(judgedUnder: offsets, app: binding.versions.app) ?? []
    }

    /// A change applies at once, keeping the session (`.sameElement`), so the next command routes around it.
    private func learn(
        from evidence: Executor.RunEvidence, reading: Snapshotter.Reading, on binding: FocusTracker.Binding,
        epoch: UInt64, seq: UInt64
    ) {
        let run = evidence.attribution.evidence
        let observed = reading.observed
        let items = (observed.evidence.map { [$0] } ?? []) + run
        Diag.evidence(epoch, seq, items)
        // Checks made after the focus left judged keys it may have taken elsewhere in the app.
        guard evidence.departure == nil else {
            Diag.notLearned(epoch, seq, reason: "left", items.filter(Learning.teaches))
            return
        }
        // A forced binding resolves nothing to learn against.
        guard let beliefs = binding.beliefs else { return }
        let model = beliefs.readModel
        let teaching = items.filter(Learning.teaches)
        // No role means no stable key to accumulate against.
        guard let rung = binding.surface.roleRung else {
            Diag.notLearned(epoch, seq, reason: "no-rung", teaching)
            return
        }
        if observed.source.observes {
            for item in items { tallies[rung, default: Tally()].count(item) }
        }
        strikes[rung]?.pass(run)
        if let route = evidence.attribution.missedRoute {
            strikes[rung, default: Strikes()].miss(route, judgedUnder: observed.after, app: binding.versions.app)
        }
        guard !teaching.isEmpty || observed.after != model.answer else { return }
        var lesson = Learning.Lesson()
        let before = strikes[rung] ?? Strikes()
        var after = before
        do {
            try Beliefs.shared.update { contents in
                var store = contents.store
                let overrides = contents.overrides
                // `update` reapplies this to a file saved meanwhile, so each try counts from the same strikes.
                after = before
                lesson = Learning.learn(
                    store: &store, strikes: &after, rung: rung, versions: binding.versions, model: model,
                    observed: observed, run: run,
                    // The user has the last word: once they set an atom, stop inferring about it.
                    overridden: {
                        CapabilityConfig.resolve(binding.surface, capability: $0.rawValue, overrides: overrides).override != nil
                    },
                    provenance: Beliefs.provenance(tag: "e\(epoch).c\(seq)"), tally: tallies[rung] ?? Tally()
                )
                contents.store = store
            }
        } catch {
            Diag.beliefsFile(error)
            Diag.notLearned(epoch, seq, reason: "beliefs-file", teaching)
            return
        }
        strikes[rung] = after.isEmpty ? nil : after
        Diag.learned(epoch, seq, lesson, rung: rung, versions: binding.versions)
        if lesson.republish { tracker.reresolveCapabilities() }
    }

    /// Collapse a stranded selection, and report whether the field is safe to type into.
    private func repairStrandedSelection(
        on binding: FocusTracker.Binding, operand: Range<Int>?, toEnd: Bool, reading: Snapshotter.Reading
    ) -> Bool {
        let paragraphs = reading.snapshot.breaks != nil
        // Unknown is not empty: a settle can fail *because* the read went dark.
        guard let read = selection(of: binding.element, paragraphs: paragraphs) else { return false }
        guard !read.caret else { return true }
        // Still the operand: the app's own editor substitutes on the first keystroke.
        if state.field.mode.isInserting, read.range == operand { return true }
        var side: ParagraphBreaks.Side?
        var snapshot: FieldSnapshot?
        if let marked = read.marked {
            side = Snapshotter.paragraphSide(of: marked, upper: false)
            // An edit, or a caret Linear drew or took away, leaves the run's snapshot describing other text.
            snapshot = AX.value(of: binding.element) == reading.value ? reading.snapshot : Snapshotter.snapshot(
                of: binding.element, capabilities: binding.capabilities, anchor: nil, cursor: state.field.cursor,
                chromium: binding.isChromium, model: binding.beliefs?.readModel ?? ReadModel(answer: .value),
                sampling: sampling, known: emptyParagraphs, knownUnreachable: unreachable
            ).snapshot
        }
        let collapse = PhysicalPlanner.collapse(
            read.range, side: side, paragraphs: paragraphs, snapshot: snapshot, toEnd: toEnd, profile: binding.capabilities
        )
        let settled = executor.execute(collapse, on: binding.element, state: &state, paragraphs: paragraphs)
        // Keys the field ignored fail their settle, and a write lane then writes the start as it was read.
        if !settled, binding.capabilities.has(.writeSelection) {
            let asRead = PhysicalPlanner.collapse(read.range, paragraphs: paragraphs, profile: binding.capabilities)
            executor.execute(asRead, on: binding.element, state: &state, paragraphs: paragraphs)
        }
        // The write that stranded this may be the one that lies, so confirm.
        return becomesCaret(binding.element, paragraphs: paragraphs)
    }

    /// Whether the selection reads as a caret within 100 ms: Chromium shows a write or key milliseconds after it is sent,
    /// and a command typed ahead would plan on the selection still shown (LIN-1931).
    private func becomesCaret(_ element: AXUIElement, paragraphs: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(0.1)
        while let read = selection(of: element, paragraphs: paragraphs) {
            if read.caret || Date() >= deadline { return read.caret }
            Thread.sleep(forTimeInterval: 0.003)
        }
        return false
    }

    /// In field offsets, through the markers (`marked`) in a text-content field, where a selected paragraph break is no caret.
    private func selection(
        of element: AXUIElement, paragraphs: Bool
    ) -> (range: Range<Int>, caret: Bool, marked: AX.MarkedSelection?)? {
        guard paragraphs, let marked = Snapshotter.markedSelection(of: element) else {
            return AX.selectedRange(of: element).map { ($0.location..<($0.location + $0.length), $0.length == 0, nil) }
        }
        return (marked.range, marked.isCollapsed, marked)
    }

    /// Records a mutating command as `lastChange`, or opens a body if it entered Insert.
    private func recordChange(
        for command: RawCommand, from before: VimState.Mode, mutated: Bool, aborted: Bool = false
    ) {
        if case .repeat = command.intent { return }
        // An aborted plan mutated nothing, whatever its steps intended.
        let changed = mutated && !aborted
        if case .visual = before {
            // Visual keys name a selection `.` cannot rebuild.
            if changed || state.field.mode.isInserting {
                executor.commit(.setLastChange(.unreplayable), state: &state)
            }
            return
        }
        if state.field.mode.isInserting {
            if openChange == nil {
                openChange = (command.source, command.count, command.register, changed)
            }
            return
        }
        guard changed else { return }
        executor.commit(.setLastChange(VimState.ChangeMemory(
            body: command.source,
            count: command.count,
            register: command.register
        )), state: &state)
    }
}
