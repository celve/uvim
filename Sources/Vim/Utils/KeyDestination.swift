/// Where a command's keys land, as read when it was verified: the active app and the session's button presses. A key
/// posted once a press was made, or once that app stopped being active, reaches another app or another place (LIN-1105).
public struct KeyDestination: Sendable {
    public enum Departure: String, Equatable, Sendable {
        case click, app
    }

    /// The app active when the command was verified; nil leaves only a click noticed.
    public let app: Int32?
    private let presses: UInt32
    private var departed: Departure?

    public init(app: Int32?, presses: UInt32) {
        self.app = app
        self.presses = presses
    }

    /// Why a key posted now would land elsewhere, for good once it has.
    public mutating func departure(presses now: UInt32, isActive: (Int32) -> Bool) -> Departure? {
        if departed == nil, now != presses { departed = .click }
        if departed == nil, let app, !isActive(app) { departed = .app }
        return departed
    }
}
