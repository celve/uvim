import AppKit
import ApplicationServices
import Core

/// The runtime's side of `StepRunner`, which walks a plan for it as for the Sim: AX writes, posted keys and timed polls carry the
/// steps out. The runtime's **sole caller of `VimReducer`**: state changes happen only when the run reaches a commit step it did
/// not abort past (or when the controller routes a runtime-authored effect through `commit(_:state:)`).
///
/// Runs synchronously on the main run loop: AX writes are fast, settle polls
/// are bounded, and blocking the tap callback is precisely what serializes
/// keys during execution.
@MainActor
public final class Executor {
    public init() {}

    /// The last run's, which a runtime-authored effect resolves against.
    private var captures: [CaptureSlot: String] = [:]

    /// Copy it right after `execute()`: hygiene plans reuse this executor and reset it.
    public struct RunEvidence: Equatable, Sendable {
        public internal(set) var attribution = RunAttribution()

        public var failedCapability: Capability? {
            attribution.evidence.first { $0.outcome == .refutes }?.question.capability
        }
        public var settledCapabilities: Set<Capability> {
            Set(attribution.evidence.compactMap { $0.outcome == .supports(nil) ? $0.question.capability : nil })
        }

        /// Recorder only.
        public internal(set) var abortedAt: Int?

        /// Why the run stopped posting keys, which then teach nothing about the field.
        public internal(set) var departure: KeyDestination.Departure?

        /// Hard and soft: a soft one rings nothing and aborts nothing, so it was invisible.
        public internal(set) var settleFailures: [SettleFailure] = []

        public init() {}
    }

    /// `answered == false` is a field that produced no attribute at all, not one that disagreed.
    public struct SettleFailure: Equatable, Sendable {
        public let hard: Bool
        public let index: Int
        public let expectation: Expectation
        public let observedSelection: Range<Int>?
        public let observedLength: Int?
        public let observedSelectedText: String?
        public let answered: Bool
        public let polls: Int
        public let milliseconds: Int
        /// Told a refused write apart from one that landed and then read back wrong.
        public let writeError: Int32?
        /// The generated text it failed across, which the model counted as the field's.
        public let misfit: Range<Int>?
    }

    public private(set) var lastRun = RunEvidence()

    /// The running command's, set around it by the controller: its keys go to its process and stop once the focus leaves;
    /// nil posts them to the front app, unchecked.
    var destination: KeyDestination?

    /// When the bound app's activity was last read: a read costs about 3 ms under a flood of keys, so keys in between share one.
    private var activeReadAt: UInt64 = 0
    private static let activeReadGap: UInt64 = 50_000_000

    /// An `AXError` worth reporting: `.success` is not one.
    private static func rejection(_ error: AXError) -> Int32? {
        error == .success ? nil : error.rawValue
    }

    /// Runs the plan in order, sparing residency when a step fails, pressing at most `keys` keys where it is given; returns
    /// whether every step ran.
    @discardableResult
    public func execute(
        _ plan: PhysicalPlan, on element: AXUIElement, state: inout VimState, paragraphs: Bool = false, generated: Bool = false,
        keys: Int? = nil
    ) -> Bool {
        var host = Host(executor: self, element: element, state: state, paragraphs: paragraphs, steps: plan.steps)
        let run = StepRunner.run(plan.steps, generated: generated, keys: keys, host: &host)
        state = host.state
        captures = run.captures
        var evidence = RunEvidence()
        evidence.attribution = run.attribution
        evidence.abortedAt = run.abortedAt
        evidence.departure = run.departure
        evidence.settleFailures = run.misses.map { miss in
            SettleFailure(
                hard: miss.failed, index: miss.index, expectation: miss.expectation,
                observedSelection: miss.read.observedSelection, observedLength: miss.read.observedLength,
                observedSelectedText: miss.read.observedSelectedText, answered: miss.read.answered, polls: miss.read.polls,
                milliseconds: miss.read.milliseconds, writeError: miss.writeError, misfit: miss.misfit
            )
        }
        lastRun = evidence
        return run.abortedAt == nil
    }

    /// Runtime-authored effects (insert payloads, dot bodies) enter through
    /// the executor too, so the reducer keeps exactly one caller.
    public func commit(_ effect: VimEffect, state: inout VimState) {
        state = VimReducer.reduce(state, effect, captures: captures)
    }

