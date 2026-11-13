import AppKit

/// The fork's runtime half of `ClipboardRoute`: writes yanks to the macOS
/// clipboard and notices text copied in other apps.
///
/// It tells copies made elsewhere from uvim's own writes by the pasteboard's
/// change count: every write uvim makes or accounts for (its yanks, and the
/// register paste's loan and restore) moves `known` along with it.
@MainActor
final class ClipboardSync {
    static let shared = ClipboardSync(.general)

    private let pasteboard: NSPasteboard
    private var known: Int

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        known = pasteboard.changeCount
    }

    /// Puts a yank or delete on the clipboard as plain text, as the user's own ⌘C would.
    func publish(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        known = pasteboard.changeCount
    }

    /// A write uvim made itself (the paste loan): not a copy from another app.
    func acknowledge() {
        known = pasteboard.changeCount
    }

    /// The text copied since uvim last looked, or nil when nothing new is there or it is not text.
    ///
    /// Each copy is reported once. Content marked transient (another tool's
    /// borrowed paste, like uvim's own loan) is skipped.
    func takeExternalText() -> String? {
        let count = pasteboard.changeCount
        guard count != known else { return nil }
        known = count
        guard pasteboard.types?.contains(PasteboardLoan.transient) != true else { return nil }
        return pasteboard.string(forType: .string)
    }
}
