/// What uvim knows of letters an input method holds pending, and what its keys do about them (LIN-2053).
public enum Composition: Equatable, Sendable {
    case pending, clear, unknown

    /// Input methods whose candidate list is up whenever letters are pending, so its absence means none are.
    public static let listsCandidates: Set<String> = ["com.apple.inputmethod.SCIM.Shuangpin"]

    /// How long after a letter reaches the app Shuangpin can take to show it pending, in seconds: 0.05–0.22 measured.
    public static let lag = 0.25

    /// The field's own answer where it has one (`AXTextInputMarkedRange`'s length), else the candidate list's.
    public static func answer(markedLength: Int?, method: String, showsList: () -> Bool) -> Composition {
        if let markedLength { return markedLength > 0 ? .pending : .clear }
        if showsList() { return .pending }
        return listsCandidates.contains(method) ? .clear : .unknown
    }

    public enum Engage: Equatable, Sendable {
        /// Normal mode, as with no input method.
        case normal
        /// The key goes to the app, whose input method cancels the letters; Insert mode stays.
        case passThrough
        /// The commit key left the letters pending: a beep, and Insert mode stays.
        case refuse
    }

    /// An engage key in Insert mode; `commit` sends the commit key and answers again, and unknown is today's behaviour.
    public static func engage(_ token: String, read: () -> Composition, commit: () -> Composition) -> Engage {
        guard read() == .pending else { return .normal }
        if token == "<Esc>" { return .passThrough }
        return commit() == .pending ? .refuse : .normal
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
