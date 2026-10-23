/// Runs a plan's physical steps in order for the runtime and the Sim alike, over a `StepHost` that carries each step out and
/// reads the field: a failed step ends the run, sparing only the commits behind it that survive an abort. The runner is its own
/// result.
struct StepRunner<Host: StepHost> {
    /// A settle that did not pass.
    struct Miss {
        let index: Int
        let expectation: Expectation
        /// A soft settle's, which fails the run only where the ⌫ before it was ignored.
        let soft: Bool
        /// It ended the run.
        let failed: Bool
        let read: Host.Read
        /// What the writes just before it returned.
        let writeError: Int32?
    }

    private(set) var attribution = RunAttribution()
    /// The step that ended the run, or the last one where keys after the last commit met the focus gone.
    private(set) var abortedAt: Int?
    /// Why the run stopped sending keys, which then teach nothing about the field.
    private(set) var departure: KeyDestination.Departure?
    private(set) var misses: [Miss] = []
    private(set) var captures: [CaptureSlot: String] = [:]

    /// The field may show only generated text: the snapshot read it so, or a settle expected it empty (LIN-1930).
    private var generated: Bool
    private var keysLeft: Int?
    /// Carets this run's settles kept, for `.between` landings.
    private var kept: [Int: Int] = [:]
    /// This run sent a key, so its commits and its end check where the focus is.
    private var postedKeys = false
    /// From the write a following settle verifies.
    private var writeError: Int32?

    private init(generated: Bool, keys: Int?) {
        self.generated = generated
        keysLeft = keys
    }

    /// Runs `steps` against `host` from what the snapshot read as `generated`, pressing at most `keys` keys where it is given.
    static func run(_ steps: [PhysicalStep], generated: Bool = false, keys: Int? = nil, host: inout Host) -> StepRunner {
        var runner = StepRunner(generated: generated, keys: keys)
        runner.walk(steps, host: &host)
        return runner
    }

    private mutating func walk(_ steps: [PhysicalStep], host: inout Host) {
        for (index, planned) in steps.enumerated() {
            var step = planned
            if case .settle(let expectation) = planned { step = .settle(expectation.resolving(kept)) }
            let (passed, read) = perform(step, at: index, host: &host)
            // A step the focus left judged nothing of this field.
            if passed || departure == nil {
                attribution.record(
                    step, passed: passed, selection: read?.selection, length: read?.length, selectedText: read?.selectedText,
                    writeError: passed ? nil : writeError
                )
            }
            switch step {
            case .setSelection, .replaceSelection:
                break
            default:
                // The settle consumes the error; any other step ends its reach.
                writeError = nil
            }
            guard passed else {
                abortedAt = index
                for case .commit(let effect) in steps[(index + 1)...] where effect.survivesAbort {
                    host.commit(effect, captures: captures)
                }
                return
            }
        }
        // Keys after the last commit did what they did only if the focus stayed.
        if !landed(host: &host) { abortedAt = max(0, steps.count - 1) }
    }

    /// Whether the step passed, and what it read where it was a settle.
    private mutating func perform(_ step: PhysicalStep, at index: Int, host: inout Host) -> (passed: Bool, read: Host.Read?) {
        switch step {
        case .setSelection(let range):
            writeError = host.setSelection(range)

        case .replaceSelection(let replacement):
            writeError = host.replaceSelection(replacement)

        case .press(let chord, let count):
            // A chord the host has no key for rings, as a plan that cannot run in the field does.
            guard host.beginPress(chord) else {
                host.bell()
                return (false, nil)
            }
            for _ in 0..<max(0, count) {
                // A landing's keys and the deadline stop a run too: a long one holds the keyboard and floods the app (LIN-2104).
                guard staysBeforeKey(of: step, host: &host), keysLeft != 0, !host.keysPastDeadline else { return (false, nil) }
                keysLeft = keysLeft.map { $0 - 1 }
                postedKeys = true
                host.sendKey(chord)
            }
            host.endPress(chord)
            return (count >= 0, nil)

        case .typeText(let text):
            guard staysBeforeKey(of: step, host: &host) else { return (false, nil) }
            postedKeys = true
            host.typeText(text)

        case .clipboardCut:
            guard staysBeforeKey(of: step, host: &host) else { return (false, nil) }
            postedKeys = true
            host.cut()

        case .clipboardCopy:
            guard staysBeforeKey(of: step, host: &host) else { return (false, nil) }
            postedKeys = true
            host.copy()

        case .clipboardInsert(let content):
            guard staysBeforeKey(of: step, host: &host) else { return (false, nil) }
            if let left = host.paste(content, at: index) {
                departure = left
                return (false, nil)
            }
            postedKeys = true

        case .captureSelectedText(let slot):
            guard let text = host.selectedText() else {
                host.bell()
                return (false, nil)
            }
            captures[slot] = text

        case .settle(let expectation):
            return settle(expectation, soft: false, at: index, host: &host)

        case .softSettle(let expectation):
            return settle(expectation, soft: true, at: index, host: &host)

        case .commit(let effect):
            // Keys the focus left did only part of what this records, and only an effect that survives an abort then applies.
            guard landed(host: &host) else {
                if effect.survivesAbort { host.commit(effect, captures: captures) }
                return (false, nil)
            }
            host.commit(effect, captures: captures)

        case .bell:
            host.bell()
        }
        return (true, nil)
    }

