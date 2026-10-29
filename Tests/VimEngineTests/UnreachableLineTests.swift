// MARK: - Unreachable lines (LIN-1652)

// Dia 1.49.1 on linear.app, probed by softlash/LIN-1652 scripts/list-probe.
let dia1Value = [
    "Top paragraph of the LIN-1652 disposable list probe.", "1.", "Numbered one", "2.", "Numbered two", "a.",
    "Nested numbered one", "b.", "Nested numbered two", "3.", "Numbered three",
    "Middle paragraph after the numbered list.", "\u{2022}", "Bullet one", "\u{25E6}", "Nested bullet one",
    "\u{2022}", "Double nested bullet", "\u{2022}", "Bullet with a mention ",
    "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)", "\u{2022}", "Bullet two", "", "",
    "Heading two", "", "", "To-do open", "", "", "To-do done", "1.", "Paragraph after a literal one-dot line.",
    "\u{2022}", "9.", "Ninth item", "10.", "Tenth item", "11.", "Eleventh item", "Last paragraph."
].joined(separator: "\n")
let dia1Raw = "Top paragraph of the LIN-1652 disposable list probe.1.Numbered one2.Numbered twoa.Nested numbered o"
    + "neb.Nested numbered two3.Numbered threeMiddle paragraph after the numbered list.\u{2022}Bullet one\u{25E6}"
    + "Nested bullet one\u{2022}Double nested bullet\u{2022}Bullet with a mention \u{2060}\u{00A0}LIN-1645"
    + " Why j/k always beeps in Linear (macbook14 logs)\n\u{2022}Bullet two\u{FFFC}\u{FFFC}Heading two\u{FFFC}"
    + "\u{FFFC}To-do open\u{FFFC}\u{FFFC}To-do done1.Paragraph after a literal one-dot line.\u{2022}9.Nint"
    + "h item10.Tenth item11.Eleventh itemLast paragraph."
let dia1Spec = """
0/G/0/52 0.0/T/0/52 1/L/52/138 1.0/G/52/66 1.0.0/G/52/54 1.0.0.0/Tg/52/53 1.0.0.1/Tg/53/54 1.0.1/G/54/66
1.0.1.0/T/54/66 1.1/G/66/122 1.1.0/G/66/68 1.1.0.0/Tg/66/67 1.1.0.1/Tg/67/68 1.1.1/G/68/80 1.1.1.0/T/68/80
1.1.2/L/80/122 1.1.2.0/G/80/101 1.1.2.0.0/G/80/82 1.1.2.0.0.0/Tg/80/81 1.1.2.0.0.1/Tg/81/82 1.1.2.0.1/G/82/101
1.1.2.0.1.0/T/82/101 1.1.2.1/G/101/122 1.1.2.1.0/G/101/103 1.1.2.1.0.0/Tg/101/102 1.1.2.1.0.1/Tg/102/103
1.1.2.1.1/G/103/122 1.1.2.1.1.0/T/103/122 1.2/G/122/138 1.2.0/G/122/124 1.2.0.0/Tg/122/123 1.2.0.1/Tg/123/124
1.2.1/G/124/138 1.2.1.0/T/124/138 2/G/138/179 2.0/T/138/179 3/L/179/322 3.0/G/179/229 3.0.0/G/179/180
3.0.0.0/Tg/179/180 3.0.1/G/180/190 3.0.1.0/T/180/190 3.0.2/L/190/229 3.0.2.0/G/190/229 3.0.2.0.0/G/190/191
3.0.2.0.0.0/Tg/190/191 3.0.2.0.1/G/191/208 3.0.2.0.1.0/T/191/208 3.0.2.0.2/L/208/229 3.0.2.0.2.0/G/208/229
3.0.2.0.2.0.0/G/208/209 3.0.2.0.2.0.0.0/Tg/208/209 3.0.2.0.2.0.1/G/209/229 3.0.2.0.2.0.1.0/T/209/229
3.1/G/229/311 3.1.0/G/229/230 3.1.0.0/Tg/229/230 3.1.1/G/230/311 3.1.1.0/T/230/252 3.1.1.1/A/252/310
3.1.1.1.0/K/252/310 3.1.1.1.0.0/T/252/253 3.1.1.1.0.1/T/253/254 3.1.1.1.0.2/T/254/262 3.1.1.1.0.3/T/262/263
3.1.1.1.0.4/T/263/310 3.2/G/311/322 3.2.0/G/311/312 3.2.0.0/Tg/311/312 3.2.1/G/312/322 3.2.1.0/T/312/322
4/H/322/333 4.0/G/322/322 4.0.0/G/322/322 4.0.0.0/E/322/322 4.0.0.1/P/322/322 4.1/T/322/333 5/L/333/353
5.0/G/333/343 5.0.0/G/333/333 5.0.0.0/I/333/333 5.0.0.1/C/333/333 5.0.1/G/333/343 5.0.1.0/G/333/343
5.0.1.0.0/T/333/343 5.1/G/343/353 5.1.0/G/343/343 5.1.0.0/I/343/343 5.1.0.1/C/343/343 5.1.1/G/343/353
5.1.1.0/G/343/353 5.1.1.0.0/T/343/353 6/G/353/355 6.0/T/353/355 7/G/355/394 7.0/T/355/394 8/G/394/395
8.0/T/394/395 9/L/395/436 9.0/G/395/407 9.0.0/G/395/397 9.0.0.0/Tg/395/396 9.0.0.1/Tg/396/397 9.0.1/G/397/407
9.0.1.0/T/397/407 9.1/G/407/420 9.1.0/G/407/410 9.1.0.0/Tg/407/409 9.1.0.1/Tg/409/410 9.1.1/G/410/420
9.1.1.0/T/410/420 9.2/G/420/436 9.2.0/G/420/423 9.2.0.0/Tg/420/422 9.2.0.1/Tg/422/423 9.2.1/G/423/436
9.2.1.0/T/423/436 10/G/436/451 10.0/T/436/451
"""
let dia1Tree = fakeTree(dia1Spec)

let dia1Plain = MarkerText.plain(dia1Raw)
let dia1Aligned = ParagraphBreaks(value: dia1Value, fieldText: dia1Plain)!

let dia1Lines = [
    "Top paragraph of the LIN-1652 disposable list probe.", "Numbered one", "Numbered two", "Nested numbered one",
    "Nested numbered two", "Numbered three", "Middle paragraph after the numbered list.", "Bullet one", "Nested bullet one",
    "Double nested bullet", "Bullet with a mention \u{2060}", "Bullet two", "Heading two", "To-do open", "To-do done", "1.",
    "Paragraph after a literal one-dot line.", "\u{2022}", "Ninth item", "Tenth item", "Eleventh item", "Last paragraph.",
]
let dia1Model = folded(dia1Value, dia1Raw, dia1Tree)

