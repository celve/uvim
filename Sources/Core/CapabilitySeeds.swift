/// Shipped curation: surfaces where a capability defaults off.
///
/// Compiled in and never written to defaults, so a seed change always reaches
/// users — the deliberate opposite of `Prefs`, which seeds via
/// `register(defaults:)` and trades future seed additions for the ability to
/// remember a removal. Nothing here is probed; seeds are decided, and the
/// user's explicit `.on` un-seeds any of them.
///
/// Pure and `Foundation`-free so `make test` can pin the real literal rather
/// than a copy of it: a renamed atom or a rung no surface can produce would
/// otherwise orphan curation in silence.
public enum CapabilitySeeds {
    /// Rung → the capabilities it denies; keyed by no app or host, since one written by hand breaks unnoticed when a site moves (LIN-1850).
    public static let denied: [String: Set<String>] = [
        Surface.everywhere: ["nativeMotions"],
    ]
}
