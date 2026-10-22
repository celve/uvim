/// The command loop the runtime and the Sim share: what it remembers between commands, and the decisions it makes as it drives a
/// `CommandHost` through the field's reads, keys, waits and commits.
struct CommandLoop<Host: CommandHost> {
    /// The command that opened the current Insert session, recorded at its Esc.
    var openChange: (source: String, count: Int?, register: Register?, mutated: Bool)?

    /// What a `u` found where its landing did not finish in time, which the next command lands from first (LIN-2104).
    var pendingUndo: PendingUndo?

    struct PendingUndo {
        /// The text `u` found, and the `AXValue` its command's snapshot read.
        let before: String
        let value: String?
        /// The button events when `u` ran, which a click since has moved.
        let clicks: UInt32
        let witness: Host.Witness
        /// The route the next attempt runs, and the selection the undo left, which tells the restored lines apart.
        var route: Int
        var near: Range<Int>?
    }

    /// Why a command or an engage key was refused, with a beep.
    enum Refusal {
        case composing(RawMonitor.Completed)
        case undoLanding(RawMonitor.Completed)
        /// Nothing read the letters an input method held as committed after ⌃[, so Insert mode stays.
        case uncommitted
    }

    /// The field as a command's snapshot read it.
    struct Reading {
        let snapshot: FieldSnapshot
        let observed: Learning.Observation
        /// `AXValue` as read, which a later read compares with to tell the field changed.
        let value: String?
        /// The field may show only text its page generates (LIN-1930).
        let generated: Bool
    }

    /// A selection read outside a plan, through the markers where `marked` holds them.
    struct Selection {
        let range: Range<Int>
        let caret: Bool
        let marked: Host.Marked?
    }

    /// One attempt at a landing after `u`, for the host's recorder.
    struct LandingTrace {
        /// The walk to Vim's place where this attempt ran it, and whether it ran to its end.
        var walk: PhysicalPlan?
        var executed = true
        /// The walk's run, or where the attempt ran none, the last run before it.
        var evidence: Host.RunRecord
        var fallbacks: [PhysicalPlan] = []
        var departure: KeyDestination.Departure?
        let waited: (polls: Int, milliseconds: Int)?
        let lengths: (before: Int, after: Int?)
        /// The route the next attempt runs; nil where this one finished.
        var route: Int?
    }
}

/// What the loop runs a command against, where the runtime and the Sim differ: the field's reads and keys, the waits that time
/// them, the commits and the records.
protocol CommandHost {
    /// A selection's read through the markers, which tell its paragraph side.
    associatedtype Marked
    /// What a pending landing keeps of the field and moment `u` ran in.
    associatedtype Witness
    /// A plan's run, as the host records it.
    associatedtype RunRecord

    var loop: CommandLoop<Self> { get set }
    var state: VimState { get }
    var profile: CapabilityProfile { get }
    /// The session's button presses and releases, which a click moves.
    var buttonEvents: UInt32 { get }

    mutating func commit(_ effect: VimEffect)
    mutating func refuse(_ reason: CommandLoop<Self>.Refusal)

    /// What an engage key does where an input method is selected, which may hold letters pending; nil where none is.
    mutating func engage(_ token: String) -> Composition.Engage?
    /// The engage key goes to the app, whose input method cancels the letters the Insert log cannot say.
    mutating func passToInputMethod()
    /// The read of the letters an input method holds pending; nil where none is selected.
    var compositionRead: (() -> Composition)? { get }