// Chips inside, ending, starting and alone in paragraphs and items.
let dia6Value = [
    "Chip probe opening paragraph.", "Before ",
    "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)", " after the chip.",
    "Text then a chip ",
    "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)", " chip then text.",
    "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    "\u{2022}", "Item before ", "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)",
    " and after", "\u{2022}", "Plain item", "\u{2022}",
    "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    " chip first item", "Closing paragraph of the chip probe."
].joined(separator: "\n")
let dia6Raw = "Chip probe opening paragraph.Before \u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macboo"
    + "k14 logs) after the chip.Text then a chip \u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots wit"
    + "h one pure builder shared by the runtime and the Sim\n\u{2060}\u{00A0}LIN-1645 Why j/k always beeps"
    + " in Linear (macbook14 logs) chip then text.\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots wi"
    + "th one pure builder shared by the runtime and the Sim\n\u{2022}Item before \u{2060}\u{00A0}LIN-1645"
    + " Why j/k always beeps in Linear (macbook14 logs) and after\u{2022}Plain item\u{2022}\u{2060}\u{00A0}"
    + "LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim chip "
    + "first itemClosing paragraph of the chip probe."
let dia6Tree = fakeTree("""
0/G/0/29 0.0/T/0/29 1/G/29/110 1.0/T/29/36 1.1/A/36/94 1.1.0/K/36/94 1.1.0.0/T/36/37 1.1.0.1/T/37/38
1.1.0.2/T/38/46 1.1.0.3/T/46/47 1.1.0.4/T/47/94 1.2/T/94/110 2/G/110/223 2.0/T/110/127 2.1/A/127/222
2.1.0/K/127/222 2.1.0.0/T/127/128 2.1.0.1/T/128/129 2.1.0.2/T/129/137 2.1.0.3/T/137/138 2.1.0.4/T/138/222
3/G/223/297 3.0/A/223/281 3.0.0/K/223/281 3.0.0.0/T/223/224 3.0.0.1/T/224/225 3.0.0.2/T/225/233
3.0.0.3/T/233/234 3.0.0.4/T/234/281 3.1/T/281/297 4/G/297/393 4.0/A/297/392 4.0.0/K/297/392 4.0.0.0/T/297/298
4.0.0.1/T/298/299 4.0.0.2/T/299/307 4.0.0.3/T/307/308 4.0.0.4/T/308/392 5/L/393/597 5.0/G/393/474
5.0.0/G/393/394 5.0.0.0/Tg/393/394 5.0.1/G/394/474 5.0.1.0/T/394/406 5.0.1.1/A/406/464 5.0.1.1.0/K/406/464
5.0.1.1.0.0/T/406/407 5.0.1.1.0.1/T/407/408 5.0.1.1.0.2/T/408/416 5.0.1.1.0.3/T/416/417 5.0.1.1.0.4/T/417/464
5.0.1.2/T/464/474 5.1/G/474/485 5.1.0/G/474/475 5.1.0.0/Tg/474/475 5.1.1/G/475/485 5.1.1.0/T/475/485
5.2/G/485/597 5.2.0/G/485/486 5.2.0.0/Tg/485/486 5.2.1/G/486/597 5.2.1.0/A/486/581 5.2.1.0.0/K/486/581
5.2.1.0.0.0/T/486/487 5.2.1.0.0.1/T/487/488 5.2.1.0.0.2/T/488/496 5.2.1.0.0.3/T/496/497 5.2.1.0.0.4/T/497/581
5.2.1.1/T/581/597 6/G/597/633 6.0/T/597/633
""")

let dia6Model = folded(dia6Value, dia6Raw, dia6Tree)

// A space after a chip shares the chip's line.
let dia7Value = [
    "Space probe opening paragraph.", "Two chips ",
    "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs) ",
    "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    " end.", "Chip then space ", "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)",
    "\u{2022}", "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    "\u{2022}", "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs) ",
    "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
    "\u{2022}", "Plain item", "Closing paragraph of the space probe.",
].joined(separator: "\n")
let dia7Raw = "Space probe opening paragraph.Two chips \u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear "
    + "(macbook14 logs) \u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder sha"
    + "red by the runtime and the Sim end.Chip then space \u{2060}\u{00A0}LIN-1645 Why j/k always beeps"
    + " in Linear (macbook14 logs)\n\u{2022}\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with "
    + "one pure builder shared by the runtime and the Sim\n\u{2022}\u{2060}\u{00A0}LIN-1645 Why j/k alw"
    + "ays beeps in Linear (macbook14 logs) \u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with "
    + "one pure builder shared by the runtime and the Sim\n\u{2022}Plain itemClosing paragraph of the s"
    + "pace probe."
let dia7Spec = """
0/G/0/30 0.0/T/0/30 1/G/30/199 1.0/T/30/40 1.1/A/40/98 1.1.0/K/40/98 1.1.0.0/T/40/41 1.1.0.1/T/41/42
1.1.0.2/T/42/50 1.1.0.3/T/50/51 1.1.0.4/T/51/98 1.2/T/98/99 1.3/A/99/194 1.3.0/K/99/194 1.3.0.0/T/99/100
1.3.0.1/T/100/101 1.3.0.2/T/101/109 1.3.0.3/T/109/110 1.3.0.4/T/110/194 1.4/T/194/199 2/G/199/274 2.0/T/199/215
2.1/A/215/273 2.1.0/K/215/273 2.1.0.0/T/215/216 2.1.0.1/T/216/217 2.1.0.2/T/217/225 2.1.0.3/T/225/226
2.1.0.4/T/226/273 3/L/274/538 3.0/G/274/371 3.0.0/G/274/275 3.0.0.0/Tg/274/275 3.0.1/G/275/371 3.0.1.0/A/275/370
3.0.1.0.0/K/275/370 3.0.1.0.0.0/T/275/276 3.0.1.0.0.1/T/276/277 3.0.1.0.0.2/T/277/285 3.0.1.0.0.3/T/285/286
3.0.1.0.0.4/T/286/370 3.1/G/371/527 3.1.0/G/371/372 3.1.0.0/Tg/371/372 3.1.1/G/372/527 3.1.1.0/A/372/430
3.1.1.0.0/K/372/430 3.1.1.0.0.0/T/372/373 3.1.1.0.0.1/T/373/374 3.1.1.0.0.2/T/374/382 3.1.1.0.0.3/T/382/383
3.1.1.0.0.4/T/383/430 3.1.1.1/T/430/431 3.1.1.2/A/431/526 3.1.1.2.0/K/431/526 3.1.1.2.0.0/T/431/432
3.1.1.2.0.1/T/432/433 3.1.1.2.0.2/T/433/441 3.1.1.2.0.3/T/441/442 3.1.1.2.0.4/T/442/526 3.2/G/527/538
3.2.0/G/527/528 3.2.0.0/Tg/527/528 3.2.1/G/528/538 3.2.1.0/T/528/538 4/G/538/575 4.0/T/538/575
"""
let dia7Tree = fakeTree(dia7Spec)

