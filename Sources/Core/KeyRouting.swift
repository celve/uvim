import CoreGraphics
import Foundation

/// A second tap, at the annotated stage where each key's target process is known: while a command runs, it drops every
/// key this process posts that is bound for another process than the command's (LIN-1105). A check made before posting
/// cannot see a focus change that lands after it.
public final class KeyRouting: @unchecked Sendable {
    public static let shared = KeyRouting()

    private let lock = NSLock()
    private var expected: pid_t?
    private var dropped = false
    private var port: CFMachPort?
    private var started = false

    private init() {}

    /// Makes the tap on a thread of its own, once: the main thread is the one a command holds.
    public func install() {
        guard !started else { return }
        started = true
        let thread = Thread { [self] in
            let mask = CGEventMask(1) << CGEventType.keyDown.rawValue | CGEventMask(1) << CGEventType.keyUp.rawValue
            guard let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: keyRoutingCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                Log.system.error("the key routing tap was refused")
                return
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            lock.withLock { self.port = port }
            CFRunLoopRun()
        }
        thread.name = "uvim key routing"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Until `finish`, keys this process posts reach only `pid`; false where the tap is not up to see to it.
    @discardableResult
    public func expect(_ pid: pid_t) -> Bool {
        lock.withLock {
            expected = pid
            dropped = false
            return port != nil
        }
    }

    public func finish() {
        lock.withLock { expected = nil }
    }

    /// Whether a key was bound for another process since `expect`, and so dropped.
    public var droppedAny: Bool { lock.withLock { dropped } }

    fileprivate func admits(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) else { return true }
        return lock.withLock {
            guard let expected, event.getIntegerValueField(.eventTargetUnixProcessID) != Int64(expected) else { return true }
            dropped = true
            return false
        }
    }

    fileprivate func reenable() {
        if let port = lock.withLock({ port }) { CGEvent.tapEnable(tap: port, enable: true) }
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
