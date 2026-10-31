// MARK: - Navigation selected by editor facts (LIN-2389)

/// `raw` with a U+FFFC at each plain offset, the text-less objects (rules, details buttons) a recording's marker text lost.
func withObjects(_ raw: String, at offsets: [Int]) -> String {
    var units = Array(raw.utf16)
    for offset in offsets.sorted(by: >) { units.insert(0xFFFC, at: offset) }
    return String(decoding: units, as: UTF16.self)
}

// The blocks recording's rules (roots 7, 9, 10, 12) and details buttons (14, 17).
let tiptapBlocksObjects = withObjects(tiptapBlocksRaw, at: [73, 81, 81, 93, 104, 125])

/// Where `keys` from the start of `line` land when Tiptap's keys are `navigation`'s structure rows.
func tiptapLanding(_ keys: [Chord], from line: String, _ model: UnreachableLines.Model) -> Int? {
    let start = lineStart(of: line, in: model.text)
    var landing = KeyModel(text: model.text, anchor: start, focus: start, stops: model.breaks.stops, cells: model.breaks.cells,
                           lastRows: model.breaks.lastRows)
    return keys.allSatisfy { landing.press($0) } && !landing.inGap ? landing.focus : nil
}

func testNavigation() {
    let blocks = folded(tiptapBlocksValue, tiptapBlocksObjects, fakeTree(tiptapBlocksSpec, linear: false))
    let tables = folded(tiptapTablesValue, tiptapTablesRaw, fakeTree(tiptapTablesSpec, linear: false))
    func at(_ line: String, _ model: UnreachableLines.Model) -> Int { lineStart(of: line, in: model.text) }
    precondition(blocks.breaks.editor == .proseMirror && tables.breaks.editor == .proseMirror)
    precondition(blocks.breaks.stops == [at("Para two", blocks): [.rule], at("Item three", blocks): [.rule, .ruleGap, .rule],
                                         at("Quote three", blocks): [.rule]],
                 "Tiptap's rules are stops, two with a gap cursor between, and no other block has one")
    precondition(tables.breaks.cells == Set(["Aone", "Atwo", "Bone", "Btwo", "Cone", "Ctwo", "Done", "Dtwo", "Eone", "Etwo", "Fone",
                                             "Gone"].map { at($0, tables) })
                 && tables.breaks.lastRows == Set(["Bone", "Done", "Eone", "Fone", "Gone"].map { at($0, tables) })
                 && tables.breaks.stops.isEmpty, "a root AXTable's cells are lines in row order, with no stop beside it")

    // Key lane, then lane B, each landing where softlash/LIN-2048 measured Tiptap's keys.
    precondition(linearKeys("j", "Para one", blocks) == [.paragraphEnd, .right, .right]
                 && linearKeys("j", "Para two", blocks) == [.paragraphEnd] + Array(repeating: .right, count: 4)
                 && linearKeys("k", "Item three", blocks) == [.paragraphStart] + Array(repeating: .left, count: 4) + [.paragraphStart],
                 "j and k press once more per rule and gap cursor")
    precondition(linearKeys("j", "Para one", blocks, profile: noLineKeys) == [.down, .down]
                 && linearKeys("j", "Para two", blocks, profile: noLineKeys) == Array(repeating: .down, count: 4)
                 && linearKeys("2j", "Para zero", blocks, profile: noLineKeys).prefix(3) == [.down, .down, .lineStart],
                 "past a rule ↓ lands at the line's start, where ⌘← would select the rule")
    precondition(linearKeys("k", "Para one", tables) == [.paragraphStart, .up, .paragraphStart]
                 && tiptapLanding(linearKeys("k", "Para one", tables), from: "Para one", tables) == at("Btwo", tables)
                 && tiptapLanding(linearKeys("2k", "Para one", tables), from: "Para one", tables) == at("Bone", tables),
                 "← from below a table skips it, so k goes up into its last cell")
    precondition(linearKeys("j", "Atwo", tables) == [.paragraphEnd, .right], "→ leaves a cell, ⌥→ lands on a word's end")
    precondition(linearKeys("j", "Atwo", tables, profile: noLineKeys) == [.lineEnd, .right]
                 && linearKeys("k", "Para one", tables, profile: noLineKeys) == [.lineStart, .up, .lineStart]
                 && linearKeys("j", "Para zero", tables, profile: noLineKeys) == [.lineEnd, .right],
                 "lane B crosses a table line by line, where ↓ and ↑ go by rows")
    precondition(linearKeys("j", "Btwo", tables, profile: noLineKeys) == [.down, .lineStart]
                 && linearKeys("2j", "Bone", tables, profile: noLineKeys) == [.lineEnd, .right, .down, .lineStart],
                 "it leaves a table's last cell by ↓, where Chromium's → can land before the table")
    precondition(linearKeys("j", "Cell one", tablesModel, profile: noLineKeys) == [.lineEnd, .right], "in Linear's tables too")

    // The rows Linear's facts override, and nothing else.
    let structure = Navigation.structure, linear = Navigation.linear
    precondition(structure.visiting == linear.visiting && structure.leaves[.gap] == linear.leaves[.gap]
                 && structure.otherwise[.rule] == .unknown && linear.otherwise[.rule] == .unknown)
    precondition(structure.leaves[.rule]?[.paragraphStart] == .unknown && linear.leaves[.rule]?[.paragraphStart] == .lineStart
                 && structure.leaves[.ruleGap]?[.paragraphEnd] == .unknown && linear.leaves[.ruleGap]?[.paragraphEnd] == .stay
                 && !structure.cellWordRight && linear.cellWordRight
                 && structure.upIntoTable == .lastLine && linear.upIntoTable == .lastRow)
    var ruleKeys = KeyModel(text: "a\nb", anchor: 1, focus: 1, stops: [2: [.rule]])
    precondition(ruleKeys.press(.right) && ruleKeys.inGap && !ruleKeys.press(.paragraphStart), "⌃A on a rule is each editor's")
    // prosemirror-view selects a rule beside a textblock's edge on ⌘ or ⌥ arrows, and moves between rules past a gap cursor.
    var edgeKeys = KeyModel(text: "a\nb\nc", anchor: 2, focus: 2, stops: [2: [.rule], 4: [.rule, .ruleGap, .rule]])
    precondition(edgeKeys.press(.lineStart) && edgeKeys.inStop == .init(line: 2, index: 0)
                 && edgeKeys.press(.lineStart) && edgeKeys.selection == 1..<1 && !edgeKeys.inGap, "⌘← at a line's start selects the rule")
    precondition(edgeKeys.press(.lineEnd) && edgeKeys.inStop == .init(line: 2, index: 0) && edgeKeys.press(.wordRight)
                 && edgeKeys.selection == 2..<2 && edgeKeys.press(.lineEnd) && edgeKeys.selection == 3..<3
                 && edgeKeys.press(.lineEnd) && edgeKeys.inStop == .init(line: 4, index: 0)
                 && edgeKeys.press(.lineEnd) && edgeKeys.inStop == .init(line: 4, index: 2) && edgeKeys.press(.wordLeft)
                 && edgeKeys.inStop == .init(line: 4, index: 0), "from a rule they pass the gap cursor to the next rule")
    edgeKeys = KeyModel(text: "ab\ncd", anchor: 4, focus: 4, stops: [3: [.rule]])
    precondition(edgeKeys.press(.lineStart) && edgeKeys.selection == 3..<3 && !edgeKeys.inGap, "off the edge ⌘← stays Cocoa's")
    var cellKeys = KeyModel(text: "p\nc1\nc2\nq", anchor: 4, focus: 4, cells: [2, 5], lastRows: [2])
    precondition(!cellKeys.press(.wordRight), "Tiptap's ⌥→ lands on the next cell's first word end, or the next row's start")
    cellKeys = KeyModel(text: "p\nc1\nc2\nq", anchor: 8, focus: 8, cells: [2, 5], lastRows: [2])
    precondition(cellKeys.press(.up) && cellKeys.selection == 5..<5, "↑ from column 0 below enters the last cell")
}