var dia1Needs: [FieldSnapshot.Need] = []
func dia1Build(caret field: Int, side: ParagraphBreaks.Side = .start(skipping: 0), unreachable known: UnreachableLines.Memo?)
    -> (snapshot: FieldSnapshot, memo: EmptyParagraphs.Memo?, unreachable: UnreachableLines.Memo?) {
    var reads = FieldSnapshot.Reads(
        field: FieldReads(text: dia1Value, plain: field..<field, markers: MarkerReads(
            breaks: dia1Aligned, value: dia1Aligned.valueRange(field..<field) { _ in side }
        )),
        length: dia1Value.utf16.count, webContent: true, blocks: dia1Tree.count, marked: field..<field, markerText: dia1Raw
    )
    var memo: EmptyParagraphs.Memo?
    var unreachable = known
    return FieldSnapshot.Step.run(taking: { need in
        dia1Needs.append(need)
        switch need {
        case .side(let end): reads.sides.updateValue(side, forKey: end)
        case .emptyParagraph: reads.inEmptyParagraph = false
        case .emptyParagraphs(let value, let raw, _):
            memo = EmptyParagraphs.Memo(value: value, markers: raw, blocks: reads.blocks, found: scanned(dia1Tree, dia1Plain))
        case .unreachable(let value, let raw, let candidates, _):
            unreachable = UnreachableLines.Memo(value: value, markers: raw, blocks: reads.blocks,
                                                found: unreachableScanned(dia1Tree, candidates))
        }
    }) {
        FieldSnapshot.build(reads, capabilities: keyProfile, answer: .textContent, anchor: nil, cursor: nil, memo: memo,
                            unreachable: unreachable)
    }
}

func dia1Planning(_ keys: String, caret: Int, profile: CapabilityProfile = keyProfile) -> PhysicalPlan {
    let snapshot = FieldSnapshot(
        capabilities: profile, text: dia1Model.text, selection: caret..<caret, length: dia1Value.utf16.count, webContent: true,
        breaks: dia1Model.breaks, textlessLeaves: true, foldedLength: dia1Model.folded
    )
    return PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: snapshot)
}

func dia1Line(_ index: Int) -> Int { dia1Lines.prefix(index).map { $0.utf16.count + 1 }.reduce(0, +) }

// LIN-1685: the folded write lane extends to a line's end by ⇧⌃E, which a chip would stop.
let dia1D = dia1Planning("D", caret: 4, profile: writeKeys)

// Where a write at a paragraph's start takes arrows after it, a caret already there is not written again, and a collapse is ←.
func writes(_ plan: PhysicalPlan) -> Bool { plan.steps.contains { if case .setSelection = $0 { true } else { false } } }

func dia1Cursor(_ keys: String, gap: Int) -> PhysicalPlan {
    let snapshot = FieldSnapshot(
        capabilities: adding([.drawCursor], to: writeKeys), text: dia1Model.text, selection: gap..<(gap + 1),
        length: dia1Value.utf16.count, cursor: gap..<(gap + 1), webContent: true, breaks: dia1Model.breaks,
        textlessLeaves: true, foldedLength: dia1Model.folded
    )
    return PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: snapshot)
}

func dia6Planning(_ keys: String, caret: Int, profile: CapabilityProfile = keyProfile) -> PhysicalPlanner.Planning {
    let snapshot = FieldSnapshot(capabilities: profile, text: dia6Model.text, selection: caret..<caret, webContent: true,
                                 breaks: dia6Model.breaks, foldedLength: dia6Model.folded, holdsChips: true)
    return PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: snapshot)
}

// A Sim of Linear's editor moves as Vim does over the lines Linear shows, in both lanes.
let linearDoc: [(String, String?, Int, Bool)] = [
    ("Top paragraph", nil, 0, false), ("Numbered one", "1.", 0, false), ("Numbered two", "2.", 0, false),
    ("Nested numbered", "a.", 0, false), ("Numbered three", "3.", 0, false), ("Middle \u{2060} paragraph", nil, 0, false),
    ("Two \u{2060} \u{2060} end", nil, 0, false), ("\u{2060} ", "\u{2022}", 0, false),
    ("Bullet one", "\u{2022}", 0, false), ("Nested bullet", "\u{25E6}", 0, false), ("\u{2060}", "\u{2022}", 1, false),
    ("", "\u{2022}", 0, false), ("Bullet \u{2060} two", "\u{2022}", 0, false), ("\u{2060} first", "\u{2022}", 0, false),
    ("Chores", nil, 2, false), ("A to-do item", nil, 2, true), ("", nil, 2, true), ("Ends in \u{2060}", nil, 0, false),
    ("\u{2060} starts", nil, 0, false), ("\u{2060}", nil, 0, false), ("Last paragraph.", nil, 0, false),
]
func linearSim(_ profile: CapabilityProfile, findsUnreachable: Bool = true) -> Sim {
    var host = Sim(text: linearDoc.map(\.0).joined(separator: "\n"), caret: 0, profile: profile)
    host.emptyParagraphs = true
    host.listLines = linearDoc.map { Sim.ListLine(marker: $0.1, leaves: $0.2, checkbox: $0.3) }
    host.findsUnreachable = findsUnreachable
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}