    /// Runs `body` with the command's keys going to the field's process, and only while the focus stays.
    mutating func postingKeys<T>(_ body: (inout Self) -> T) -> T
    /// The field as it reads for a command, Visual mode's `anchor` with it.
    mutating func snapshot(anchor: Int?) -> CommandLoop<Self>.Reading
    /// The optional routes to plan without.
    func missedRoutes(under offsets: OffsetsAnswer) -> Set<Route>
    /// Runs a command's plan: whether every step ran, and where it stopped.
    mutating func execute(_ plan: PhysicalPlan, paragraphs: Bool, generated: Bool) -> (executed: Bool, abortedAt: Int?)
    /// Records the command and learns from its run, once the loop is done with it.
    mutating func record(
        _ completed: RawMonitor.Completed, logical: LogicalPlan, planned: PhysicalPlanner.Planning, from before: VimState.Mode,
        reading: CommandLoop<Self>.Reading, executed: Bool
    )

    /// The selection as it reads now, in field offsets; nil where it went unanswered.
    mutating func selectionRead(paragraphs: Bool) -> CommandLoop<Self>.Selection?
    mutating func side(of marked: Marked) -> ParagraphBreaks.Side?
    /// `AXValue` as it reads now.
    mutating func value() -> String?
    /// The field as it reads now, outside a command.
    mutating func snapshotAside() -> FieldSnapshot
    /// Runs a plan that cleans up after the command's: whether every step ran.
    @discardableResult mutating func runAside(_ plan: PhysicalPlan, paragraphs: Bool) -> Bool
    /// Whether the selection reads as a caret, in the time the field takes to show one.
    mutating func becomesCaret(paragraphs: Bool) -> Bool

    /// Whether the focus left during a resumed landing, which refuses the command it held.
    mutating func leftDuringLanding(_ completed: RawMonitor.Completed) -> Bool
    /// Runs `body` as one landing attempt, within the deadline that bounds it.
    mutating func attemptLanding<T>(_ body: (inout Self) -> T) -> T
    var witness: Witness { get }
    func isField(of witness: Witness) -> Bool
    /// The `AXValue` once it shows the `u` command's undo, or once waiting for it is over; nil where it went unanswered.
    mutating func awaitUndo(from value: String?) -> (shown: String?, waited: (polls: Int, milliseconds: Int)?)
    /// The `AXValue` once it shows an undo that showed late, or once waiting for it is over; nil where it went unanswered.
    mutating func awaitResumed(_ pending: CommandLoop<Self>.PendingUndo) -> String?
    /// Whether the caret reads the same for a while, a sign that keys an earlier attempt sent are handled.
    mutating func caretHolds() -> Bool
    /// The deadline has passed, so no landing plan starts.
    var pastDeadline: Bool { get }
    /// A read made now answers nothing.
    var readsRefused: Bool { get }
    /// Runs a landing plan, pressing at most `PhysicalPlanner.undoKeys` keys: whether it ran to its end, and why the focus left.
    mutating func runLanding(_ plan: PhysicalPlan, paragraphs: Bool) -> (ran: Bool, departure: KeyDestination.Departure?)
    var lastRun: RunRecord { get }
    mutating func traceLanding(_ trace: CommandLoop<Self>.LandingTrace)
}

// MARK: - A command

extension CommandLoop {
    /// An engage key in Insert mode, which an input method holding letters pending may take (#69): nil where Normal mode follows,
    /// else whether uvim takes the key.
    static func engage(_ token: String, host: inout Host) -> Bool? {
        switch host.engage(token) {
        case .normal?, nil:
            return nil
        case .passThrough?:
            host.passToInputMethod()
            return false
        case .refuse?:
            host.refuse(.uncommitted)
            return true
        }
    }

    /// A completed command, run unless letters an input method holds pending, or a landing after `u` it waits behind, refuse it;
    /// whether it ran.
    @discardableResult
    static func command(_ completed: RawMonitor.Completed, mode: RawMonitor.Mode, host: inout Host) -> Bool {
        // Pending letters take the field's keys and selection, so a command would misfire and teach uvim wrong.
        if mode != .insert, let read = host.compositionRead, !Composition.runs(completed.command, read: read) {
            host.refuse(.composing(completed))
            return false
        }
        return host.postingKeys { host in
            guard landsPending(completed, host: &host) else { return false }
            run(completed, host: &host)
            return true
        }
    }

