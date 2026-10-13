public enum TapStanding: Equatable, Sendable {
    case waiting, installed
    /// macOS refused it with Accessibility granted: the process started without it, or Input Monitoring is off for uvim.
    case refused

    /// macOS judges a process once, at an attempt or at a launch that finds uvim switched off, so the attempt waits for the grant.
    public func attempts(wanted: Bool, trusted: Bool) -> Bool {
        self == .waiting && wanted && trusted
    }

    /// Refused after starting without Accessibility, a process was turned down for good, and only a new one gets a tap.
    public func handsOver(startedTrusted: Bool) -> Bool {
        self == .refused && !startedTrusted
    }
}
