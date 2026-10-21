import AppKit
import CoreGraphics

/// Tags uvim's own synthesized CGEvents (via `kCGEventSourceUserData`) so the
/// consuming tap can bypass them — otherwise the engine would feed itself.
///
/// **The magic is a cross-app ABI.** Vibe tags its synthesized events with
/// the same value and both apps bypass tagged events before any handler runs;
/// never change it in one app without the other (see README).
public enum SynthTag {
    public static let magic: Int64 = 0x4345_4C56   // 'CELV'
    public static func tag(_ event: CGEvent?) { event?.setIntegerValueField(.eventSourceUserData, value: magic) }
    public static func isSelf(_ event: CGEvent) -> Bool { event.getIntegerValueField(.eventSourceUserData) == magic }
}

/// Synthesized-input primitives — the blind lane's actuator and the clipboard
/// paste fallback. Events go to the frontmost app (uvim is an accessory
/// agent), or to the one process `pid` names, which no other app's focus can
/// redirect (LIN-1105). Requires Accessibility permission. Every event is tagged.
public enum Synth {
    /// Below every session-level tap — including uvim's own. The executor
    /// settles *inside* the tap callback (main run loop held), so an event
    /// posted at `.cgSessionEventTap` parks at the window server awaiting
    /// uvim's own verdict — which uvim cannot render until the settle that
    /// is waiting for that very event gives up. Posting at the annotated
    /// stage delivers while the engine verifies; the tag stays as the
    /// cross-app ABI and defense-in-depth.
    private static let tapLocation: CGEventTapLocation = .cgAnnotatedSessionEventTap
    private static func source() -> CGEventSource? { CGEventSource(stateID: .combinedSessionState) }
    /// Between down and up for keys not measured without it, as arrows and ⌃A ⌃E were (LIN-1686); none between presses.
    public static let pairGap: TimeInterval = 0.002
    private static func nudge(_ seconds: TimeInterval = pairGap) { if seconds > 0 { Thread.sleep(forTimeInterval: seconds) } }

    private static func post(_ event: CGEvent, to pid: pid_t?) {
        SynthTag.tag(event)
        if let pid { event.postToPid(pid) } else { event.post(tap: tapLocation) }
    }

    /// Synthesize ⌘V (clipboard paste). Used by clipboard-insert steps.
    public static func commandV(to pid: pid_t? = nil) { key(0x09, .maskCommand, to: pid) }   // 0x09 = kVK_ANSI_V

    /// Post a key down+up with modifier flags (tagged), `gap` apart.
    public static func key(_ code: CGKeyCode, _ flags: CGEventFlags = [], gap: TimeInterval = pairGap, to pid: pid_t? = nil) {
        let src = source()
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.flags = flags; post(down, to: pid)
        }
        nudge(gap)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.flags = flags; post(up, to: pid)
        }
    }

    /// Posts `count` presses, stopping before the first `proceed` refuses; returns how many it posted.
    @discardableResult
    public static func key(
        _ code: CGKeyCode, _ flags: CGEventFlags = [], times count: Int, gap: TimeInterval = pairGap, to pid: pid_t? = nil,
        while proceed: () -> Bool = { true }
    ) -> Int {
        for posted in 0..<max(0, count) {
            guard proceed() else { return posted }
            key(code, flags, gap: gap, to: pid)
        }
        return max(0, count)
    }

    /// Type arbitrary Unicode (emoji/CJK verbatim — no layout mapping), tagged.
    public static func type(_ text: String, to pid: pid_t? = nil) {
        let src = source()
        let units = Array(text.utf16)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(down, to: pid)
        }
        nudge()
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(up, to: pid)
        }
    }
}
