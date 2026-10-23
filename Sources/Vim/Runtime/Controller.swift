import AppKit
import ApplicationServices
import Core

/// The runtime: routes the tap's key events through the monitor to the `CommandLoop`, which runs each command against the bound
/// field through `Host`, the runtime's AX reads, keys and waits; and binds and probes fields as the focus moves.
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

    /// The open change for `.` and the landing pending after `u`.
    private var loop = CommandLoop<Host>()

    /// The last snapshot's, to convert the drawn cursor at unbind.
    private var fieldBreaks: ParagraphBreaks?

    /// When the app last got a letter in Insert mode, in uptime nanoseconds: an input method shows it pending only later.
    private var letterAt: UInt64?

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
        loop.openChange = nil
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
        if !consumed, event.kind == .keyDown { loop.pendingUndo = nil }
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

        if mode == .insert, Self.engageTokens.contains(token) {
            var host = Host(controller: self, binding: binding, seq: seq)
            if let engaged = CommandLoop.engage(token, host: &host) { return engaged }
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
            let destination = KeyDestinationReads.verified(binding.pid)
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
            var host = Host(controller: self, binding: binding, seq: commandSeq, destination: destination)
            if CommandLoop.command(completed, mode: mode, host: &host) {
                // Publish even on mid-plan aborts: a .setMode commit may have
                // landed before a later step failed.
                publishMode()
            }
            return true
        }
    }

    /// A key whose command uvim drops is refused while a landing after `u` is pending, not typed into the field (LIN-2104).
    private func refusesForPendingUndo() -> Bool {
        guard loop.pendingUndo != nil else { return false }
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
            loop.pendingUndo = nil
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
            loop.openChange = nil
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
        from evidence: Executor.RunEvidence, observed: Learning.Observation, on binding: FocusTracker.Binding,
        epoch: UInt64, seq: UInt64
    ) {
        let run = evidence.attribution.evidence
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
}

// MARK: - The loop's host

extension Controller {
    /// One command's host for the loop against `binding`: every AX read, key, wait and record of the runtime's.
    @MainActor struct Host: @MainActor CommandHost {
        /// When `u` was sent, and the field it ran in.
        struct Witness {
            let sent: Date
            let element: AXUIElement
        }

        unowned let controller: Controller
        let binding: FocusTracker.Binding
        /// The command's number, and where its keys go; an engage key has neither of its own.
        let seq: UInt64
        let destination: KeyDestination?

        /// When the current landing attempt started, which its deadline counts from.
        private var landingStart = Date()
        /// The epoch the command ran in, its snapshot's generated text, and its run, harvested before a cleanup's plans reset it.
        private var epoch: UInt64 = 0
        private var generated = 0
        private var evidence = Executor.RunEvidence()

        init(controller: Controller, binding: FocusTracker.Binding, seq: UInt64, destination: KeyDestination? = nil) {
            self.controller = controller
            self.binding = binding
            self.seq = seq
            self.destination = destination
        }

        var loop: CommandLoop<Host> {
            get { controller.loop }
            nonmutating set { controller.loop = newValue }
        }

        var state: VimState { controller.state }

        var profile: CapabilityProfile { binding.capabilities }

        var buttonEvents: UInt32 { Controller.buttonEvents() }

        func commit(_ effect: VimEffect) {
            controller.executor.commit(effect, state: &controller.state)
        }

        func refuse(_ reason: CommandLoop<Host>.Refusal) {
            NSSound.beep()
            switch reason {
            case .composing(let completed):
                Diag.dropped(controller.tracker.epoch, seq, command: completed.command, reason: "composing")
            case .undoLanding(let completed):
                Diag.dropped(controller.tracker.epoch, seq, command: completed.command, reason: "undo-landing")
            case .uncommitted:
                break
            }
        }

        // MARK: Input methods

        func engage(_ token: String) -> Composition.Engage? {
            guard let method = InputSource.selectedMethod() else { return nil }
            let start = DispatchTime.now().uptimeNanoseconds
            var answers: [Composition] = []
            let engaged = Composition.engage(token, read: {
                answers.append(CompositionReads.answer(of: binding, method: method, letter: controller.letterAt))
                return answers[answers.count - 1]
            }, commit: {
                answers.append(CompositionReads.commit(on: binding, method: method))
                return answers[answers.count - 1]
            })
            Diag.engaged(controller.tracker.epoch, key: token, method: method, answers: answers, engaged, since: start)
            return engaged
        }

        func passToInputMethod() {
            controller.monitor.markInsertLogLossy()
        }

