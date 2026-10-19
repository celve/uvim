/// Where a command's keys land, as read when it was verified: the session's button presses, and the process the keys are
/// routed to, which `KeyRouting` holds them to. A key posted once a press was made reaches another place (LIN-1105).
public struct KeyDestination: Sendable {
    public enum Departure: String, Equatable, Sendable {
        case click, app, unrouted
    }

    /// The session's button presses when the command was verified.
    public let presses: UInt32
    /// Whether `KeyRouting` holds this command's keys to its process; without that no key may be posted.
    public var routed = false
    private var departed: Departure?

    public init(presses: UInt32) {
        self.presses = presses
    }

    /// Why a key posted now would land elsewhere, for good once it has; `routedAway` is a key already dropped as bound elsewhere.
    public mutating func departure(presses now: UInt32, routedAway: Bool) -> Departure? {
        if departed == nil, !routed { departed = .unrouted }
        if departed == nil, now != presses { departed = .click }
        if departed == nil, routedAway { departed = .app }
        return departed
    }
}
