import ApplicationServices
import Core
import Foundation

/// Letters an input method holds pending in the bound field, read over AX (LIN-2053); `Composition` has the rules.
enum CompositionReads {
    /// Read again until pending while the letter the app got at uptime `letter` may not show as pending yet.
    static func answer(of binding: FocusTracker.Binding, method: String, letter: UInt64?) -> Composition {
        guard !binding.isForced else { return .unknown }
        let settled = letter.map { $0 + UInt64(Composition.lag * 1e9) } ?? 0
        var answer = read(binding, method: method)
        while answer != .pending, DispatchTime.now().uptimeNanoseconds < settled {
            Thread.sleep(forTimeInterval: 0.005)
            answer = read(binding, method: method)
        }
        return answer
    }

    /// F13, which Shuangpin takes to commit the letters as typed; answers once they are no longer pending, or after 150 ms.
    static func commit(on binding: FocusTracker.Binding, method: String) -> Composition {
        // Chromium's value shows the commit up to 42 ms after its candidate list closes, and the Esc plan reads the value.
        let lagging = AX.inputMarkedRange(of: binding.element) == nil ? AX.value(of: binding.element) : nil
        Synth.key(105)   // kVK_F13
        let deadline = Date().addingTimeInterval(0.15)
        var answer = read(binding, method: method)
        while answer == .pending, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.003)
            answer = read(binding, method: method)
        }
        if answer != .pending, let lagging {
            let shown = Date().addingTimeInterval(0.1)
            while AX.value(of: binding.element) == lagging, Date() < shown { Thread.sleep(forTimeInterval: 0.003) }
        }
        return answer
    }

    private static func read(_ binding: FocusTracker.Binding, method: String) -> Composition {
        Composition.answer(markedLength: AX.inputMarkedRange(of: binding.element)?.length, method: method) {
            showsCandidates(binding.pid)
        }
    }

    /// Shuangpin's candidate bar is an untitled dialog among the app's own windows, holding this list.
    private static func showsCandidates(_ pid: pid_t) -> Bool {
        let windows = AX.attributes([kAXWindowsAttribute], of: AXUIElementCreateApplication(pid)).elements(0) ?? []
        return windows.contains { window in
            let reads = AX.attributes([kAXSubroleAttribute, kAXChildrenAttribute], of: window)
            guard reads.string(0) != kAXStandardWindowSubrole else { return false }
            return (reads.elements(1) ?? []).contains {
                AX.attributes([kAXIdentifierAttribute], of: $0).string(0) == "InputMethodCandidateList"
            }
        }
    }
}