    /// The observed values ride every exit, so a timeout costs no extra round trip.
    struct SettleOutcome {
        let converged: Bool
        let observedSelection: Range<Int>?
        let observedLength: Int?
        let observedSelectedText: String?
        let answered: Bool
        let polls: Int
        let milliseconds: Int
        var misfit: Range<Int>?
    }

    /// Bounded convergence poll against the planner's prediction.
    ///
    /// One IPC per poll: the attribute list is built from what the
    /// expectation actually asks about, so a selection-only settle never
    /// reads length. `kAXValue` deliberately stays OUT of the batch — it is
    /// the rare fallback for an element that claimed `readLength` and then
    /// answered nil, and fetching it every poll would marshal the entire
    /// document dozens of times per settle.
    nonisolated static func settle(
        _ expectation: Expectation, on element: AXUIElement, paragraphs: Bool, presses: Int = 0, generated: Bool = false
    ) -> SettleOutcome {
        var names: [String] = []
        var selectionSlot: Int?
        var lengthSlot: Int?
        var textSlot: Int?
        if expectation.landing != nil {
            selectionSlot = names.count
            names.append(kAXSelectedTextRangeAttribute)
        }
        if expectation.length != nil {
            lengthSlot = names.count
            names.append(kAXNumberOfCharactersAttribute)
        }
        if expectation.selectedText != nil {
            textSlot = names.count
            names.append(kAXSelectedTextAttribute)
        }
        // An expectation that predicts nothing is already met — and must not
        // spend a round trip discovering that.
        guard !names.isEmpty else {
            return SettleOutcome(
                converged: true, observedSelection: nil, observedLength: nil, observedSelectedText: nil,
                answered: true, polls: 0, milliseconds: 0
            )
        }

        let start = Date()
        // Keys go back to back, so a run lands inside this wait, and Chromium takes a long shifted one more slowly still.
        let deadline = start.addingTimeInterval(0.25 + Double(presses) * (paragraphs ? 0.005 : 0.0025))
        var polls = 0
        while true {
            polls += 1
            let reads = AX.attributes(names, of: element)
            var selection: Range<Int>?
            var length: Int?
            if let slot = selectionSlot, let range = reads.range(slot) {
                selection = range.location..<(range.location + range.length)
            }
            if let slot = lengthSlot {
                length = reads.int(slot) ?? AX.value(of: element).map { $0.utf16.count }
            }
            // Chromium adds a U+FFFC here for each text-less leaf, which `Expectation.matches` looks past.
            let text = textSlot.flatMap { reads.string($0) }
            // Not convergence: an absent attribute is a silent app, a wrong one a liar.
            let answered = (selectionSlot == nil || selection != nil)
                && (lengthSlot == nil || length != nil)
                && (textSlot == nil || text != nil)
            func outcome(_ converged: Bool) -> SettleOutcome {
                SettleOutcome(
                    converged: converged,
                    observedSelection: selection, observedLength: length, observedSelectedText: text,
                    answered: answered, polls: polls,
                    milliseconds: Int(Date().timeIntervalSince(start) * 1000)
                )
            }
            var side: ParagraphBreaks.Side?
            var checkedLength = length
            // Only the markers place a caret between elements or tell a boundary's sides apart.
            if !expectation.converged(selection: selection, length: length, selectedText: text, side: nil), paragraphs,
               selectionSlot != nil, let marked = Snapshotter.markedSelection(of: element) {
                selection = marked.range
                side = expectation.edge == nil ? nil : Snapshotter.paragraphSide(of: marked, upper: true)
                // The caret Linear draws at a code span's edge is lines of its own, which no expected length counts.
                if let expected = expectation.length, let observed = length, (1...2).contains(observed - expected) {
                    checkedLength = observed - Snapshotter.drawnLength(at: marked)
                }
            }
            // A field showing only text its page generates, as an empty editor shows its placeholder, holds none (LIN-1930).
            if expectation.passes(
                selection: selection, length: checkedLength, selectedText: text, side: side, answered: answered,
                generated: generated, showsOnlyGeneratedText: { Snapshotter.showsOnlyGeneratedText(element) }
            ) {
                return outcome(true)
            }
            guard Date() < deadline, !AX.pastDeadline else {
                var failed = outcome(false)
                failed.misfit = expectation.misfit(selection: selection, length: checkedLength, selectedText: text, side: side)
                return failed
            }
            // In the rich-text fields measured, a missed poll cost the host ~0.5 ms of CPU on average (LIN-1727).
            Thread.sleep(forTimeInterval: 0.003)
        }
    }