    /// Plans a command against the field as it reads now and runs it; then the cleanup where it failed, the bookkeeping for `.`,
    /// the landing after `u`, and last the host's record and lesson.
    static func run(_ completed: RawMonitor.Completed, host: inout Host) {
        let command = completed.command
        let logical = LogicalPlanner.plan(command, state: host.state)
        var anchor: Int?
        var visual = false
        if case .visual(let context) = host.state.field.mode {
            (anchor, visual) = (context.anchor, true)
        }
        let reading = host.snapshot(anchor: anchor)
        let snapshot = reading.snapshot
        let paragraphs = snapshot.breaks != nil
        let planned = PhysicalPlanner.planning(
            logical, snapshot: snapshot, missed: host.missedRoutes(under: reading.observed.after), visual: visual
        )
        let physical = planned.plan
        let before = host.state.field.mode
        let ran = host.execute(physical, paragraphs: paragraphs, generated: reading.generated)
        // After the cleanup and the bookkeeping, on both paths, so the republish a lesson causes happens as `run` unwinds.
        defer {
            host.record(completed, logical: logical, planned: planned, from: before, reading: reading, executed: ran.executed)
        }
        guard ran.executed else {
            if planned.abortedAtTextCheck(ran.abortedAt) {
                // Other text than the plan meant was selected, so the mode it asked for goes too.
                if let read = host.selectionRead(paragraphs: paragraphs), !read.caret {
                    host.runAside(
                        PhysicalPlanner.collapse(read.range, misread: true, toEnd: planned.collapsesToEnd, profile: host.profile),
                        paragraphs: paragraphs
                    )
                    _ = host.becomesCaret(paragraphs: paragraphs)
                }
                if host.state.field.mode.isInserting {
                    host.commit(.setMode(before.nonVisual))
                }
            } else if !repairStrandedSelection(
                operand: planned.operand, toEnd: planned.collapsesToEnd, reading: reading, host: &host
            ), host.state.field.mode.isInserting {
                // A selection we could not collapse is one the app would type over.
                host.commit(.setMode(before.nonVisual))
            }
            // `RawMonitor` drained the payload it will never offer again.
            if let payload = completed.insertPayload, !host.state.field.mode.isInserting {
                closeInsertSession(payload, lossless: completed.insertPayloadIsLossless, host: &host)
            }
            recordChange(for: command, from: before, mutated: physical.mutatesText, aborted: true, host: &host)
            return
        }

        if let payload = completed.insertPayload {
            closeInsertSession(payload, lossless: completed.insertPayloadIsLossless, host: &host)
        }

        recordChange(for: command, from: before, mutated: physical.mutatesText, host: &host)
        if logical.steps.contains(.history(.undo)), let text = snapshot.text {
            landUndo(from: text, value: reading.value, host: &host)
        }
    }

    /// Collapse a stranded selection, and report whether the field is safe to type into.
    static func repairStrandedSelection(operand: Range<Int>?, toEnd: Bool, reading: Reading, host: inout Host) -> Bool {
        let paragraphs = reading.snapshot.breaks != nil
        // Unknown is not empty: a settle can fail *because* the read went dark.
        guard let read = host.selectionRead(paragraphs: paragraphs) else { return false }
        guard !read.caret else { return true }
        // Still the operand: the app's own editor substitutes on the first keystroke.
        if host.state.field.mode.isInserting, read.range == operand { return true }
        var side: ParagraphBreaks.Side?
        var snapshot: FieldSnapshot?
        if let marked = read.marked {
            side = host.side(of: marked)
            // An edit, or a caret Linear drew or took away, leaves the run's snapshot describing other text.
            snapshot = host.value() == reading.value ? reading.snapshot : host.snapshotAside()
        }
        let collapse = PhysicalPlanner.collapse(
            read.range, side: side, paragraphs: paragraphs, snapshot: snapshot, toEnd: toEnd, profile: host.profile
        )
        let settled = host.runAside(collapse, paragraphs: paragraphs)
        // Keys the field ignored fail their settle, and a write lane then writes the start as it was read.
        if !settled, host.profile.has(.writeSelection) {
            let asRead = PhysicalPlanner.collapse(read.range, paragraphs: paragraphs, profile: host.profile)
            host.runAside(asRead, paragraphs: paragraphs)
        }
        // The write that stranded this may be the one that lies, so confirm.
        return host.becomesCaret(paragraphs: paragraphs)
    }
}

