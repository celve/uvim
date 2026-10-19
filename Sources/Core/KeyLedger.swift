/// The routing tap's rule for this process's own keys, apart from the tap so that it can be tested (LIN-1105). A command's
/// policy names the one process its keys may reach and the click count it was checked at. It starts and ends only once
/// every barrier posted has reached the tap, and from its first key bound elsewhere or behind a click it drops every key.
public struct KeyLedger: Sendable {
    /// The process the running command's keys may reach; it outlives the command while the command's keys are on their way.
    public private(set) var expected: Int32?
    public private(set) var cancelled = false
    private var presses: UInt32 = 0
    private var barriersPosted: UInt64 = 0
    private var barriersSeen: UInt64 = 0

    public init() {}

    /// Whether the tap has seen every barrier posted, and so, keys reaching it in the order posted, every key before them.
    public var settled: Bool { barriersSeen >= barriersPosted }

    /// Numbers a barrier about to be posted.
    public mutating func barrier() -> UInt64 {
        barriersPosted += 1
        return barriersPosted
    }

    /// One barrier vouches for every barrier posted before it.
    public mutating func saw(barrier id: UInt64) {
        barriersSeen = max(barriersSeen, id)
    }

    /// Puts a command's policy in force; false while a barrier is out, and the old policy then stays.
    public mutating func begin(_ pid: Int32, presses: UInt32) -> Bool {
        guard settled else { return false }
        expected = pid
        self.presses = presses
        cancelled = false
        return true
    }

    /// Ends the command's policy; false while a barrier is out, and the policy then stays for keys still on their way.
    public mutating func end() -> Bool {
        guard settled else { return false }
        expected = nil
        return true
    }

    /// The tap's verdict on one of this process's keys, routed to `target` when the session had counted `presses` clicks.
    public mutating func admit(target: Int32, presses now: UInt32) -> Bool {
        guard let expected else { return true }
        if !cancelled, target == expected, now == presses { return true }
        cancelled = true
        return false
    }

    /// The command saw the focus leave, or the tap was off: none of its keys may go any more.
    public mutating func cancel() {
        if expected != nil { cancelled = true }
    }
}