    // MARK: - Chord lowering (symbolic → hardware)

    static func keyCode(for key: Key) -> CGKeyCode? {
        switch key {
        case .arrowLeft: return 123
        case .arrowRight: return 124
        case .arrowDown: return 125
        case .arrowUp: return 126
        case .pageUp: return 116
        case .pageDown: return 121
        case .delete: return 51
        case .forwardDelete: return 117
        case .enter: return 36
        case .escape: return 53
        case .character(let character):
            switch character {
            case "a": return 0    // kVK_ANSI_A (⌃A)
            case "e": return 14   // kVK_ANSI_E (⌃E)
            case "z": return 6    // kVK_ANSI_Z (undo/redo)
            case "v": return 9    // kVK_ANSI_V
            default: return nil
            }
        }
    }

    /// Measured to land exactly with no gap between down and up, shifted or not (LIN-1686).
    static func backToBack(_ chord: Chord) -> Bool {
        switch chord.key {
        case .arrowLeft, .arrowRight: return chord.modifiers.subtracting(.shift).isEmpty
        case .character("a"), .character("e"): return chord.modifiers.subtracting(.shift) == [.control]
        default: return false
        }
    }

    static func flags(for modifiers: Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}

// MARK: - The runner's host

extension Executor {
    /// One run's host for `StepRunner`: every AX write and read, posted key and wait of the runtime's.
    @MainActor struct Host: @MainActor StepHost {
        unowned let executor: Executor
        let element: AXUIElement
        /// The field selects in text content (Chromium rich text).
        let paragraphs: Bool
        var state: VimState
        /// Settles straight after a ⇧← → that keeps a caret outside a code span, whose target showed before those two keys.
        private let afterNormalizing: Set<Int>

        /// Keys pressed since the last settle.
        private var pressed = 0
        /// The press under way, lowered.
        private var key: (code: CGKeyCode, flags: CGEventFlags, gap: TimeInterval)?

        /// This run's last register paste, which only the settle straight after it can confirm.
        private var pastedAt: Int?
        /// That paste was in Chromium's rich text, where a settle after it that predicts nothing waits for it to land.
        private var pasteWaits = false
        /// The caret the paste began at, when it read as one.
        private var pastedFrom: (range: Range<Int>, side: ParagraphBreaks.Side?)?

        init(executor: Executor, element: AXUIElement, state: VimState, paragraphs: Bool, steps: [PhysicalStep]) {
            self.executor = executor
            self.element = element
            self.state = state
            self.paragraphs = paragraphs
            let outside: [PhysicalStep] = [.press(.selectLeft, count: 1), .press(.right, count: 1)]
            afterNormalizing = Set(steps.indices.filter {
                guard $0 >= 2, case .settle = steps[$0] else { return false }
                return Array(steps[$0 - 2..<$0]) == outside
            })
        }

        private var target: pid_t? { executor.destination?.pid }

        func setSelection(_ range: Range<Int>) -> Int32? {
            Executor.rejection(AX.setSelectedRange(CFRange(location: range.lowerBound, length: range.count), on: element))
        }

        func replaceSelection(_ replacement: String) -> Int32? {
            Executor.rejection(AX.setSelectedText(replacement, on: element))
        }

        mutating func beginPress(_ chord: Chord) -> Bool {
            guard let code = Executor.keyCode(for: chord.key) else { return false }
            key = (code, Executor.flags(for: chord.modifiers), Executor.backToBack(chord) ? 0 : Synth.pairGap)
            return true
        }

        mutating func sendKey(_ chord: Chord) {
            guard let key else { return }
            Synth.key(key.code, key.flags, gap: key.gap, to: target)
            pressed += 1
        }

        func endPress(_ chord: Chord) {}

        func typeText(_ text: String) {
            Synth.type(text, to: target)
        }

        func cut() {
            // The pasteboard IS the register (clipboard=unnamed): post the
            // cut and move on — nothing read back, silence on failure.
            Synth.key(7, .maskCommand, to: target)   // kVK_ANSI_X
        }

        func copy() {
            Synth.key(8, .maskCommand, to: target)   // kVK_ANSI_C
        }

