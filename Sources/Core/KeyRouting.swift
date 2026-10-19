import CoreGraphics
import Foundation

/// A second tap, at the annotated stage where each key's target process is known, holding every key this process posts to
/// `KeyLedger`'s rule (LIN-1105): a check made before posting cannot see a focus change that lands after it, and `post`
/// returns before the key reaches the tap.
public final class KeyRouting: @unchecked Sendable {
    public static let shared = KeyRouting()

    private let lock = NSLock()
    private var ledger = KeyLedger()
    private var port: CFMachPort?

    private init() {}

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

    /// Holds the keys this process posts to `pid` until `finish`; false where it cannot, and nothing may then be posted.
    public func expect(_ pid: pid_t, wait: TimeInterval = 0.1) -> Bool {
        install()
        return until(wait) { $0.begin(pid, at: Self.now()) }
    }

    /// Ends the hold once the command's keys have all reached the tap, or leaves it for the ones still on their way.
    public func finish(wait: TimeInterval = 0.1) {
        _ = until(wait) { $0.end(at: Self.now()) }
    }

    /// Whether every key posted has reached the tap, waiting at most `wait` seconds.
    public func settle(wait: TimeInterval = 0.1) -> Bool {
        until(wait) { $0.settled(at: Self.now()) }
    }

    /// Whether a key of the running command was bound elsewhere, or went by while the tap was off.
    public var cancelled: Bool { lock.withLock { ledger.cancelled } }

    public func willPost() {
        lock.withLock { ledger.post(at: Self.now()) }
    }

    private func until(_ wait: TimeInterval, _ attempt: (inout KeyLedger) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(wait)
        while true {
            if lock.withLock({ port != nil && attempt(&ledger) }) { return true }
            if Date() >= deadline { return false }
            usleep(100)
        }
    }

    fileprivate func admits(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) else { return true }
        let target = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        return lock.withLock { ledger.admit(target: target) }
    }

    fileprivate func reenable() {
        lock.withLock {
            ledger.cancel()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        }
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
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