        var compositionRead: (() -> Composition)? {
            guard let method = InputSource.selectedMethod() else { return nil }
            let (binding, letter) = (binding, controller.letterAt)
            return { CompositionReads.answer(of: binding, method: method, letter: letter) }
        }

        // MARK: The command

        mutating func postingKeys<T>(_ body: (inout Host) -> T) -> T {
            controller.executor.destination = destination
            defer { controller.executor.destination = nil }
            return body(&self)
        }

        mutating func snapshot(anchor: Int?) -> CommandLoop<Host>.Reading {
            let reading = Snapshotter.snapshot(
                of: binding.element,
                capabilities: binding.capabilities,
                anchor: anchor,
                cursor: controller.state.field.cursor,
                chromium: binding.isChromium,
                model: binding.beliefs?.readModel ?? ReadModel(answer: .value),
                sampling: controller.sampling,
                known: controller.emptyParagraphs,
                knownUnreachable: controller.unreachable
            )
            if reading.emptyParagraphs != controller.emptyParagraphs, let memo = reading.emptyParagraphs {
                Diag.emptyParagraphs(controller.tracker.epoch, seq, memo)
            }
            controller.emptyParagraphs = reading.emptyParagraphs
            if reading.unreachable != controller.unreachable, let memo = reading.unreachable {
                Diag.unreachable(controller.tracker.epoch, seq, memo)
            }
            controller.unreachable = reading.unreachable
            if reading.sampled {
                controller.sampling.sampled(
                    markers: reading.markers, evidence: reading.observed.evidence, text: reading.reads.text,
                    plain: reading.reads.plain
                )
            }
            controller.fieldBreaks = reading.snapshot.breaks
            generated = reading.generated
            return CommandLoop.Reading(
                snapshot: reading.snapshot, observed: reading.observed, value: reading.value, generated: reading.generated > 0
            )
        }

        func missedRoutes(under offsets: OffsetsAnswer) -> Set<Route> {
            controller.missedRoutes(on: binding, under: offsets)
        }

        mutating func execute(_ plan: PhysicalPlan, paragraphs: Bool, generated: Bool) -> (executed: Bool, abortedAt: Int?) {
            epoch = controller.tracker.epoch
            let executed = controller.executor.execute(
                plan, on: binding.element, state: &controller.state, paragraphs: paragraphs, generated: generated
            )
            evidence = controller.executor.lastRun
            return (executed, evidence.abortedAt)
        }

        func record(
            _ completed: RawMonitor.Completed, logical: LogicalPlan, planned: PhysicalPlanner.Planning,
            from before: VimState.Mode, reading: CommandLoop<Host>.Reading, executed: Bool
        ) {
            Diag.command(
                epoch, seq,
                command: completed.command,
                from: before, to: controller.state.field.mode,
                plan: planned.plan,
                rejection: planned.rejection,
                bell: Controller.bellReason(logical),
                executed: executed,
                evidence: evidence,
                insertPayload: completed.insertPayload,
                emptyLines: reading.snapshot.valueGap,
                foldedLength: reading.snapshot.foldedLength,
                generated: generated
            )
            // After the record, as the republish a lesson causes re-enters the tracker.
            controller.learn(from: evidence, observed: reading.observed, on: binding, epoch: epoch, seq: seq)
        }

        // MARK: The cleanup after a failed command

        /// In field offsets, through the markers in a text-content field, where a selected paragraph break is no caret.
        func selectionRead(paragraphs: Bool) -> CommandLoop<Host>.Selection? {
            guard paragraphs, let marked = Snapshotter.markedSelection(of: binding.element) else {
                return AX.selectedRange(of: binding.element).map {
                    CommandLoop.Selection(range: $0.location..<($0.location + $0.length), caret: $0.length == 0, marked: nil)
                }
            }
            return CommandLoop.Selection(range: marked.range, caret: marked.isCollapsed, marked: marked)
        }

        func side(of marked: AX.MarkedSelection) -> ParagraphBreaks.Side? {
            Snapshotter.paragraphSide(of: marked, upper: false)
        }

        func value() -> String? {
            AX.value(of: binding.element)
        }

        @discardableResult
        func runAside(_ plan: PhysicalPlan, paragraphs: Bool) -> Bool {
            controller.executor.execute(plan, on: binding.element, state: &controller.state, paragraphs: paragraphs)
        }

