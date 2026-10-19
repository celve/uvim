/// The routing tap's rule for this process's own keys, apart from the tap so that it can be tested (LIN-1105). A command's
/// policy names the one process its keys may reach. It starts once every key posted before it has reached the tap, ends once
/// every key the command posted has, and from the first key bound elsewhere it drops every later key of the command.
public struct KeyLedger: Sendable {
    /// Nanoseconds without a post after which keys never seen went by while the tap was off, and are let go.
    public static let stale: UInt64 = 250_000_000

    /// The process the running command's keys may reach; it outlives the command while the command's keys are on their way.
    public private(set) var expected: Int32?
    public private(set) var cancelled = false
    private var posted = 0
    private var seen = 0
    private var lastPost: UInt64 = 0

    public init() {}

    /// Whether every key posted has reached the tap, or none has been posted for `stale`.
    public func settled(at time: UInt64) -> Bool {
        seen >= posted || time >= lastPost + Self.stale
    }

    /// Puts a command's policy in force; false while keys from before are on their way, and the old policy then stays.
    public mutating func begin(_ pid: Int32, at time: UInt64) -> Bool {
        guard settled(at: time) else { return false }
        seen = posted
        expected = pid
        cancelled = false
        return true
    }

    /// Ends the command's policy; false while its keys are on their way, and the policy then stays for them.
    public mutating func end(at time: UInt64) -> Bool {
        guard settled(at: time) else { return false }
        seen = posted
        expected = nil
        return true
    }

    /// Counts a key before it is posted, since the tap can see it before `post` returns.
    public mutating func post(at time: UInt64) {
        posted += 1
        lastPost = time
    }

    /// The tap's verdict on one of this process's keys, which the window server is routing to `target`.
    public mutating func admit(target: Int32) -> Bool {
        seen += 1
        guard let expected else { return true }
        if !cancelled, target == expected { return true }
        cancelled = true
        return false
    }

    /// The tap was off for a while, so keys of the running command may have gone by unchecked.
    public mutating func cancel() {
        if expected != nil { cancelled = true }
    }
}
