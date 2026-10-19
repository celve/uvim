import AppKit

/// `KeyDestination`'s reads, answered by the window server and LaunchServices while a command holds the main thread.
enum KeyDestinationReads {
    /// The front app as the main run loop last heard of it: the first check asks LaunchServices whether it still is.
    static func verified() -> KeyDestination {
        KeyDestination(app: NSWorkspace.shared.frontmostApplication?.processIdentifier, presses: presses())
    }

    /// Asks LaunchServices when `fresh`, else takes `watch`'s last answer, starting it at the first such check.
    static func departure(
        of destination: inout KeyDestination, fresh: Bool, watch: inout ActiveWatch?
    ) -> KeyDestination.Departure? {
        destination.departure(presses: presses()) { app in
            guard !fresh else { return isActive(app) }
            let current = watch ?? ActiveWatch(app)
            watch = current
            return current.isActive
        }
    }

    /// A new instance: a kept one's `isActive`, like NSWorkspace's answers, changes only as the main run loop turns.
    static func isActive(_ app: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: app)?.isActive ?? false
    }

    /// Presses only: a release can end a press made before the command.
    private static func presses() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
}

/// Asks LaunchServices off the main thread, which a run of keys would otherwise hold about 2 ms an answer while they flood
/// the window server.
final class ActiveWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))

    init(_ app: pid_t) {
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let answer = KeyDestinationReads.isActive(app)
            lock.withLock { self.active = answer }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(2))
        timer.resume()
    }

    var isActive: Bool { lock.withLock { active } }

    deinit { timer.cancel() }
}