        /// Whether the selection reads as a caret within 100 ms: Chromium shows a write or key milliseconds after it is sent,
        /// and a command typed ahead would plan on the selection still shown (LIN-1931).
        func becomesCaret(paragraphs: Bool) -> Bool {
            let deadline = Date().addingTimeInterval(0.1)
            while let read = selectionRead(paragraphs: paragraphs) {
                if read.caret || Date() >= deadline { return read.caret }
                Thread.sleep(forTimeInterval: 0.003)
            }
            return false
        }

        // MARK: The landing after `u`

        func leftDuringLanding(_ completed: RawMonitor.Completed) -> Bool {
            // A click or another app during the landing refuses the command it held, whose writes no departure stops.
            if var destination = controller.executor.destination {
                let left = KeyDestinationReads.departure(of: &destination, readsActive: true)
                controller.executor.destination = destination
                if left != nil {
                    controller.drop(completed, seq, "undo-landing-left")
                    return true
                }
            }
            // The landing's keys can carry the caret into another field, as a block editor's ⌘↓ does.
            if !binding.isForced, !(controller.tracker.focusedField().map { CFEqual($0, binding.element) } ?? false) {
                NSSound.beep()
                controller.drop(completed, seq, "undo-landing-left")
                return true
            }
            return false
        }

        mutating func attemptLanding<T>(_ body: (inout Host) -> T) -> T {
            landingStart = Date()
            // A read may take the whole messaging timeout, and no key is handled meanwhile (LIN-2104).
            return AX.until(landingStart.addingTimeInterval(0.5)) { body(&self) }
        }

        var witness: Witness { Witness(sent: landingStart, element: binding.element) }

        func isField(of witness: Witness) -> Bool { CFEqual(witness.element, binding.element) }

        func awaitUndo(from value: String?) -> (shown: String?, waited: (polls: Int, milliseconds: Int)?) {
            // Chrome can apply ⌘Z after reads that follow it, and a read it cannot answer yet is no change (LIN-1980).
            var waited = 0
            var shown = AX.value(of: binding.element)
            while (shown ?? value) == value, waited < 25, !AX.pastDeadline {
                Thread.sleep(forTimeInterval: 0.01)
                waited += 1
                shown = AX.value(of: binding.element)
            }
            return (shown, (waited, Int(Date().timeIntervalSince(landingStart) * 1000)))
        }

        func awaitResumed(_ pending: CommandLoop<Host>.PendingUndo) -> String? {
            // An undo can show only after `u` gave up on it, while this key waited behind that `u`; half the time stays to land.
            let shownBy = min(pending.witness.sent.addingTimeInterval(1), landingStart.addingTimeInterval(0.25))
            var shown = AX.value(of: binding.element)
            var waited = 0
            while (shown ?? pending.value) == pending.value, Date() < shownBy, waited < 25 {
                Thread.sleep(forTimeInterval: 0.01)
                waited += 1
                shown = AX.value(of: binding.element)
            }
            return shown
        }

        /// Whether the caret read the same for 60 ms before `AX.until`'s deadline, longer than any gap measured between a route's
        /// keys landing (LIN-2104): a sign, not proof, that the keys a landing sent are handled; true where uvim reads no caret.
        func caretHolds() -> Bool {
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

        func snapshotAside() -> FieldSnapshot {
            Snapshotter.snapshot(
                of: binding.element, capabilities: binding.capabilities, anchor: nil, cursor: controller.state.field.cursor,
                chromium: binding.isChromium, model: binding.beliefs?.readModel ?? ReadModel(answer: .value),
                sampling: controller.sampling, known: controller.emptyParagraphs, knownUnreachable: controller.unreachable
            ).snapshot
        }

        var pastDeadline: Bool { AX.pastDeadline }

        var readsRefused: Bool { AX.pastDeadline }

        func runLanding(_ plan: PhysicalPlan, paragraphs: Bool) -> (ran: Bool, departure: KeyDestination.Departure?) {
            let ran = controller.executor.execute(
                plan, on: binding.element, state: &controller.state, paragraphs: paragraphs, keys: PhysicalPlanner.undoKeys
            )
            return (ran, controller.executor.lastRun.departure)
        }

        var lastRun: Executor.RunEvidence { controller.executor.lastRun }

        func traceLanding(_ trace: CommandLoop<Host>.LandingTrace) {
            var evidence = trace.evidence
            if let left = trace.departure { evidence.departure = left }
            Diag.undoLanding(
                controller.tracker.epoch, seq, plan: trace.walk, executed: trace.executed, evidence: evidence,
                waited: trace.waited, lengths: trace.lengths, fallbacks: trace.fallbacks, route: trace.route
            )
        }
    }
}
