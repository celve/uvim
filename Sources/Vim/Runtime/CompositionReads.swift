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

    /// F13, which Shuangpin takes to commit the letters as typed; answers once they read clear, or after 150 ms.
    static func commit(on binding: FocusTracker.Binding, method: String) -> Composition {
        // Chromium's value shows the commit up to 42 ms after its candidate list closes, and the Esc plan reads the value.
        let lagging = marked(binding.element) == .absent ? AX.value(of: binding.element) : nil
        Synth.key(105)   // kVK_F13
        let deadline = Date().addingTimeInterval(0.15)
        var answer = read(binding, method: method)
        while answer != .clear, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.003)
            answer = read(binding, method: method)
        }
        if answer == .clear, let lagging {
            let shown = Date().addingTimeInterval(0.1)
            while AX.value(of: binding.element) ?? lagging == lagging, Date() < shown { Thread.sleep(forTimeInterval: 0.003) }
        }
        return answer
    }

    private static func read(_ binding: FocusTracker.Binding, method: String) -> Composition {
        Composition.answer(marked: marked(binding.element), method: method) { showsCandidates(binding.pid) }
    }

    private static func marked(_ element: AXUIElement) -> Composition.Marked {
        let reads = AX.attributes(["AXTextInputMarkedRange"], of: element)
        guard FieldTree.absentOrRead(reads, 0) else { return .failed }
        return reads.range(0).map { .length($0.length) } ?? .absent
    }

    /// Shuangpin's candidate bar is an untitled dialog among the app's own windows, holding this list; nil when a read failed.
    private static func showsCandidates(_ pid: pid_t) -> Bool? {
        guard let windows = AX.attributes([kAXWindowsAttribute], of: AXUIElementCreateApplication(pid)).elements(0) else {
            return nil
        }
        var failed = false
        for window in windows {
            let reads = AX.attributes([kAXSubroleAttribute, kAXChildrenAttribute], of: window)
            guard FieldTree.absentOrRead(reads, 0), FieldTree.absentOrRead(reads, 1) else {
                failed = true
                continue
            }
            guard reads.string(0) != kAXStandardWindowSubrole else { continue }
            for child in reads.elements(1) ?? [] {
                let identifier = AX.attributes([kAXIdentifierAttribute], of: child)
                if identifier.string(0) == "InputMethodCandidateList" { return true }
                if !FieldTree.absentOrRead(identifier, 0) { failed = true }
            }
        }
        return failed ? nil : false
    }
}
