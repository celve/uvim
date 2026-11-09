/// The editor facts in scope for a field, each from DOM classes: they choose the structure its walk reads and the rows of its
/// `Navigation` (softlash/LIN-2329 field-model.md §5 L4).
public struct EditorFacts: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `editor:prosemirror` on the field: a root rule is a node every arrow selects first, two rules have a gap cursor between
    /// them, and a root table's cells are lines in row order (softlash/LIN-2048, shared by Linear and Tiptap).
    public static let proseMirror = EditorFacts(rawValue: 1)
    /// A root block carries one of Linear's own classes: its stops between blocks, and its own keys at rules and tables.
    public static let linear = EditorFacts(rawValue: 2)
    /// `editor:editor-kit` on the field, Lark's composer: ⌃A and ⌃E are its own commands, which ignore ⇧ (LIN-1975).
    public static let editorKit = EditorFacts(rawValue: 4)

    /// The facts a field's own DOM classes give; ProseMirror's reach the walk by `FieldSnapshot.Reads.proseMirror` instead.
    public init(classes: [String]) {
        self = Surface.editor(classes: classes) == "editor-kit" ? .editorKit : []
    }
}
