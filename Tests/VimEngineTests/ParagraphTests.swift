// MARK: - Paragraph breaks (Chromium rich text)

let paras = ParagraphBreaks(value: "ab\ncd\nef", fieldText: "abcdef")!

// LIN-1643: a stranded selection's start resolves through its side, and ← collapses it where a write would need keys.
func strandedPlan(
    _ selection: Range<Int>, _ side: ParagraphBreaks.Side?, text: String = "ab\ncd\nef", breaks: ParagraphBreaks = paras,
    profile: CapabilityProfile
) -> PhysicalPlan {
    PhysicalPlanner.collapse(
        selection, side: side, paragraphs: true, snapshot: FieldSnapshot(capabilities: profile, text: text, breaks: breaks),
        profile: profile
    )
}

// "ab\ncd ef\ngh" reads to the field as "abcd efgh".
let threeParagraphs = "ab\ncd ef\ngh"

func leafyPlanning(_ keys: String, caret: Int) -> PhysicalPlanner.Planning {
    let snapshot = FieldSnapshot(capabilities: readProfile, text: threeParagraphs, selection: caret..<caret,
                                 breaks: ParagraphBreaks(offsets: [2, 8]), textlessLeaves: true)
    return PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: snapshot)
}

func testParagraphBreaks() {
    precondition(paras.offsets == [2, 5])
    precondition(paras.fieldOffset(2) == 2 && paras.fieldOffset(3) == 2 && paras.fieldOffset(7) == 5)
    precondition(paras.fieldRange(1..<7) == 1..<5)
    precondition(paras.valueOffsets(2) == 2...3, "a paragraph's end and the next one's start")
    precondition(paras.valueOffsets(1) == 1...1)
    precondition(paras.valueOffsets(3) == 4...4)
    precondition(paras.valueOffsets(4) == 5...6)
    precondition(ParagraphBreaks(value: "a\nb", fieldText: "a\nb")!.offsets == [], "<br> lines are in both")
    precondition(ParagraphBreaks(value: "• ab\n• cd", fieldText: "• ab• cd")!.offsets == [4], "so are list markers")
    precondition(ParagraphBreaks(value: "ab\n\ncd", fieldText: "ab\ncd")!.offsets == [2], "the break leads the text's own newline")
    precondition(ParagraphBreaks(value: "", fieldText: "")!.offsets == [])
    precondition(ParagraphBreaks(value: "ab\ncd", fieldText: "abxcd") == nil)
    precondition(ParagraphBreaks(value: "ab", fieldText: "ab ") == nil)
    precondition(ParagraphBreaks(value: "a\nb", fieldText: "a\n\nb") == nil)

    precondition(paras.valueRange(2..<2) { _ in .start(skipping: 0) } == 3..<3)
    precondition(paras.valueRange(2..<2) { _ in .end } == 2..<2)
    precondition(paras.valueRange(2..<2) { _ in nil } == nil, "a boundary nothing resolves is unknown")
    precondition(paras.valueRange(1..<3) { _ in preconditionFailure("unambiguous") } == 1..<4)
    precondition(paras.valueRange(2..<2) { $0 == .upper ? .start(skipping: 0) : .end } == 2..<3, "the break alone")
    precondition(paras.valueRange(2..<2) { $0 == .lower ? .start(skipping: 0) : .end } == 2..<3, "the break alone, selected backward")
    let listItems = ParagraphBreaks(value: "• ab\n• cd", fieldText: "• ab• cd")!
    precondition(listItems.valueRange(4..<4) { _ in .start(skipping: 2) } == 7..<7, "a caret between items sits past the next marker")
    precondition(listItems.valueRange(0..<0) { _ in .start(skipping: 2) } == 2..<2, "and so does one before the first item")
    precondition(listItems.valueRange(0..<0) { _ in nil } == nil, "a field's start nothing resolves is unknown too")
    precondition(listItems.valueRange(0..<4) { $0 == .lower ? .start(skipping: 2) : .end } == 2..<4)

    let collapsedToEnd = PhysicalPlan(
        .press(.left, count: 1), .press(.selectLeft, count: 1), .press(.right, count: 1),
        .settle(Expectation(selection: 2..<2, edge: .paragraphEnd))
    )
    for profile in [axProfile, readProfile] {
        precondition(strandedPlan(2..<4, .end, profile: profile) == collapsedToEnd,
                     "a write there lands on the next paragraph, so ← collapses the selection in a write lane too")
    }
    precondition(strandedPlan(2..<4, .start(skipping: 0), profile: axProfile) == PhysicalPlan(.setSelection(2..<2)))
    precondition(strandedPlan(2..<2, .end, profile: axProfile) == collapsedToEnd, "a selected break alone starts at the end too")
    precondition(strandedPlan(1..<4, .end, profile: axProfile) == PhysicalPlan(.setSelection(1..<1)), "off a boundary the side says nothing")
    let drawnAhead = FieldSnapshot(capabilities: axProfile, text: "ab\ncd\nef", breaks: paras, drawnBreak: 4)
    for (profile, asRead) in [
        (axProfile, PhysicalPlan(.setSelection(2..<2))),
        (readProfile, PhysicalPlan(
            .press(.left, count: 1), .press(.selectLeft, count: 1), .press(.right, count: 1), .settle(Expectation(selection: 2..<2))
        )),
    ] {
        for unplaced in [
            strandedPlan(2..<4, nil, profile: profile),
            PhysicalPlanner.collapse(2..<4, side: .end, paragraphs: true, profile: profile),
            strandedPlan(2..<4, .end, text: "a", profile: profile),
            PhysicalPlanner.collapse(2..<4, side: .end, paragraphs: true, snapshot: drawnAhead, profile: profile),
        ] {
            precondition(unplaced == asRead,
                         "a side says nothing without breaks that place it: a code span's end inside a paragraph is an end too")
        }
    }
    precondition(strandedPlan(2..<4, .start(skipping: 0), profile: readProfile) == PhysicalPlan(
        .press(.left, count: 1), .settle(Expectation(selection: 2..<2, edge: .paragraphStart))
    ), "no ⇧← → crosses the break above a paragraph's start")
    precondition(strandedPlan(4..<6, .start(skipping: 2), text: "• ab\n• cd", breaks: listItems, profile: axProfile)
                 == PhysicalPlan(.setSelection(6..<6)), "a list item's start is written past its marker")
    precondition(strandedPlan(0..<2, .start(skipping: 2), text: "• ab\n• cd", breaks: listItems, profile: axProfile)
                 == PhysicalPlan(.setSelection(2..<2)))
    precondition(strandedPlan(4..<6, .end, text: "• ab\n• cd", breaks: listItems, profile: axProfile) == PhysicalPlan(
        .press(.left, count: 1), .press(.selectLeft, count: 1), .press(.right, count: 1),
        .settle(Expectation(selection: 4..<4, edge: .paragraphEnd))
    ))

    // LIN-1931: a command typed behind a failed one can read the selection that one left while its collapse write is on the way.
    for profile in [axProfile, removing([.insertText], from: axProfile)] {
        for (keys, selection) in [("dd", 0..<4), ("dd", 4..<8), ("x", 4..<5), ("diw", 4..<7)] {
            precondition(physical(keys, text: "one\ntwo\nthree", selection: selection, profile: profile)
                         == physical(keys, text: "one\ntwo\nthree", caret: selection.lowerBound, profile: profile),
                         "\(keys) makes its selection again, as from a caret at its start")
        }
    }
    precondition(checkedText(physical("x", text: "one two", selection: 4..<5, profile: readProfile).steps.first) == "t",
                 "a lane that cannot write takes the selection as it reads, as before")
    for anchor in [4, nil] {
        var visualWords = VimState.initial
        visualWords.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: anchor))
        precondition(PhysicalPlanner.planning(
            LogicalPlanner.plan(RawCommand("iw"), state: visualWords),
            snapshot: FieldSnapshot(capabilities: axProfile, text: "one two three", selection: 4..<7, anchor: anchor), visual: true
        ).plan.steps.isEmpty, "Visual's own selection is the word already, with or without the anchor a block crossing drops")
    }

    precondition(paras.replacing(1..<4, with: "") == ParagraphBreaks(offsets: [2]))
    precondition(paras.replacing(0..<0, with: "x\n") == ParagraphBreaks(offsets: [1, 4, 7]))
    precondition(paras.replacing(5..<6, with: " ") == ParagraphBreaks(offsets: [2]), "J joins the paragraphs")

    precondition(MarkerText.plain("See \u{FFFC}LIN-1234") == "See LIN-1234")
    precondition(MarkerText.plainLength("\u{FFFC}\u{FFFC}Problem") == 7)
    precondition(MarkerText.plainLength("a😀\u{FFFC}") == 3, "UTF-16 units, as the offsets are")
    precondition(MarkerText.plain("") == "" && MarkerText.plainLength("") == 0)

    let leafShapes: [(name: String, value: String, markers: String, caret: Int, valueCaret: Int)] = [
        ("icon chip",
         "Heading one\nFirst paragraph with some words.\nSee \n\nLIN-1234\n here\n• item alpha\n• item beta\nHeading two\nLast paragraph here.",
         "Heading oneFirst paragraph with some words.See \u{FFFC}LIN-1234 here• item alpha• item betaHeading twoLast paragraph here.",
         95, 104),
        ("hr",
         "Heading one\nFirst paragraph with some words.\n\n• item alpha\n• item beta\nHeading two\nLast paragraph here.",
         "Heading oneFirst paragraph with some words.\u{FFFC}• item alpha• item betaHeading twoLast paragraph here.",
         78, 84),
        ("checkbox",
         "Heading one\nFirst paragraph with some words.\n• \ntask one\n• item alpha\n• item beta\nHeading two\nLast paragraph here.",
         "Heading oneFirst paragraph with some words.• \u{FFFC}task one• item alpha• item betaHeading twoLast paragraph here.",
         88, 95),
    ]
    for shape in leafShapes {
        precondition(ParagraphBreaks(value: shape.value, fieldText: shape.markers) == nil, "\(shape.name): U+FFFC is no break")
        let breaks = ParagraphBreaks(value: shape.value, fieldText: MarkerText.plain(shape.markers))!
        precondition(breaks.valueRange(shape.caret..<shape.caret) { _ in preconditionFailure("unambiguous") }
            == shape.valueCaret..<shape.valueCaret, shape.name)
    }
    let linearHeading = ParagraphBreaks(value: "\n\nProblem\nWhen", fieldText: MarkerText.plain("\u{FFFC}\u{FFFC}ProblemWhen"))!
    precondition(linearHeading.offsets == [0, 1, 9], "the heading widget's two lines are breaks")
    precondition(linearHeading.valueRange(0..<0) { _ in .start(skipping: 0) } == 2..<2, "a caret on the heading sits past them")

    precondition(Expectation(selection: 5..<7, length: 11, edge: .paragraphEnd).traceFields == "sel=5..7 len=11 edge=end")

    precondition(paragraphPlanning("j", text: threeParagraphs, caret: 1, profile: noCursorProfile).plan.steps == [
        .setSelection(3..<3),
        .settle(Expectation(selection: 3..<3, length: 11)),
        .commit(.setCursor(nil)),
    ])
    precondition(paragraphPlanning("j", text: threeParagraphs, caret: 0, profile: noCursorProfile).plan.steps == [
        .setSelection(2..<2),
        .settle(Expectation(selection: 2..<2, length: 11, edge: .paragraphStart)),
        .commit(.setCursor(nil)),
    ])
    precondition(paragraphPlanning("l", text: threeParagraphs, caret: 9, profile: readProfile).plan.steps == [
        .press(.selectRight, count: 1),
        .press(.right, count: 1),
        .settle(Expectation(selection: 8..<8, length: 11)),
        .commit(.setCursor(nil)),
    ])

    let lastWordA = paragraphPlanning("ciw", text: threeParagraphs, caret: 7, profile: noCursorProfile)
    precondition(lastWordA.plan.steps == [
        .setSelection(5..<7),
        .press(.selectLeft, count: 1),
        .settle(checkingWrite(Expectation(selection: 5..<7, length: 11, edge: .paragraphEnd))),
        .settle(Expectation(selection: 5..<7, length: 11, edge: .paragraphEnd, selectedText: "ef")),
        .replaceSelection(""),
        .settle(Expectation(selection: 5..<5, length: 9, edge: .paragraphEnd)),
        .commit(.deleted(into: nil, content: .literal("ef"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(6)),
    ])
    precondition(lastWordA.operand == 5..<7, "the operand is compared with the field's own read")
    precondition(paragraphPlanning("ciw", text: threeParagraphs, caret: 7, profile: readProfile).plan.steps == [
        .press(.selectLeft, count: 1),
        .press(.left, count: 1),
        .press(.selectLeft, count: 1),
        .press(.right, count: 1),
        .press(.selectRight, count: 2),
        .settle(Expectation(selection: 5..<7, length: 11, edge: .paragraphEnd)),
        .settle(Expectation(selection: 5..<7, length: 11, edge: .paragraphEnd, selectedText: "ef")),
        .press(.deleteBack, count: 1),
        .softSettle(deleting(Expectation(selection: 5..<5, length: 9, edge: .paragraphEnd), 5..<7, before: 11)),
        .commit(.deleted(into: nil, content: .literal("ef"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(6)),
    ])
    precondition(paragraphPlanning("A", text: threeParagraphs, caret: 0, profile: noCursorProfile).plan.steps == [
        .setSelection(2..<2),
        .press(.selectLeft, count: 1),
        .press(.left, count: 1),
        .settle(checkingWrite(Expectation(selection: 2..<2, length: 11, edge: .paragraphEnd))),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(2)),
    ])
    let fromParagraphEnd = LogicalPlan(.select(.span(to: .offset(5), inclusive: false)), .deleteSelection(into: nil))
    precondition(PhysicalPlanner.planning(fromParagraphEnd, snapshot: FieldSnapshot(
        capabilities: noCursorProfile, text: threeParagraphs, selection: 2..<2, breaks: ParagraphBreaks(offsets: [2, 8])
    )).plan.steps == [
        .setSelection(2..<2),
        .press(.left, count: 1),
        .press(.selectRight, count: 3),
        .settle(checkingWrite(Expectation(selection: 2..<4, length: 11))),
        .settle(Expectation(selection: 2..<4, length: 11, selectedText: "cd")),
        .replaceSelection(""),
        .settle(Expectation(selection: 2..<2, length: 8)),
        .commit(.deleted(into: nil, content: .literal("\ncd"), wise: .character)),
    ])
    precondition(checkedTexts(paragraphPlanning("dd", text: threeParagraphs, caret: 4, profile: readProfile).plan) == ["cd ef"])
    let pastPhantom = Expectation(selection: 0..<2, length: 6, edge: .paragraphStart, selectedText: "ab")
    precondition(paragraphPlanning("dd", text: "ab\n\ncd", caret: 0, profile: readProfile).plan.steps.contains(.settle(pastPhantom)),
                 "keys that stop before the break read the paragraph's end and fail it")

    precondition(leafyPlanning("J", caret: 4).rejection != nil, "typing over a break could drop an <hr> or a table cell")
    precondition(leafyPlanning("gUj", caret: 4).rejection != nil, "and so could retyping two lines")
    precondition(leafyPlanning("gUiw", caret: 4).rejection == nil, "one line's text is safe to retype")
    precondition(leafyPlanning("dd", caret: 4).rejection == nil, "a delete retypes nothing")
    precondition(paragraphPlanning("J", text: threeParagraphs, caret: 4, profile: readProfile).rejection == nil)
    precondition(paragraphPlanning("gUj", text: threeParagraphs, caret: 4, profile: readProfile).rejection == nil)
    precondition(ParagraphBreaks(offsets: [2, 8]).fieldText("cd ef\n", at: 3..<9) == "cd ef")
    precondition(ParagraphBreaks(offsets: [2, 8]).fieldText("b\ncd", at: 1..<5) == "bcd")
    precondition(paragraphPlanning("o", text: threeParagraphs, caret: 0, profile: noCursorProfile).plan.steps.contains(
        .settle(Expectation(selection: nil, length: 12))
    ))
}

// MARK: - Paragraph edges

let chromiumModes: [(name: String, apply: (inout Sim) -> Void)] = [
    ("reads", { $0.reads = omitsBreaks }),
    ("markers", { $0.reads = omitsBreaks; $0.markers = true }),
    ("emptyParagraphs", { $0.emptyParagraphs = true }),
]

func testParagraphEdges() {
    for mode in chromiumModes {
        for (edge, settles) in [(Expectation.Edge.paragraphStart, true), (.paragraphEnd, false)] {
            var host = Sim(text: "ab\ncd", caret: 3, profile: readProfile)
            mode.apply(&host)
            precondition(host.perform([.settle(Expectation(selection: 2..<2, edge: edge))]) == settles, "\(mode.name) \(edge)")
        }
    }

    var appended = Sim(text: "ab\ncd", caret: 1, profile: axProfile)
    appended.reads = omitsBreaks
    appended.markers = true
    appended.writesInReadOffsets = true
    appended.readModel = .textContent
    var misplaced = appended
    misplaced.ignoredChords = [.left, .selectLeft]
    appended.type("A")
    precondition(appended.caret == 2 && appended.settleFailures == 0 && appended.state.field.mode == .insert)
    misplaced.type("A")
    precondition(misplaced.caret == 3 && misplaced.settleFailures == 1, "the next paragraph's start reads the same offset")
    var strandedMarkers = Sim(text: "ab cd\nef gh", caret: 5, profile: axProfile)
    strandedMarkers.reads = omitsBreaks
    strandedMarkers.markers = true
    strandedMarkers.writesInReadOffsets = true
    strandedMarkers.emulatesKeys = true
    strandedMarkers.readModel = .textContent
    strandedMarkers.reboundChords = [.selectRight: .selectWordRight]
    strandedMarkers.type("cw")
    strandedMarkers.reboundChords = [:]
    strandedMarkers.type("X")
    precondition(strandedMarkers.text == "ab cdX\nef gh",
                 "LIN-1643: a repair reads its start's side from the markers, and collapses onto that paragraph's end")
}
