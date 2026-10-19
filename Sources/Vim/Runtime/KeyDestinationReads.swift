import AppKit
import Core

/// `KeyDestination`'s reads, which the window server and the routing tap answer while a command holds the main thread.
enum KeyDestinationReads {
    static func verified() -> KeyDestination {
        KeyDestination(presses: presses())
    }

    static func departure(of destination: inout KeyDestination) -> KeyDestination.Departure? {
        destination.departure(presses: presses(), routedAway: KeyRouting.shared.droppedAny)
    }

    /// Presses only: a release can end a press made before the command.
    private static func presses() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
}
