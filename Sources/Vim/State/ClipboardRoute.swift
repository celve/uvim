// The app's Vim framework links Core; `make test` builds ClipboardMode into the same module, where there is no Core to import.
#if canImport(Core)
import Core
#endif

/// The fork's clipboard rules, pure so the engine tests pin them: which
/// committed effects reach the macOS clipboard, and when text copied in
/// another app becomes what `p` puts.
public enum ClipboardRoute {
    /// The text `effect` sends to the clipboard under `mode`, or nil when it stays in uvim's registers.
    ///
    /// A `.pasteboard` payload is never sent: the app's own ⌘C/⌘X already put it there.
    public static func text(
        for effect: VimEffect, captures: [CaptureSlot: String], mode: ClipboardMode
    ) -> String? {
        let register: Register?
        let payload: TextPayload
        let yank: Bool
        switch effect {
        case .yanked(let into, let content, _):
            (register, payload, yank) = (into, content, true)
        case .deleted(let into, let content, _):
            (register, payload, yank) = (into, content, false)
        default:
            return nil
        }
        guard reaches(register, yank: yank, mode: mode) else { return nil }
        switch payload {
        case .literal(let text): return text
        case .captured(let slot): return captures[slot]
        case .pasteboard: return nil
        }
    }

    /// `"+`/`"*` always; the unnamed register as the mode says; named, numbered and `"_` never.
    static func reaches(_ register: Register?, yank: Bool, mode: ClipboardMode) -> Bool {
        switch register?.name {
        case "+", "*": return true
        case nil: return mode == .unnamed || (mode == .yank && yank)
        default: return false
        }
    }

    /// Whether text copied elsewhere should become the unnamed register.
    ///
    /// Not when the unnamed register is already a pasteboard marker: it
    /// already puts whatever the clipboard holds, and its wise came from the
    /// cut that made it, which a guess from the text must not overwrite.
    public static func adoptsExternal(mode: ClipboardMode, unnamed: RegisterSlot?) -> Bool {
        guard mode != .off else { return false }
        if case .pasteboard = unnamed { return false }
        return true
    }

    /// The wise a put of copied text takes: a trailing newline means whole lines, as Vim reads the clipboard.
    public static func wise(ofExternal text: String) -> Wise {
        text.hasSuffix("\n") ? .line : .character
    }
}