    /// A miss fails the run, but a soft settle's only where the ⌫ before it was ignored: blind keys before it promise nothing.
    private mutating func settle(
        _ expectation: Expectation, soft: Bool, at index: Int, host: inout Host
    ) -> (passed: Bool, read: Host.Read?) {
        let read = host.settle(expectation, at: index, generated: generated)
        generated = !read.passed || expectation.metByEmptyField
        if read.passed {
            if !soft, let slot = expectation.keeps, let caret = read.selection?.lowerBound { kept[slot] = caret }
            return (true, read)
        }
        // Only what the expectation asks about is read, as the runtime reads it.
        let failed = !soft || expectation.ignored(
            selection: expectation.landing == nil ? nil : read.selection, length: expectation.length == nil ? nil : read.length
        )
        misses.append(Miss(
            index: index, expectation: expectation, soft: soft, failed: failed, read: read, writeError: writeError
        ))
        guard failed else { return (true, read) }
        if stays(fresh: true, host: &host) { host.refused(expectation, read, soft: soft) }
        return (false, read)
    }

    /// Whether the focus is still where the command was verified; once not, the run says why.
    private mutating func stays(fresh: Bool, host: inout Host) -> Bool {
        if departure == nil { departure = host.departure(fresh: fresh) }
        return departure == nil
    }

    private mutating func staysBeforeKey(of step: PhysicalStep, host: inout Host) -> Bool {
        if departure == nil { departure = host.departure(beforeKeyOf: step) }
        return departure == nil
    }

    /// Whether the keys this run sent, if any, met the field with the focus still there.
    private mutating func landed(host: inout Host) -> Bool {
        postedKeys ? stays(fresh: true, host: &host) : departure == nil
    }
}

/// What carries a plan's steps out and reads the field for its settles, where the runtime and the Sim differ.
protocol StepHost {
    associatedtype Read: SettleRead

    /// The error the field returned for the write, if any.
    mutating func setSelection(_ range: Range<Int>) -> Int32?
    mutating func replaceSelection(_ replacement: String) -> Int32?

    /// A press's keys are about to go: false where the host has no key for `chord`.
    mutating func beginPress(_ chord: Chord) -> Bool
    mutating func sendKey(_ chord: Chord)
    /// Every key of the press went.
    mutating func endPress(_ chord: Chord)
    mutating func typeText(_ text: String)
    mutating func cut()
    mutating func copy()
    /// Pastes `content`, or what the user has on the pasteboard: why the focus left before ⌘V, where the host read that it did.
    mutating func paste(_ content: String?, at index: Int) -> KeyDestination.Departure?

    /// `AXSelectedText`, nil where it went unanswered.
    mutating func selectedText() -> String?
    /// The settle at `index` once the field meets `expectation` or the host stops waiting for it.
    mutating func settle(_ expectation: Expectation, at index: Int, generated: Bool) -> Read
    /// Why the focus has left the field, nil while it stays; `fresh` reads it all now, where a host spaces out a costly read.
    mutating func departure(fresh: Bool) -> KeyDestination.Departure?
    /// The same before each key of `step`, which the Sim's focus moves with.
    mutating func departure(beforeKeyOf step: PhysicalStep) -> KeyDestination.Departure?
    /// The deadline that stops reads has passed, which stops keys too.
    var keysPastDeadline: Bool { get }

    mutating func commit(_ effect: VimEffect, captures: [CaptureSlot: String])
    mutating func bell()
    /// A settle failed the run with the focus still on the field.
    mutating func refused(_ expectation: Expectation, _ read: Read, soft: Bool)
}

/// What a settle read, and whether that met its expectation.
protocol SettleRead {
    var passed: Bool { get }
    var selection: Range<Int>? { get }
    var length: Int? { get }
    var selectedText: String? { get }
}