        mutating func paste(_ content: String?, at index: Int) -> KeyDestination.Departure? {
            if let content {
                // No sleep before ⌘V: the app reads the pasteboard only as it handles the ⌘V, queued after the write.
                PasteboardLoan.shared.put(content)
                pastedAt = index
                pasteWaits = paragraphs
                pastedFrom = paragraphs ? Snapshotter.markedSelection(of: element).flatMap {
                    $0.isCollapsed ? ($0.range, Snapshotter.paragraphSide(of: $0, upper: true)) : nil
                } : nil
            } else {
                // Registers +/* and pasteboard markers paste what the user has there, not a register still on loan.
                PasteboardLoan.shared.restore()
            }
            // The loan and the reads above take long enough for the focus to move.
            if let left = departure(fresh: false) {
                if content != nil { PasteboardLoan.shared.restore() }
                return left
            }
            Synth.commandV(to: target)
            return nil
        }

        func selectedText() -> String? {
            AX.selectedText(of: element)
        }

        mutating func settle(_ expectation: Expectation, at index: Int, generated: Bool) -> SettleOutcome {
            awaitPaste(expectation, at: index)
            var outcome = Executor.settle(
                expectation, on: element, paragraphs: paragraphs, presses: pressed, generated: generated
            )
            pressed = 0
            if outcome.converged, afterNormalizing.contains(index) {
                // Read again once the ⇧← → are in, so the next command never reads the selection between them.
                Thread.sleep(forTimeInterval: 0.015)
                outcome = Executor.settle(expectation, on: element, paragraphs: paragraphs, generated: generated)
            }
            confirmPaste(outcome, expectation, at: index)
            return outcome
        }

        /// Where the focus is, read before every key: the button presses each time, the app's activity when `fresh` or 50 ms on.
        func departure(fresh: Bool) -> KeyDestination.Departure? {
            guard var held = executor.destination else { return nil }
            let now = DispatchTime.now().uptimeNanoseconds
            let readsActive = fresh || now &- executor.activeReadAt >= Executor.activeReadGap
            if readsActive { executor.activeReadAt = now }
            let left = KeyDestinationReads.departure(of: &held, readsActive: readsActive)
            executor.destination = held
            return left
        }

        func departure(beforeKeyOf step: PhysicalStep) -> KeyDestination.Departure? {
            departure(fresh: false)
        }

        /// `AX.until`'s deadline stops keys too: a long run holds the keyboard and floods the app (LIN-2104).
        var keysPastDeadline: Bool { AX.pastDeadline }

        mutating func commit(_ effect: VimEffect, captures: [CaptureSlot: String]) {
            state = VimReducer.reduce(state, effect, captures: captures)
        }

        func bell() {
            NSSound.beep()
        }

        /// Only Chromium's tree tells the page's generated text from the field's.
        func generates(_ run: Range<Int>) -> Bool {
            paragraphs && Snapshotter.generates(run, in: element)
        }

        /// Reads `AX.until`'s deadline refused fail a settle without saying anything of this field.
        func refused(_ expectation: Expectation, _ read: SettleOutcome, soft: Bool) {
            if soft || !AX.pastDeadline { NSSound.beep() }
        }

        /// Pastes land up to 250 ms late: a settle after one that predicts nothing waits for the caret to stay off its start.
        private func awaitPaste(_ expectation: Expectation, at index: Int) {
            guard pastedAt == index - 1, pasteWaits, expectation.landing == nil, expectation.length == nil,
                  expectation.selectedText == nil else { return }
            let deadline = Date().addingTimeInterval(0.25)
            var moved = 0
            while Date() < deadline {
                // A caret Linear draws beside code reads as a selection, or elsewhere, for a moment, which is no landing.
                if let from = pastedFrom, let marked = Snapshotter.markedSelection(of: element), marked.isCollapsed,
                   marked.range != from.range || Snapshotter.paragraphSide(of: marked, upper: true) != from.side {
                    moved += 1
                    if moved == 2 { return }
                } else {
                    moved = 0
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        /// Only a caret landing straight after the paste proves the target read it: a length can match before it lands.
        private func confirmPaste(_ outcome: SettleOutcome, _ expectation: Expectation, at index: Int) {
            guard pastedAt == index - 1, outcome.converged, expectation.landing != nil else { return }
            PasteboardLoan.shared.landed()
        }
    }
}

extension Executor.SettleOutcome: SettleRead {
    var passed: Bool { converged }
    var selection: Range<Int>? { observedSelection }
    var length: Int? { observedLength }
    var selectedText: String? { observedSelectedText }
}