func testUnreachableLines() {
    let hiddenMarker = ParagraphBreaks(offsets: [2], hidden: [.init(at: 3, text: "1.")])
    precondition(hiddenMarker.fieldOffset(2) == 2 && hiddenMarker.fieldOffset(3) == 4 && hiddenMarker.fieldOffset(5) == 6)
    precondition(hiddenMarker.valueOffsets(2) == 2...2, "a caret at the marker's start is at the line above's end")
    precondition(hiddenMarker.valueOffsets(3) == 3...3 && hiddenMarker.valueOffsets(4) == 3...3)
    precondition(hiddenMarker.fieldText("ab\ncd", at: 0..<5) == "ab1.cd" && hiddenMarker.fieldText("cd", at: 3..<5) == "cd")
    precondition(hiddenMarker.fieldText("b\n", at: 1..<3) == "b1.", "a line's AXSelectedText runs through the next marker")
    precondition(hiddenMarker.replacing(3..<4, with: "") == ParagraphBreaks(offsets: [2], hidden: [.init(at: 3, text: "1.")]))
    precondition(hiddenMarker.replacing(0..<3, with: "") == ParagraphBreaks(offsets: []))
    precondition(hiddenMarker.replacing(0..<3, with: "", keepingCovered: true) == ParagraphBreaks(hidden: [.init(at: 0, text: "1.")]))
    precondition(hiddenMarker.covers(1..<3) && !hiddenMarker.covers(3..<5))

    // "T[abc]" then "Next": the chip is one model character, and the <br> after it is the model's newline.
    let chipBreaks = ParagraphBreaks(offsets: [2], hidden: [
        .init(at: 2, text: "bc", kind: .atom), .init(at: 2, text: "\n", kind: .trailingBreak),
    ])
    precondition((0...7).map(chipBreaks.fieldOffset) == [0, 1, 5, 5, 6, 7, 8, 9])
    precondition(chipBreaks.fieldRange(1..<2) == 1..<4 && chipBreaks.fieldRange(1..<3) == 1..<5 && chipBreaks.fieldRange(2..<3) == 4..<5,
                 "a caret after the chip reads past its <br>, a selection's end stops before it")
    precondition(chipBreaks.fieldText("a", at: 1..<2) == "abc" && chipBreaks.fieldText("a\n", at: 1..<3) == "abc\n")
    precondition(chipBreaks.valueRange(5..<5) { _ in .end } == 2..<2 && chipBreaks.valueRange(5..<5) { _ in .start(skipping: 0) } == 3..<3)
    precondition(chipBreaks.valueRange(1..<4) { _ in nil } == 1..<2)
    precondition(chipBreaks.isAtom(1) && !chipBreaks.isAtom(0) && chipBreaks.atoms == [1])
    precondition(chipBreaks.withAtoms("Ta\nN", at: 0..<4) == "Tabc\nN" && chipBreaks.coversAtom(0..<2) && !chipBreaks.coversAtom(2..<4))
    precondition(chipBreaks.replacing(1..<2, with: "") == ParagraphBreaks(offsets: [1]), "deleting the chip takes its <br>")

    let dia2Value = [
        "Second probe of LIN-1652 list shapes.", "\u{2022}", "Bullet before empty", "\u{2022}", "\u{2022}",
        "Bullet after empty", "1.", "One", "2.", "3.", "Three", "", "", "To-do before empty", "", "",
        "To-do after empty", "\u{2022}", "Line one of a soft break", "\u{200B}line two of a soft break", "\u{2022}",
        "Para one of a loose item", "Para two of a loose item", "\u{2022}", "Before ",
        "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)", " after the chip", "\u{2022}", "",
        "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim",
        "1.", "Quoted paragraph", "\u{2022}", "Quoted bullet", "", "", "Heading between", "Closing paragraph."
    ].joined(separator: "\n")
    let dia2Raw = "Second probe of LIN-1652 list shapes.\u{2022}Bullet before empty\u{2022}\n\u{2022}Bullet after empt"
        + "y1.One2.\n3.Three\u{FFFC}\u{FFFC}To-do before empty\u{FFFC}\u{FFFC}\n\u{FFFC}\u{FFFC}To-do after em"
        + "pty\u{2022}Line one of a soft break\n\u{200B}line two of a soft break\u{2022}Para one of a loose it"
        + "emPara two of a loose item\u{2022}Before \u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (m"
        + "acbook14 logs) after the chip\u{2022}\u{FFFC}\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots "
        + "with one pure builder shared by the runtime and the Sim\n1.\nQuoted paragraph\u{2022}Quoted bullet\u{FFFC}"
        + "\u{FFFC}Heading betweenClosing paragraph."
    let dia2Tree = fakeTree("""
    0/G/0/37 0.0/T/0/37 1/L/37/78 1.0/G/37/57 1.0.0/G/37/38 1.0.0.0/Tg/37/38 1.0.1/G/38/57 1.0.1.0/T/38/57
    1.1/G/57/59 1.1.0/G/57/58 1.1.0.0/Tg/57/58 1.1.1/E/58/59 1.2/G/59/78 1.2.0/G/59/60 1.2.0.0/Tg/59/60 1.2.1/G/60/78
    1.2.1.0/T/60/78 2/L/78/93 2.0/G/78/83 2.0.0/G/78/80 2.0.0.0/Tg/78/79 2.0.0.1/Tg/79/80 2.0.1/G/80/83
    2.0.1.0/T/80/83 2.1/G/83/86 2.1.0/G/83/85 2.1.0.0/Tg/83/84 2.1.0.1/Tg/84/85 2.1.1/E/85/86 2.2/G/86/93
    2.2.0/G/86/88 2.2.0.0/Tg/86/87 2.2.0.1/Tg/87/88 2.2.1/G/88/93 2.2.1.0/T/88/93 3/L/93/410 3.0/G/93/111
    3.0.0/G/93/93 3.0.0.0/I/93/93 3.0.0.1/C/93/93 3.0.1/G/93/111 3.0.1.0/G/93/111 3.0.1.0.0/T/93/111 3.1/G/111/112
    3.1.0/G/111/111 3.1.0.0/I/111/111 3.1.0.1/C/111/111 3.1.1/E/111/112 3.1.1.0/E/111/112 3.2/G/112/129
    3.2.0/G/112/112 3.2.0.0/I/112/112 3.2.0.1/C/112/112 3.2.1/G/112/129 3.2.1.0/G/112/129 3.2.1.0.0/T/112/129
    3.3/G/129/180 3.3.0/G/129/130 3.3.0.0/Tg/129/130 3.3.1/G/130/180 3.3.1.0/T/130/154 3.3.1.1/T/155/156
    3.3.1.2/T/156/180 3.4/G/180/229 3.4.0/G/180/181 3.4.0.0/Tg/180/181 3.4.1/G/181/205 3.4.1.0/T/181/205
    3.4.2/G/205/229 3.4.2.0/T/205/229 3.5/G/229/310 3.5.0/G/229/230 3.5.0.0/Tg/229/230 3.5.1/G/230/310
    3.5.1.0/T/230/237 3.5.1.1/A/237/295 3.5.1.1.0/K/237/295 3.5.1.1.0.0/T/237/238 3.5.1.1.0.1/T/238/239
    3.5.1.1.0.2/T/239/247 3.5.1.1.0.3/T/247/248 3.5.1.1.0.4/T/248/295 3.5.1.2/T/295/310 3.6/G/310/407
    3.6.0/G/310/311 3.6.0.0/Tg/310/311 3.6.1/G/311/407 3.6.1.0/A/311/406 3.6.1.0.0/K/311/406 3.6.1.0.0.0/I/311/311
    3.6.1.0.0.1/T/311/312 3.6.1.0.0.2/T/312/313 3.6.1.0.0.3/T/313/321 3.6.1.0.0.4/T/321/322 3.6.1.0.0.5/T/322/406
    3.7/G/407/410 3.7.0/L/407/410 3.7.0.0/G/407/410 3.7.0.0.0/G/407/409 3.7.0.0.0.0/Tg/407/408 3.7.0.0.0.1/Tg/408/409
    3.7.0.0.1/E/409/410 4/G/410/440 4.0/G/410/426 4.0.0/T/410/426 4.1/L/426/440 4.1.0/G/426/440 4.1.0.0/G/426/427
    4.1.0.0.0/Tg/426/427 4.1.0.1/G/427/440 4.1.0.1.0/T/427/440 5/H/440/455 5.0/G/440/440 5.0.0/G/440/440
    5.0.0.0/E/440/440 5.0.0.1/P/440/440 5.1/T/440/455 6/G/455/473 6.0/T/455/473
    """)

    let dia1Candidates = UnreachableLines.candidates(text: dia1Value, breaks: dia1Aligned)
    precondition(dia1Candidates.markers.map(\.lowerBound) == [52, 66, 80, 101, 122, 179, 190, 208, 229, 311, 353, 394, 395, 407, 420])
    precondition(dia1Candidates.chips == [252..<310])
    let dia1Found = unreachableScanned(dia1Tree, dia1Candidates)!
    precondition(dia1Found.markers.map(\.lowerBound) == [52, 66, 80, 101, 122, 179, 190, 208, 229, 311, 395, 407, 420],
                 "the paragraphs that only read 1. and • are no list's")
    precondition(dia1Found.chips == [UnreachableLines.Chip(range: 252..<310, paragraph: 230..<311)])

    precondition(dia1Model.text == dia1Lines.joined(separator: "\n"), "the lines a caret reaches, as Linear shows them")
    precondition(dia1Model.folded == dia1Value.utf16.count - dia1Model.text.utf16.count)
    precondition(dia1Model.breaks.fieldText(dia1Model.text, at: 0..<dia1Model.text.utf16.count) == dia1Plain)
    precondition(roundTrips(dia1Model))

    let dia2Plain = MarkerText.plain(dia2Raw)
    precondition(scanned(dia2Tree, dia2Plain) == [58, 85, 111, 409], "each empty item's <br>, the to-do's included")
    let dia2Model = folded(dia2Value, dia2Raw, dia2Tree)
    precondition(dia2Model.text == [
        "Second probe of LIN-1652 list shapes.", "Bullet before empty", "", "Bullet after empty", "One", "", "Three",
        "To-do before empty", "", "To-do after empty", "Line one of a soft break", "\u{200B}line two of a soft break",
        "Para one of a loose item", "Para two of a loose item", "Before \u{2060} after the chip", "\u{2060}", "",
        "Quoted paragraph", "Quoted bullet", "Heading between", "Closing paragraph.",
    ].joined(separator: "\n"), "an empty item keeps its line, a chip with an icon is one character, and a quote's list folds too")
    precondition(dia2Model.breaks.fieldText(dia2Model.text, at: 0..<dia2Model.text.utf16.count) == dia2Plain)
    precondition(roundTrips(dia2Model))

    let dia6Plain = MarkerText.plain(dia6Raw)
    let dia6Candidates = UnreachableLines.candidates(text: dia6Value, breaks: ParagraphBreaks(value: dia6Value, fieldText: dia6Plain)!)
    precondition(dia6Candidates.chips.map(\.lowerBound) == [36, 127, 223, 297, 406, 486])
    let dia6Found = unreachableScanned(dia6Tree, dia6Candidates)!
    precondition(dia6Found.markers == [393..<394, 474..<475, 485..<486])
    precondition(dia6Found.chips.map(\.paragraph) == [29..<110, 110..<223, 223..<297, 297..<393, 394..<474, 486..<597])

    precondition(dia6Model.text == [
        "Chip probe opening paragraph.", "Before \u{2060} after the chip.", "Text then a chip \u{2060}", "\u{2060} chip then text.",
        "\u{2060}", "Item before \u{2060} and after", "Plain item", "\u{2060} chip first item", "Closing paragraph of the chip probe.",
    ].joined(separator: "\n"))
    precondition(dia6Model.breaks.fieldText(dia6Model.text, at: 0..<dia6Model.text.utf16.count) == dia6Plain)
    precondition(roundTrips(dia6Model))
    precondition(dia6Model.breaks.atoms == [37, 72, 74, 92, 106, 129])

    let dia7Plain = MarkerText.plain(dia7Raw)
    let dia7Candidates = UnreachableLines.candidates(text: dia7Value, breaks: ParagraphBreaks(value: dia7Value, fieldText: dia7Plain)!)
    let dia7Found = unreachableScanned(dia7Tree, dia7Candidates)!
    precondition(dia7Found.chips.map(\.range) == [40..<98, 99..<194, 215..<273, 275..<370, 372..<430, 431..<526])
    let dia7Model = folded(dia7Value, dia7Raw, dia7Tree)
    precondition(dia7Model.text == [
        "Space probe opening paragraph.", "Two chips \u{2060} \u{2060} end.", "Chip then space \u{2060}", "\u{2060}",
        "\u{2060} \u{2060}", "Plain item", "Closing paragraph of the space probe.",
    ].joined(separator: "\n"))
    precondition(dia7Model.breaks.fieldText(dia7Model.text, at: 0..<dia7Model.text.utf16.count) == dia7Plain)
    precondition(roundTrips(dia7Model))
    precondition(dia7Model.breaks.atoms == [41, 43, 66, 68, 70, 72])

    // Chromium's own lists start each item's line with its marker.
    let dia8Value = [
        "Native list probe opening paragraph.", "\u{2022} First bullet item", "\u{2022} Second bullet item",
        "\u{25E6} Nested circle item", "\u{2022} ", "\u{2022} After empty", "Middle paragraph between the lists.",
        "9. Nine", "10. Ten is longer", "i. Roman one", "ii. Roman two", "Closing paragraph.",
    ].joined(separator: "\n")
    let dia8Raw = "Native list probe opening paragraph.\u{2022} First bullet item\u{2022} Second bullet item"
        + "\u{25E6} Nested circle item\u{2022} \n\u{2022} After emptyMiddle paragraph between the lists.9. "
        + "Nine10. Ten is longeri. Roman oneii. Roman twoClosing paragraph."
    let dia8Tree = fakeTree("""
    0/G/0/36 0.0/T/0/36 1/L/36/111 1.0/G/36/55 1.0.0/M/36/38 1.0.1/T/38/55 1.1/G/55/95 1.1.0/M/55/57 1.1.1/T/57/75
    1.1.2/L/75/95 1.1.2.0/G/75/95 1.1.2.0.0/M/75/77 1.1.2.0.1/T/77/95 1.2/G/95/98 1.2.0/M/95/97 1.3/G/98/111
    1.3.0/M/98/100 1.3.1/T/100/111 2/G/111/146 2.0/T/111/146 3/L/146/170 3.0/G/146/153 3.0.0/M/146/149
    3.0.1/T/149/153 3.1/G/153/170 3.1.0/M/153/157 3.1.1/T/157/170 4/L/170/195 4.0/G/170/182 4.0.0/M/170/173
    4.0.1/T/173/182 4.1/G/182/195 4.1.0/M/182/186 4.1.1/T/186/195 5/G/195/213 5.0/T/195/213
    """)
    let dia8Plain = MarkerText.plain(dia8Raw)
    let dia8Candidates = UnreachableLines.candidates(text: dia8Value, breaks: ParagraphBreaks(value: dia8Value, fieldText: dia8Plain)!)
    precondition(dia8Candidates.markers.map(\.lowerBound) == [36, 55, 75, 95, 98, 146, 153, 170, 182])
    precondition(unreachableScanned(dia8Tree, dia8Candidates)?.markers
                 == [36..<38, 55..<57, 75..<77, 95..<97, 98..<100, 146..<149, 153..<157, 170..<173, 182..<186], "each marker and its space")
    let dia8Model = folded(dia8Value, dia8Raw, dia8Tree)
    precondition(dia8Model.text == [
        "Native list probe opening paragraph.", "First bullet item", "Second bullet item", "Nested circle item", "",
        "After empty", "Middle paragraph between the lists.", "Nine", "Ten is longer", "Roman one", "Roman two",
        "Closing paragraph.",
    ].joined(separator: "\n"))
    precondition(dia8Model.breaks.fieldText(dia8Model.text, at: 0..<dia8Model.text.utf16.count) == dia8Plain)
    precondition(roundTrips(dia8Model))
    precondition([(36, 2, 37), (55, 2, 55), (95, 2, 93), (98, 2, 94), (146, 3, 142), (153, 4, 147)].allSatisfy { field, skip, model in
        dia8Model.breaks.valueRange(field..<field) { _ in .start(skipping: skip) } == model..<model
    }, "a caret read at a marker's start and past it is at its item's start")
    precondition(dia8Model.breaks.valueRange(36..<36) { _ in .end } == 36..<36 && dia8Model.breaks.valueRange(95..<95) { _ in .end } == 92..<92)
    let dia9Value = "Third list probe top paragraph.\n\u{2022} One\n\u{2022} \nBetween.\n1. Only\n2. \n3. \n"
    let dia9Raw = "Third list probe top paragraph.\u{2022} One\u{2022} \nBetween.1. Only2. \n3. \n"
    let dia9Tree = fakeTree("""
    0/G/0/31 0.0/T/0/31 1/L/31/39 1.0/G/31/36 1.0.0/M/31/33 1.0.1/T/33/36 1.1/G/36/39 1.1.0/M/36/38 2/G/39/47 2.0/T/39/47
    3/L/47/62 3.0/G/47/54 3.0.0/M/47/50 3.0.1/T/50/54 3.1/G/54/58 3.1.0/M/54/57 3.2/G/58/62 3.2.0/M/58/61
    """)
    let dia9Model = folded(dia9Value, dia9Raw, dia9Tree)
    precondition(dia9Model.text == "Third list probe top paragraph.\nOne\n\nBetween.\nOnly\n\n", "an empty last item's <br> is no line")
    precondition(dia9Model.breaks.fieldOffset(dia9Model.text.utf16.count) == 61 && roundTrips(dia9Model))
    precondition(unreachableScanned([FakeNode("AXList", "AXContentList", 0, 7, [paragraph(0, 7)])],
                                    UnreachableLines.Candidates(markers: [0..<2], chips: []))?.markers == [])

    let noUnreachable = UnreachableLines.Found(markers: [], chips: [])
    let dia1Unfound = UnreachableLines.fold(text: dia1Value, breaks: dia1Aligned, raw: dia1Raw, found: noUnreachable)
    precondition(dia1Unfound.text.contains("\n1.\nNumbered one") && !dia1Unfound.text.contains("To-do open\n\n"),
                 "without discovery markers stay lines, and leaves still fold")
    precondition(UnreachableLines.fold(text: "ab\ncd", breaks: ParagraphBreaks(offsets: [2]), raw: "abcd", found: noUnreachable)
                 == UnreachableLines.Model(text: "ab\ncd", breaks: ParagraphBreaks(offsets: [2]), folded: 0), "nothing to fold")
    let chipLast = UnreachableLines.fold(text: "a\n\u{2022}\nChip\n", breaks: ParagraphBreaks(offsets: [1, 3]), raw: "a\u{2022}Chip\n",
                                         found: UnreachableLines.Found(markers: [1..<2], chips: [.init(range: 2..<6, paragraph: 2..<7)]))
    precondition(chipLast.text == "a\nC" && chipLast.breaks.fieldOffset(3) == 7, "a <br> ending the field leaves no line")

    let todoOne = FakeNode("AXList", "AXContentList", 0, 2, [FakeNode("AXGroup", nil, 0, 2, [
        FakeNode("AXGroup", nil, 0, 0, [FakeNode("AXCheckBox", nil, 0, 0)]), paragraph(0, 2),
    ])])
    precondition(unreachableScanned([todoOne], UnreachableLines.Candidates(markers: [0..<2], chips: []))?.markers == [],
                 "a to-do reading 1. has a checkbox where a marker would be")
    precondition(unreachableScanned(dia6Tree, UnreachableLines.Candidates(markers: [], chips: [29..<36]))?.chips == [],
                 "text is no chip")
    dia1Tree[1].children[0].fails = true
    precondition(unreachableScanned(dia1Tree, dia1Candidates) == nil, "a failed read fails the scan")
    dia1Tree[1].children[0].fails = false
    precondition(unreachableScanned(dia1Tree, dia1Candidates, budget: 60) == nil, "past its budget")
    let separated = FakeNode("AXGroup", nil, 2, 11, [FakeNode("AXGroup", "AXApplicationGroup", 2, 10, [text(2, 10)]),
                                                     FakeNode("AXGroup", "AXEmptyGroup", 10, 10)])
    precondition(scanned([paragraph(0, 1), FakeNode("AXList", "AXContentList", 1, 11, [FakeNode("AXGroup", nil, 1, 11, [
        FakeNode("AXGroup", nil, 1, 2, [text(1, 2)]), separated,
    ])])], "a\u{2022}Chip one\n") == [], "the image after a chip is no empty paragraph")

    let dia1Built = dia1Build(caret: 68, unreachable: nil)
    precondition(dia1Needs.contains(.unreachable(value: dia1Value, markers: dia1Raw, candidates: dia1Candidates, why: .first)))
    precondition(dia1Built.snapshot.text == dia1Model.text && dia1Built.snapshot.breaks == dia1Model.breaks)
    precondition(dia1Built.snapshot.selection == 66..<66 && dia1Built.snapshot.foldedLength == dia1Model.folded
                 && dia1Built.snapshot.holdsChips, "the caret past 2. is at Numbered two's start")
    dia1Needs = []
    let dia1Rebuilt = dia1Build(caret: 68, unreachable: dia1Built.unreachable)
    precondition(dia1Rebuilt.snapshot == dia1Built.snapshot && !dia1Needs.contains { if case .unreachable = $0 { true } else { false } },
                 "a memo that holds spares discovery")
    precondition(dia1Build(caret: 66, side: .end, unreachable: dia1Built.unreachable).snapshot.selection == 65..<65,
                 "a caret before a marker is at the line above's end")
    let dia1Failed = dia1Build(caret: 68, unreachable: UnreachableLines.Memo(
        value: dia1Value, markers: dia1Raw, blocks: dia1Tree.count, found: nil
    )).snapshot
    precondition(dia1Failed.text == dia1Unfound.text, "failed discovery keeps the markers' lines")

    let dia1j = dia1Planning("j", caret: 0)
    precondition(dia1j.traceShape == "P!P!C" && settleTraces(dia1j) == ["sel=52..52 len=491", "sel=54..54 len=491"],
                 "LIN-1645's j into the first item")
    let dia1k = dia1Planning("k", caret: 53)
    precondition(dia1k.traceShape == "P!PP!C" && settleTraces(dia1k) == ["sel=54..54 len=491", "sel=0..0 len=491"])
    let dia1Count = dia1Planning("3j", caret: 55)
    precondition(settleTraces(dia1Count).last == "sel=105..105 len=491", "3j counts the lines Linear shows, keeping column 2")
    let dia1dd = dia1Planning("dd", caret: 53)
    precondition(checkedTexts(dia1dd) == ["Numbered one2."], "AXSelectedText runs through the next item's marker")
    precondition(settleTraces(dia1dd).last == "soft sel=54..54 len=nil", "a list renumbers, so the length goes unchecked")
    precondition(dia1Planning("$", caret: 0, profile: removing([.lineEndKey], from: writeKeys)).steps.prefix(3)
                 == [.setSelection(51..<51), .press(.selectRight, count: 1), .press(.right, count: 1)],
                 "a write at a list marker lands by where the caret was, so the line's end is reached from inside it")
    let dia1End = dia1Planning("$", caret: 0, profile: writeKeys)
    precondition(dia1End.traceShape == "P!C" && chords(dia1End) == [.paragraphEnd], "where ⌃E lands it alone, no write goes first")
    precondition(chords(dia1Planning("A", caret: 4, profile: writeKeys)) == [.paragraphEnd])

    let heading = dia1Line(12)
    precondition(chords(dia1Planning("0", caret: heading + 3, profile: writeKeys)) == [.paragraphStart], "the heading's leaves fold there")
    precondition(chords(dia1Planning("0", caret: dia1Line(6) + 3, profile: writeKeys)).isEmpty, "a plain paragraph's start takes a write")
    precondition(dia1Planning("0", caret: dia1Line(1) + 3, profile: writeKeys).steps.first == .setSelection(54..<54),
                 "past a list marker a write lands alone")
    precondition(dia1Planning("0", caret: 4, profile: writeKeys).steps.first == .setSelection(0..<0), "a write that lands alone stays")

    precondition(dia1D.steps.first == .setSelection(4..<4) && chords(dia1D) == [Chord.paragraphEnd.shifted])
    precondition(chords(dia1Planning("D", caret: 4, profile: removing([.lineEndKey], from: writeKeys)))
                 == Array(repeating: .selectRight, count: 48))
    precondition(Set(chords(dia1Planning("D", caret: dia1Line(10) + 7, profile: writeKeys))) == [.selectRight],
                 "the mention chip ends that line")
    precondition(chords(dia1Planning("cc", caret: 4, profile: writeKeys)) == [Chord.paragraphEnd.shifted])
    precondition(chords(dia1Planning("dd", caret: 4, profile: writeKeys)) == [Chord.paragraphEnd.shifted, .selectRight])
    precondition(chords(dia1Planning("2dd", caret: 4, profile: writeKeys))
                 == [Chord.paragraphEnd.shifted, .selectRight, Chord.paragraphEnd.shifted, .selectRight])

    let headingYank = dia1Planning("yw", caret: heading, profile: writeKeys)
    precondition(!writes(headingYank) && chords(headingYank) == Array(repeating: .selectRight, count: 8) + [.left])
    let middle = dia1Line(6)
    let middleYank = dia1Planning("yw", caret: middle, profile: writeKeys)
    precondition(writes(middleYank) && chords(middleYank).isEmpty, "a plain paragraph's start takes writes alone")

    let cursorX = dia1Cursor("x", gap: heading)
    precondition(!writes(cursorX) && cursorX.steps.prefix(2) == [.press(.left, count: 1), .press(.selectRight, count: 1)],
                 "the drawn cursor collapses by ←")
    precondition(writes(dia1Cursor("x", gap: heading + 2)), "inside a paragraph the write stays")
    precondition(chords(dia1Cursor("x", gap: middle)).isEmpty, "at a plain paragraph's start too, and the cursor is drawn by a write")
    let cursorJ = dia1Cursor("j", gap: heading)
    precondition(cursorJ.steps.first == .press(.left, count: 1) && writes(cursorJ))
    if case .settle = cursorJ.steps[1] {} else { preconditionFailure("a write after the ← waits for it to settle") }
    precondition(chords(dia1Cursor("$", gap: middle + 2)) == [.paragraphEnd]
                 && chords(dia1Cursor("0", gap: heading + 2)) == [.paragraphStart, .selectRight],
                 "⌃A and ⌃E land alike from the cursor, which needs no collapse first; ⇧→ draws it again at the start")
    precondition(chords(dia1Cursor("0", gap: middle + 2)).isEmpty, "a plain paragraph's start is written, cursor and all")
    for history in ["u", "<C-r>"] {
        var nothingToUndo = Sim(text: "alpha\nbeta", caret: 0, profile: adding([.drawCursor], to: writeKeys))
        nothingToUndo.emptyParagraphs = true
        nothingToUndo.listLines = [Sim.ListLine(marker: "\u{2022}"), Sim.ListLine()]
        nothingToUndo.emulatesKeys = true
        nothingToUndo.readModel = .textContent
        nothingToUndo.ignoredChords = [.undo, .redo]
        nothingToUndo.type("l")
        nothingToUndo.feed(history)
        nothingToUndo.type("iQ")
        precondition(nothingToUndo.text == "aQlpha\nbeta", "an undo with nothing to undo leaves no drawn cursor to type over")
    }

    let chipA = "\u{2060}\u{00A0}LIN-1645 Why j/k always beeps in Linear (macbook14 logs)"
    let chipB = "\u{2060}\u{00A0}LIN-1641 Build mvim's field snapshots with one pure builder shared by the runtime and the Sim"
    precondition(dia6Planning("0", caret: 80, profile: removing([.lineStartKey], from: writeKeys)).plan.steps.prefix(2)
                 == [.setSelection(281..<281), .press(.left, count: 1)],
                 "a caret written at a chip's start stops the next arrow, so a chip's start is reached from its end")
    precondition(chords(dia6Planning("0", caret: 80, profile: writeKeys).plan) == [.paragraphStart], "⌃A crosses the chip")
    precondition(dia6Planning("$", caret: 60, profile: writeKeys).plan.steps.first == .setSelection(222..<222),
                 "after a chip that ends its paragraph, the write goes before the <br>")
    let dia6j = dia6Planning("j", caret: 30, profile: writeKeys).plan
    precondition(dia6j.steps.first == .setSelection(110..<110) && chords(dia6j).isEmpty,
                 "a plain paragraph's start sharing an offset with the line above's end takes the write, which lands downstream")
    precondition(checkedTexts(dia6Planning("x", caret: 37).plan) == [chipA], "x takes the chip whole")
    precondition(dia6Planning("yy", caret: 60).plan.steps.contains(
        .commit(.yanked(into: nil, content: .literal("Text then a chip " + chipB + "\n"), wise: .line))
    ), "a register keeps a chip's label")
    precondition(dia6Planning("rx", caret: 37).rejection != nil && dia6Planning("~", caret: 37).rejection != nil,
                 "typed text cannot rebuild a chip")
    precondition(dia6Planning("~", caret: 36).rejection == nil)

    var chipKeys = KeyModel(text: "ab\u{2060}cd", anchor: 0, focus: 0, atoms: [2])
    precondition(chipKeys.press(Chord.paragraphEnd.shifted) && chipKeys.selection == 0..<2, "⇧⌃E stops at a chip")
    precondition(chipKeys.press(Chord.paragraphEnd.shifted) && chipKeys.selection == 0..<2)
    chipKeys = KeyModel(text: "ab\u{2060}cd", anchor: 5, focus: 5, atoms: [2])
    precondition(chipKeys.press(Chord.paragraphStart.shifted) && chipKeys.selection == 3..<5, "⇧⌃A stops after one")
    precondition(chipKeys.press(.paragraphStart) && chipKeys.selection == 0..<0, "⌃A crosses it")

    for profile in [keyProfile, writeKeys] {
        let down = String(repeating: "j", count: linearDoc.count)
        for keys in [down + String(repeating: "k", count: linearDoc.count), "3j2k4j5j3k", "5ljjjjjjjjjjjjjjjjkkkk",
                     "$jjjjjjjjjjjjjjjjkkkk", "G" + String(repeating: "k", count: linearDoc.count - 1), "jjjjjjjjjjjjjjjjj0jj^",
                     "jjjjjwwwwwwwwwwwbbbbbbb",
                     "jjjjjjjjjjjjjjjjdd", "jjjjjlx"] {
            var linear = linearSim(profile)
            // A chip is drawn, so plain text stands a visible character in for it.
            var plain = Sim(text: String(linear.text.map { $0 == "\u{2060}" ? "@" : $0 }), caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                linear.type(String(key))
                plain.type(String(key))
                precondition(linear.caret == plain.caret && linear.text == String(plain.text.map { $0 == "@" ? "\u{2060}" : $0 }),
                             "\(keys) at \(key)")
            }
            precondition(linear.settleFailures == 0 && linear.bells == 0, keys)
        }
    }
    var chipStart = linearSim(writeKeys)
    let firstChip = chipStart.chromium.chips[0].range.lowerBound
    chipStart.perform([.setSelection(firstChip..<firstChip), .press(.right, count: 1)])
    precondition(chipStart.readSelection == firstChip..<firstChip, "the Sim's caret written at a chip's start stops the next arrow")

    let nativeDoc: [(String, String?)] = [
        ("Top paragraph", nil), ("First bullet", "\u{2022} "), ("Second bullet", "\u{2022} "), ("Nested one", "\u{25E6} "),
        ("", "\u{2022} "), ("After empty", "\u{2022} "), ("Middle paragraph", nil), ("Nine", "9. "), ("Ten longer", "10. "),
        ("Last paragraph.", nil),
    ]
    for profile in [keyProfile, writeKeys] {
        let down = String(repeating: "j", count: nativeDoc.count)
        for keys in [down + String(repeating: "k", count: nativeDoc.count), "3j2k4j3j3k", "5ljjjjjjjjkkkk", "$jjjjjjjjkkkkk",
                     "G" + String(repeating: "k", count: nativeDoc.count - 1), "jjjjjjj0jj^k0", "jwwwwwwwwwbbbbbbb", "jjjdd", "jjjjdd",
                     "jjjjjdd", "jjjjjjjdd", "jlx"] {
            var native = Sim(text: nativeDoc.map(\.0).joined(separator: "\n"), caret: 0, profile: profile)
            native.emptyParagraphs = true
            native.listLines = nativeDoc.map { Sim.ListLine(marker: $0.1, inline: true) }
            native.emulatesKeys = true
            native.readModel = .textContent
            var plain = Sim(text: native.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                native.type(String(key))
                plain.type(String(key))
                precondition(native.caret == plain.caret && native.text == plain.text, "\(keys) at \(key)")
            }
            precondition(native.settleFailures == 0 && native.bells == 0, keys)
        }
    }

    // Quill's `li::before`, Slack's message box: no space after the marker, and a caret at the start reads before it (LIN-2329).
    let quillDocs: [[(String, String?)]] = [
        [("Top paragraph", nil), ("one", "\u{2022}"), ("two longer", "\u{2022}"), ("Middle paragraph", nil), ("first", "1."),
         ("second item", "2."), ("nested", "a."), ("Last paragraph.", nil)],
        [("one", "\u{2022}"), ("", "\u{2022}"), ("three", "\u{2022}"), ("four", "1."), ("", "2."), ("six", "a.")],
        [("", "\u{2022}"), (" one", "\u{2022}"), ("", "\u{2022}"), ("three", "1."), (" four", "2.")],
        [("", "\u{2022}"), ("", "\u{2022}")],
        [("one", "\u{25B8}"), ("two", "a)"), ("", "\u{25B8}"), ("Last", nil)],
    ]
    for (doc, profile) in quillDocs.flatMap({ doc in [keyProfile, writeKeys].map { (doc, $0) } }) {
        for keys in ["jjjjjjjkkkkkkk", "3j2k4j3j3k", "5ljjjjjjkkkk", "$jjjjjjjkkkkk", "jjjjdd", "jjjjjdd", "jlx", "jjj0x", "jdd",
                     "jjdd", "Gkkkkkkk", "ggjdk"] {
            var quill = Sim(text: doc.map(\.0).joined(separator: "\n"), caret: 0, profile: profile)
            quill.emptyParagraphs = true
            quill.quill = true
            quill.listLines = doc.map { Sim.ListLine(marker: $0.1, inline: true) }
            quill.emulatesKeys = true
            quill.readModel = .textContent
            var plain = Sim(text: quill.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                quill.type(String(key))
                plain.type(String(key))
                precondition(quill.caret == plain.caret && quill.text == plain.text, "Quill \(keys) at \(key)")
            }
            precondition(quill.settleFailures == 0 && quill.bells == 0, "Quill \(keys) \(doc.map(\.0)) \(quill.settleFailures) \(quill.bells)")
        }
    }
    precondition(UnreachableLines.markerShape(Array("\u{2022}one".utf16)) == 1 && UnreachableLines.markerShape(Array("10.ten".utf16)) == 3
                 && UnreachableLines.markerShape(Array("\u{25B8} one".utf16)) == 1 && UnreachableLines.markerShape(Array("a)two".utf16)) == 2)
    precondition(UnreachableLines.markerShape(Array("+1".utf16)) == 1 && UnreachableLines.markerShape(Array("\u{1F600}x".utf16)) == 2
                 && UnreachableLines.markerShape(Array("\u{00B7}x".utf16)) == 1, "a plus, an emoji, a middle dot")
    precondition(["one", "(a)", "#1", "\"q\"", "\u{201C}q", "\u{300C}q", "\u{4E00}\u{3001}"].allSatisfy {
        UnreachableLines.markerShape(Array($0.utf16)) == nil
    }, "text, ASCII's other punctuation, opening quotes and a CJK numeral are no shape")

    // `•one⏎•⏎•three` as Chromium 153 shows Quill 1.3.7's list: an empty item holds its `::before` group alone.
    let quillTree = fakeTree("0/L/0/12 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/T/1/4 0.1/G/4/6 0.1.0/G/4/5 0.1.0.0/Tg/4/5 0.2/G/6/12 0.2.0/G/6/7 0.2.0.0/Tg/6/7 0.2.1/T/7/12", linear: false)
    let quillBreaks = ParagraphBreaks(offsets: [4])
    let quillCandidates = UnreachableLines.candidates(text: "\u{2022}one\n\u{2022}\n\u{2022}three", breaks: quillBreaks)
    precondition(unreachableScanned(quillTree, quillCandidates)?.markers == [0..<1, 4..<5, 6..<7], "the empty item's marker too")
    let typedTree = fakeTree("0/L/0/12 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/T/0/1 0.0.1/T/1/4 0.1/G/4/6 0.1.0/G/4/5 0.1.0.0/T/4/5 0.2/G/6/12 0.2.0/G/6/7 0.2.0.0/T/6/7 0.2.1/T/7/12", linear: false)
    precondition(unreachableScanned(typedTree, quillCandidates)?.markers == [], "the same text the page does not generate is none")
    let spacedTree = fakeTree("0/L/0/9 0.0/G/0/5 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/T/1/5 0.1/G/5/9 0.1.0/G/5/6 0.1.0.0/Tg/5/6 0.1.1/T/6/9", linear: false)
    let spacedBreaks = ParagraphBreaks(offsets: [5])
    let spacedFound = unreachableScanned(spacedTree, UnreachableLines.candidates(text: "\u{2022} one\n\u{2022}two", breaks: spacedBreaks))
    precondition(spacedFound?.markers == [0..<1, 5..<6], "an item whose text starts with a space keeps its marker")
    precondition(UnreachableLines.fold(text: "\u{2022} one\n\u{2022}two", breaks: spacedBreaks, raw: "\u{2022} one\u{2022}two",
                                       found: spacedFound!).text == " one\ntwo")

    var linearLogged = linearSim(keyProfile, findsUnreachable: false)
    linearLogged.type("j")
    precondition(linearLogged.settleFailures == 1 && linearLogged.caret == 14, "without discovery, LIN-1645's j into an item")
    linearLogged.type("k")
    precondition(linearLogged.settleFailures == 2, "and its k out of one")
}
