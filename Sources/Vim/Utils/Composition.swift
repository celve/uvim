/// What uvim knows of letters an input method holds pending, and what its keys do about them (LIN-2053).
public enum Composition: Equatable, Sendable {
    case pending, clear, unknown

    /// Input methods whose candidate list is up whenever letters are pending, so its absence means none are.
    public static let listsCandidates: Set<String> = ["com.apple.inputmethod.SCIM.Shuangpin"]

    /// How long after a letter reaches the app Shuangpin can take to show it pending, in seconds: 0.05–0.22 measured.
    public static let lag = 0.25

    /// What the field's `AXTextInputMarkedRange` answered.
    public enum Marked: Equatable, Sendable {
        case length(Int)
        /// The field has no such attribute, as in Chromium.
        case absent
        case failed
    }

    /// The field's own answer where it has one, else the candidate list's; `showsList` is nil when a read failed.
    public static func answer(marked: Marked, method: String, showsList: () -> Bool?) -> Composition {
        switch marked {
        case .length(let length): return length > 0 ? .pending : .clear
        case .failed: return .unknown
        case .absent:
            guard let shows = showsList() else { return .unknown }
            return shows ? .pending : listsCandidates.contains(method) ? .clear : .unknown
        }
    }

    public enum Engage: Equatable, Sendable {
        /// Normal mode, as with no input method.
        case normal
        /// The key goes to the app, whose input method cancels the letters; Insert mode stays.
        case passThrough
        /// Nothing read the letters as committed after the commit key: a beep, and Insert mode stays.
        case refuse
    }

    /// An engage key in Insert mode; unknown at first is today's behaviour, but after `commit` only clear enters Normal.
    public static func engage(_ token: String, read: () -> Composition, commit: () -> Composition) -> Engage {
        guard read() == .pending else { return .normal }
        if token == "<Esc>" { return .passThrough }
        return commit() == .clear ? .normal : .refuse
    }

    /// A Normal- or Visual-mode command runs unless letters are pending, but plain `i` goes back to them.
    public static func runs(_ command: RawCommand, read: () -> Composition) -> Bool {
        command.source == "i" || read() != .pending
    }
}

// MARK: - Recorder

extension Composition {
    var traceName: String {
        switch self {
        case .pending: return "pending"
        case .clear: return "clear"
        case .unknown: return "unknown"
        }
    }
}

extension Composition.Engage {
    var traceName: String {
        switch self {
        case .normal: return "normal"
        case .passThrough: return "pass"
        case .refuse: return "refuse"
        }
    }
}
