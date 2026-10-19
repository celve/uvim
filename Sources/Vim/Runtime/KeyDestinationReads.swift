import AppKit
import Core

/// `KeyDestination`'s reads, which the window server and the routing tap answer while a command holds the main thread.
enum KeyDestinationReads {
    static func verified() -> KeyDestination {
        KeyDestination(presses: KeyRouting.presses())
    }

    static func departure(of destination: inout KeyDestination) -> KeyDestination.Departure? {
        destination.departure(presses: KeyRouting.presses(), routedAway: KeyRouting.shared.cancelled)
    }
}
