/// What a node of a field's tree is, by its own reads: the field model's rules (softlash/LIN-2329 field-model.md §5). The text
/// only says where to look; these decide. C5, the text-less leaf, is read from the marker text's U+FFFCs
/// (`UnreachableLines.leafCounts`), and Linear's P1 stops and P2 code-block labels are `Linear`'s.
public enum FieldRules {
    /// C1: Chromium's own list marker, which no caret enters.
    public static func isListMarker(role: String?) -> Bool {
        role == "AXListMarker"
    }

    /// C2 and C3: text the page generates, as `li::before` content or a placeholder, which no DOM node backs (LIN-1930).
    public static func isGeneratedText(role: String?, generated: Bool) -> Bool {
        role == "AXStaticText" && generated
    }

    /// C4: an inline island a caret crosses in one step, as Linear's mention chip (LIN-1652).
    public static func isChip(subrole: String?) -> Bool {
        subrole == "AXApplicationGroup"
    }

    /// C6: a group with no children and no text, an empty paragraph's block or a caret Linear draws (LIN-1612, LIN-1683).
    public static func isEmptyBlock(subrole: String?, children: Int) -> Bool {
        subrole == "AXEmptyGroup" && children == 0
    }

    public static func isList(role: String?) -> Bool {
        role == "AXList"
    }

    /// Text, or a node with nothing under it, where a descent stops.
    public static func isLeaf(role: String?, children: Int) -> Bool {
        role == "AXStaticText" || children == 0
    }
}

extension EmptyBlockScan.Block {
    var isListMarker: Bool { FieldRules.isListMarker(role: role) }
    var isGeneratedText: Bool { FieldRules.isGeneratedText(role: role, generated: generated) }
    var isChip: Bool { FieldRules.isChip(subrole: subrole) }
    var isEmptyBlock: Bool { FieldRules.isEmptyBlock(subrole: subrole, children: children.count) }
    var isList: Bool { FieldRules.isList(role: role) }
    var isLeaf: Bool { FieldRules.isLeaf(role: role, children: children.count) }
}
