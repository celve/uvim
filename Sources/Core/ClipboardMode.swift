/// Where uvim's yanks and deletes meet the macOS clipboard (fork setting).
///
/// `"+` and `"*` always read and write the clipboard, whatever the mode: the
/// user named it. The mode decides only what unnamed yanks and deletes do.
public enum ClipboardMode: String, CaseIterable, Sendable {
    /// Upstream behaviour: registers stay inside uvim.
    case off
    /// Unnamed yanks reach the clipboard; deletes stay in uvim's registers.
    case yank
    /// Unnamed yanks and deletes both reach it, as Vim's `clipboard=unnamedplus`.
    case unnamed
}

/// Which apps uvim engages in (fork setting).
public enum AppScope: String, CaseIterable, Sendable {
    /// Every app except those set to Off: upstream behaviour.
    case everywhere
    /// Only apps explicitly set to Auto or Force; every other app is Off.
    case onlyAllowed
}
