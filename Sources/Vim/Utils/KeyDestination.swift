/// Where a running command's keys go: the bound field's process, which each key is addressed to so that no other app can
/// take one (LIN-1105), with the session's button presses and whether that app was active when the command was verified.
public struct KeyDestination: Sendable {
    public enum Departure: String, Equatable, Sendable {
        case click, app
    }

    public let pid: Int32
    /// The session's button presses when the command was verified.
    public let presses: UInt32
    /// An app that was not active then, as an overlay's is not, has no activation to lose.
    public let active: Bool
    private var departed: Departure?

    public init(pid: Int32, presses: UInt32, active: Bool) {
        self.pid = pid
        self.presses = presses
        self.active = active
    }

    /// Why the focus has left the field, for good once it has; `active` is nil where it was not read.
    public mutating func departure(presses now: UInt32, active nowActive: Bool?) -> Departure? {
        if departed == nil, now != presses { departed = .click }
        if departed == nil, active, nowActive == false { departed = .app }
        return departed
    }
}