// MARK: - The bookkeeping for `.`

extension CommandLoop {
    /// Fold a just-ended Insert session into the dot memories.
    static func closeInsertSession(_ payload: String, lossless: Bool, host: inout Host) {
        if !payload.isEmpty {
            host.commit(.setLastInsert(payload))
        }
        guard let change = host.loop.openChange else { return }
        host.loop.openChange = nil
        guard lossless else {
            host.commit(.setLastChange(.unreplayable))
            return
        }
        // An empty session is still a change if its entry mutated (`ciw`, `o`).
        guard change.mutated || !payload.isEmpty else { return }
        host.commit(.setLastChange(VimState.ChangeMemory(
            body: change.source,
            count: change.count,
            register: change.register,
            insert: payload
        )))
    }

    /// Records a mutating command as `lastChange`, or opens a body if it entered Insert.
    static func recordChange(
        for command: RawCommand, from before: VimState.Mode, mutated: Bool, aborted: Bool = false, host: inout Host
    ) {
        if case .repeat = command.intent { return }   // `.` must not overwrite what it replays
        // An aborted plan mutated nothing, whatever its steps intended.
        let changed = mutated && !aborted
        if case .visual = before {
            // Visual keys name a selection `.` cannot rebuild.
            if changed || host.state.field.mode.isInserting {
                host.commit(.setLastChange(.unreplayable))
            }
            return
        }
        if host.state.field.mode.isInserting {
            if host.loop.openChange == nil {
                host.loop.openChange = (command.source, command.count, command.register, changed)
            }
            return
        }
        guard changed else { return }
        host.commit(.setLastChange(VimState.ChangeMemory(
            body: command.source,
            count: command.count,
            register: command.register
        )))
    }
}

// MARK: - The landing after `u`

extension CommandLoop {
    /// Puts the cursor on the lines `u` put back, as Vim does, from the field as the undo left it, or leaves that to the next
    /// command where the field has not shown them in time; `value` is the `AXValue` the `u` command's snapshot read.
    static func landUndo(from before: String, value: String?, host: inout Host) {
        host.attemptLanding { host in
            // Counted before the landing, so a click during it drops what it leaves.
            let clicks = host.buttonEvents
            let (shown, waited) = host.awaitUndo(from: value)
            // A field that left the last read unanswered would leave a snapshot unanswered too.
            guard shown != nil else {
                host.loop.pendingUndo = PendingUndo(
                    before: before, value: value, clicks: clicks, witness: host.witness, route: 0, near: nil
                )
                return host.traceLanding(LandingTrace(
                    evidence: host.lastRun, waited: waited, lengths: (before.utf16.count, nil), route: 0
                ))
            }
            let landed = landRestoredLines(after: before, changed: shown != value, waited: waited, host: &host)
            if !landed.finished {
                host.loop.pendingUndo = PendingUndo(
                    before: before, value: value, clicks: clicks, witness: host.witness, route: landed.route, near: landed.near
                )
            }
        }
    }

    /// The landing a `u` left, before the next command plans: false where that command must not run, as the landing still cannot
    /// finish or the focus left during it.
    static func landsPending(_ completed: RawMonitor.Completed, host: inout Host) -> Bool {
        let resumed = host.loop.pendingUndo != nil
        // No command plans on the line above lines an undo put back while their landing cannot finish.
        guard landPendingUndo(host: &host) else {
            host.refuse(.undoLanding(completed))
            return false
        }
        return !resumed || !host.leftDuringLanding(completed)
    }

