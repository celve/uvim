import CoreGraphics
import Foundation

/// A second tap, at the annotated stage where each key's target process is known, holding every key this process posts to
/// `KeyLedger`'s rule (LIN-1105): a check made before posting cannot see a focus change that lands after it, and `post`
/// returns before the key reaches the tap.
public final class KeyRouting: @unchecked Sendable {
    public static let shared = KeyRouting()

    /// A barrier's `eventSourceUserData`, its number in the low half; the tap drops it, and no key sends key code 0xFF.
    private static let barrierMark: Int64 = 0x4C49_4E00 << 32
    private static let barrierKey: CGKeyCode = 0xFF

    private let lock = NSLock()
    private var ledger = KeyLedger()
    private var port: CFMachPort?

    private init() {}

    /// The session's button presses, which move at the press; releases are left out, as one can end a press made earlier.
    public static func presses() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

    /// Makes the tap, unless it is up, and returns once a thread of its own services it: the main thread is the one a
    /// command holds.
    public func install() {
        guard lock.withLock({ port == nil }) else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue | CGEventMask(1) << CGEventType.keyUp.rawValue
        guard let port = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: keyRoutingCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.system.error("the key routing tap was refused")
            return
        }
        CGEvent.tapEnable(tap: port, enable: false)
        let running = DispatchSemaphore(value: 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
            running.signal()
            CFRunLoopRun()
        }
        thread.name = "uvim key routing"
        thread.qualityOfService = .userInteractive
        thread.start()
        running.wait()
        CGEvent.tapEnable(tap: port, enable: true)
        lock.withLock { self.port = port }
    }

    /// Holds the keys this process posts to `pid`, as checked at `presses` clicks, until `finish`; false where it cannot,
    /// and nothing may then be posted.
    public func expect(_ pid: pid_t, presses: UInt32, wait: TimeInterval = 0.1) -> Bool {
        install()
        guard settle(wait: wait) else { return false }
        return lock.withLock { ledger.begin(pid, presses: presses) }
    }

    /// Ends the hold once the command's keys have all passed the tap, or leaves it for the ones still on their way.
    public func finish(wait: TimeInterval = 0.1) {
        guard settle(wait: wait) else { return }
        _ = lock.withLock { ledger.end() }
    }

    /// Whether every key this process posted has passed the tap, as a barrier posted behind them shows, within `wait` seconds.
    public func settle(wait: TimeInterval = 0.1) -> Bool {
        guard lock.withLock({ port != nil }),
              let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: Self.barrierKey,
                                  keyDown: false) else { return false }
        let id = lock.withLock { ledger.barrier() }
        event.setIntegerValueField(.eventSourceUserData, value: Self.barrierMark | Int64(truncatingIfNeeded: id & 0xFFFF_FFFF))
        event.post(tap: .cgAnnotatedSessionEventTap)
        let deadline = Date().addingTimeInterval(wait)
        while !lock.withLock({ ledger.settled }) {
            if Date() >= deadline { return false }
            usleep(50)
        }
        return true
    }

    /// Whether a key of the running command was bound elsewhere or behind a click, or the command was cancelled.
    public var cancelled: Bool { lock.withLock { ledger.cancelled } }

    public func cancel() {
        lock.withLock { ledger.cancel() }
    }

    fileprivate func admits(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) else { return true }
        let data = event.getIntegerValueField(.eventSourceUserData)
        if data & ~Int64(0xFFFF_FFFF) == Self.barrierMark {
            lock.withLock { ledger.saw(barrier: UInt64(data & 0xFFFF_FFFF)) }
            return false
        }
        let target = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        let presses = Self.presses()
        return lock.withLock { ledger.admit(target: target, presses: presses) }
    }

    fileprivate func reenable() {
        lock.withLock {
            ledger.cancel()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        }
    }
}

private func keyRoutingCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let routing = Unmanaged<KeyRouting>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        routing.reenable()
        return Unmanaged.passUnretained(event)
    }
    return routing.admits(event) ? Unmanaged.passUnretained(event) : nil
}
