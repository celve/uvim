import AppKit
import Core

/// `KeyDestination`'s reads, which the window server answers while a command holds the main thread.
enum KeyDestinationReads {
    static func verified(_ pid: pid_t) -> KeyDestination {
        KeyDestination(pid: pid, presses: presses(), active: isActive(pid))
    }

    /// `readsActive` costs 0.2–3 ms, so the executor asks for it only now and then.
    static func departure(of destination: inout KeyDestination, readsActive: Bool) -> KeyDestination.Departure? {
        destination.departure(presses: presses(), active: readsActive ? isActive(destination.pid) : nil)
    }

    /// Releases are left out, as one can end a press made before the command.
    private static func presses() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

    /// A fresh instance, 17–40 ms behind a switch: a kept one, as NSWorkspace's, hears of it only on the main run loop.
    private static func isActive(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.isActive ?? false
    }
}