    /// The landing a `u` left to this command, before it plans, its keys going where the command's will; false where it still
    /// cannot finish.
    static func landPendingUndo(host: inout Host) -> Bool {
        guard let pending = host.loop.pendingUndo else { return true }
        // A click, or another field, leaves the caret somewhere the undo did not put it.
        guard host.isField(of: pending.witness), pending.clicks == host.buttonEvents else {
            host.loop.pendingUndo = nil
            return true
        }
        let landed = host.attemptLanding { host in
            guard host.awaitResumed(pending) != nil else { return (finished: false, route: pending.route, near: pending.near) }
            return landRestoredLines(
                after: pending.before, changed: true, waited: nil, resumed: (pending.route, pending.near), host: &host
            )
        }
        if landed.finished {
            host.loop.pendingUndo = nil
        } else {
            host.loop.pendingUndo?.route = landed.route
            host.loop.pendingUndo?.near = landed.near
        }
        return landed.finished
    }

    /// Lands on the lines an undo put back since `before` by its routes in turn, from `resumed`, where a pending landing stopped:
    /// the walk to Vim's place, then for lines that end the text the two fallbacks, each pressing at most `undoKeys` keys. Finished
    /// where the walk lands, a fresh read shows the cursor on those lines, every route ran its course without bringing it nearer,
    /// or the field shows no such lines although it has `changed`; otherwise the result's `route` is the one the next attempt runs,
    /// and `near` the selection that told those lines apart.
    static func landRestoredLines(
        after before: String, changed: Bool, waited: (polls: Int, milliseconds: Int)?,
        resumed: (route: Int, near: Range<Int>?)? = nil, host: inout Host
    ) -> (finished: Bool, route: Int, near: Range<Int>?) {
        // Only a read that answered the text and, in a field whose caret uvim reads, the caret decides anything.
        func answered(_ field: FieldSnapshot) -> Bool {
            field.text != nil && !host.readsRefused && (field.selection != nil || !field.capabilities.has(.readCaret))
        }
        // Keys an earlier attempt sent can still be on their way; a caret holding still is taken as where they leave it.
        let still = resumed == nil || host.caretHolds()
        let after = host.snapshotAside()
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
        var trace = LandingTrace(
            evidence: host.lastRun, waited: waited, lengths: (before.utf16.count, after.text?.utf16.count), route: nil
        )
        while let found, !finished, route < routes, !host.pastDeadline {
            guard let plan = route == 0 ? found.plan
                    : PhysicalPlanner.undoFallback(onto: found.lines, snapshot: field, selecting: route == 2) else {
                route += 1
                continue
            }
            let ran = host.runLanding(plan, paragraphs: field.breaks != nil)
            if route == 0 {
                (trace.walk, trace.executed, trace.evidence) = (plan, ran.ran, host.lastRun)
            } else {
                trace.fallbacks.append(plan)
            }
            // The focus leaving ends the landing as it ends a command, and a click or another field would drop it anyway.
            if let left = ran.departure {
                (trace.departure, finished) = (left, true)
                break
            }
            // The walk's checks put the cursor on Vim's place, and where no caret reads nothing can confirm more, as in #64.
            if route == 0, ran.ran || field.selection == nil {
                finished = true
                break
            }
            guard host.caretHolds() else { break }
            let now = host.snapshotAside()
            guard answered(now), let from = distance(field), let to = distance(now) else { break }
            field = now
            // Nearer, the same route again at the next attempt; no nearer, the next route now.
            if to == 0 { finished = true } else if to < from { break } else { route += 1 }
        }
        // Every route ran its course without bringing the cursor nearer, as #64's fallbacks could fail.
        if found != nil, route >= routes { finished = true }
        trace.route = finished ? nil : route
        host.traceLanding(trace)
        return (finished, route, found == nil ? resumed?.near : near)
    }
}
