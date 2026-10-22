// MARK: - Empty paragraphs (LIN-1612)

// Chrome 153's own strings (softlash/LIN-1612 scripts/empty-shapes): a blank line under the first paragraph.
let blankParagraphs = ["Heading one", "First paragraph with some words.", "", "Second paragraph.", "\u{2022} item alpha",
                       "\u{2022} item beta", "Last paragraph here."]
let blankValue = "Heading one\nFirst paragraph with some words.\nSecond paragraph.\n\u{2022} item alpha\n\u{2022} item beta\n"
    + "Last paragraph here."
let blankMarkers = "Heading oneFirst paragraph with some words.\nSecond paragraph.\u{2022} item alpha\u{2022} item beta"
    + "Last paragraph here."
let blankAligned = ParagraphBreaks(value: blankValue, fieldText: blankMarkers)!

var blankNeeds: [FieldSnapshot.Need] = []
func blankBuild(
    memo known: EmptyParagraphs.Memo?, unreachable knownUnreachable: UnreachableLines.Memo? = nil
) -> (snapshot: FieldSnapshot, memo: EmptyParagraphs.Memo?, unreachable: UnreachableLines.Memo?) {
    var reads = FieldSnapshot.Reads(
        field: FieldReads(text: blankValue, plain: 43..<43, markers: MarkerReads(
            breaks: blankAligned, value: blankAligned.valueRange(43..<43) { _ in .start(skipping: 0) }
        )),
        length: blankValue.utf16.count, webContent: true, blocks: blankParagraphs.count, marked: 43..<43, markerText: blankMarkers
    )
    var memo = known
    var unreachable = knownUnreachable
    return FieldSnapshot.Step.run(taking: { need in
        blankNeeds.append(need)
        switch need {
        case .side(let end): reads.sides.updateValue(.start(skipping: 0), forKey: end)
        case .emptyParagraph: reads.inEmptyParagraph = true
        case .emptyParagraphs(let value, let markers, _):
            memo = EmptyParagraphs.Memo(value: value, markers: markers, blocks: reads.blocks, found: [43])
        case .unreachable(let value, let markers, _, _):
            unreachable = UnreachableLines.Memo(value: value, markers: markers, blocks: reads.blocks, found: nil)
        }
    }) {
        FieldSnapshot.build(reads, capabilities: readProfile, answer: .textContent, anchor: nil, cursor: nil, memo: memo,
                            unreachable: unreachable)
    }
}

// macbook14's e78: L is field 203..<210, the blank line's <br> is at 210.
let e78Paragraphs = [String(repeating: "a", count: 121), String(repeating: "b", count: 82), "ccccccc", "", "ddddd"]
let e78Shown = EmptyParagraphs.chromium(e78Paragraphs)

let e78Aligned = ParagraphBreaks(value: e78Shown.value, fieldText: e78Shown.markers)!
let e78Model = EmptyParagraphs.restore(value: e78Shown.value, fieldText: e78Shown.markers, aligned: e78Aligned, found: [210])!

func e78Planning(_ keys: String, caret: Int) -> PhysicalPlanner.Planning {
    PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: FieldSnapshot(
        capabilities: keyProfile, text: e78Model.text, selection: caret..<caret, webContent: true, breaks: e78Model.breaks,
        valueGap: e78Model.gap, holdsEmptyParagraphs: true
    ))
}

// Lane A: writes land on the blank line too.
let writeKeys = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .insertText, .wholeDocument,
    .lineStartKey, .lineEndKey, .documentStartKey, .documentEndKey,
])

// LIN-1643: `cw` whose ⇧→ selects a word fails its check with the selection stranded, and `c` keeps Insert where it collapses.
func strandedChange(
    _ paragraphs: [String], caret: Int, profile: CapabilityProfile, lines: [Sim.ListLine]? = nil, code: [Range<Int>] = [],
    rebound: [Chord: Chord] = [:], ignored: Set<Chord> = []
) -> Sim {
    var host = blankSim(paragraphs, caret: caret, profile: profile)
    host.listLines = lines
    host.codeSpans = code
    host.reboundChords = [.selectRight: .selectWordRight, Chord.paragraphEnd.shifted: .selectWordRight].merging(rebound) { $1 }
    host.ignoredChords = ignored
    host.type("cw")
    host.reboundChords = [:]
    host.type("X")
    return host
}

func testEmptyParagraphs() {
    precondition(blankAligned.offsets == [11, 62, 75, 87], "the blank line's <br> pairs with AXValue's separator")
    let blankModel = EmptyParagraphs.restore(value: blankValue, fieldText: blankMarkers, aligned: blankAligned, found: [43])!
    precondition(blankModel.text == blankParagraphs.joined(separator: "\n"))
    precondition(blankModel.gap == 1)
    precondition(blankModel.breaks.valueRange(43..<43) { _ in .start(skipping: 0) } == 45..<45, "a caret in it reads as its own line")
    precondition(blankModel.breaks.valueRange(43..<43) { _ in .end } == 44..<44)
    precondition(blankModel.breaks.valueRange(44..<44) { _ in .start(skipping: 0) } == 46..<46)
    precondition(EmptyParagraphs.chromium(blankParagraphs) == (blankValue, blankMarkers, [43]))

    let blankBuilt = blankBuild(memo: nil)
    precondition(blankNeeds == [
        .emptyParagraph, .emptyParagraphs(value: blankValue, markers: blankMarkers, why: .first), .side(.lower), .side(.upper),
        .unreachable(value: blankValue, markers: blankMarkers,
                     candidates: UnreachableLines.candidates(text: blankModel.text, breaks: blankModel.breaks), why: .first),
    ])
    precondition(blankBuilt.snapshot.text == blankModel.text && blankBuilt.snapshot.selection == 45..<45 && blankBuilt.snapshot.valueGap == 1)
    precondition(blankBuilt.snapshot.holdsEmptyParagraphs && !blankBuilt.snapshot.caretInEmptyParagraph, "its own line holds the caret")
    blankNeeds = []
    let blankRebuilt = blankBuild(memo: blankBuilt.memo, unreachable: blankBuilt.unreachable)
    precondition(blankRebuilt.snapshot == blankBuilt.snapshot && blankRebuilt.memo == blankBuilt.memo)
    precondition(blankNeeds == [.emptyParagraph, .side(.lower), .side(.upper)], "a memo that holds spares discovery")

    // Each placement Chrome 153 was measured in, round-tripped through every caret.
    for paragraphs in [["L", "", "N"], ["L", "", "", "N"], ["L", "", "", "", "N"], ["", "L"], ["", "", "L"], ["L", ""], ["L", "", ""],
                       [""], ["", ""], ["L", "N"], ["a", "", "bc", "", "", "d", ""]] {
        let truth = paragraphs.joined(separator: "\n")
        let shown = EmptyParagraphs.chromium(paragraphs)
        let aligned = ParagraphBreaks(value: shown.value, fieldText: shown.markers)!
        let restored = EmptyParagraphs.restore(value: shown.value, fieldText: shown.markers, aligned: aligned, found: shown.found)
        precondition(restored?.text == truth && restored?.gap == truth.utf16.count - shown.value.utf16.count, "\(paragraphs)")
        let host = ChromiumParagraphs(text: truth)
        for caret in 0...truth.utf16.count {
            let field = host.field(caret)
            let read = restored?.breaks.valueRange(field..<field) { _ in host.side(caret) }
            precondition(read == caret..<caret, "\(paragraphs) at \(caret)")
        }
    }
    precondition(EmptyParagraphs.restore(value: "L\nN", fieldText: "L\nN", aligned: ParagraphBreaks(offsets: []), found: [0]) == nil,
                 "a found offset must be a <br>")
    precondition(EmptyParagraphs.restore(value: "L\n\nN", fieldText: "L\n\nN", aligned: ParagraphBreaks(offsets: []), found: [2, 1]) == nil)
    precondition(EmptyParagraphs.restore(value: "a\nb", fieldText: "a\nb", aligned: ParagraphBreaks(offsets: []), found: [])
                 == EmptyParagraphs.Model(text: "a\nb", breaks: ParagraphBreaks(offsets: []), gap: 0), "no blank line, no change")

    precondition(e78Shown.value.utf16.count == 218 && e78Shown.markers.utf16.count == 216 && e78Shown.found == [210])

    precondition(e78Model.breaks.offsets == [121, 204, 212] && e78Model.gap == 1)

    let e78k = e78Planning("k", caret: 213).plan
    precondition(e78k.traceShape == "P!PP!C")
    precondition(settleTraces(e78k) == ["sel=210..210 len=218 edge=start", "sel=203..203 len=218 edge=start"], "c61 leaves the blank line")
    let e78j = e78Planning("j", caret: 205).plan
    precondition(e78j.traceShape == "P!P!C")
    precondition(settleTraces(e78j) == ["sel=210..210 len=218 edge=end", "sel=210..210 len=218 edge=start"], "c60: j stops on it")
    let e78dd = e78Planning("dd", caret: 205).plan
    precondition(e78dd.traceShape == "P!P!P!!P?CC")
    precondition(settleTraces(e78dd)[2] == "sel=203..210 len=218 edge=start", "c49: ⇧→ ends in the blank line")
    precondition(settleTraces(e78dd).last == "soft sel=203..203 len=nil", "and what AXValue shows after is a guess")

    var e78Keys = blankSim(e78Paragraphs, caret: 205)
    e78Keys.type("j")
    precondition(e78Keys.caret == 213 && e78Keys.settleFailures == 0, "j from the line above lands in the blank line")
    e78Keys.type("k")
    precondition(e78Keys.caret == 205 && e78Keys.settleFailures == 0)
    e78Keys.type("jj")
    precondition(e78Keys.caret == 214)
    e78Keys.type("kk")
    precondition(e78Keys.caret == 205 && e78Keys.settleFailures == 0 && e78Keys.bells == 0)
    var e78Above = blankSim(e78Paragraphs, caret: 205)
    e78Above.type("dd")
    precondition(e78Above.text == [e78Paragraphs[0], e78Paragraphs[1], "", "ddddd"].joined(separator: "\n"))
    precondition(e78Above.settleFailures == 0)
    var e78Blank = blankSim(e78Paragraphs, caret: 213)
    e78Blank.type("dd")
    precondition(e78Blank.text == [e78Paragraphs[0], e78Paragraphs[1], "ccccccc", "ddddd"].joined(separator: "\n"))
    precondition(e78Blank.settleFailures == 0 && e78Blank.caret == 213)
    for keys in ["h", "j", "k", "l", "0", "$", "w", "b", "e", "x", "D", "gg", "G", "yy", "ma`a"] {
        var fromBlank = blankSim(e78Paragraphs, caret: 213)
        fromBlank.type(keys)
        precondition(fromBlank.settleFailures == 0 && fromBlank.unsupportedSteps == 0, "\(keys) from the blank line")
    }
    var blankInsert = blankSim(e78Paragraphs, caret: 213)
    blankInsert.type("I")
    blankInsert.feed("<C-[>")
    precondition(blankInsert.caret == 213 && blankInsert.settleFailures == 0 && blankInsert.state.field.mode == .normal)
    var blankVisual = blankSim(e78Paragraphs, caret: 213)
    blankVisual.type("v")
    precondition(blankVisual.state.field.mode == .visual(VimState.VisualContext(kind: .character, anchor: 213)))

    // Without discovery the field keeps AXValue's lines, and e78 happens as logged.
    var e78Logged = blankSim(e78Paragraphs, caret: 205)
    e78Logged.findsEmptyParagraphs = false
    e78Logged.type("j")
    precondition(e78Logged.settleFailures == 1 && e78Logged.caret == 213, "c60")
    e78Logged.type("k")
    precondition(e78Logged.settleFailures == 2 && e78Logged.caret == 213, "c61: the caret stays in the blank line")
    precondition(e78Logged.attribution.evidence.contains { $0.question == .key(.lineStartKey) && $0.why == .emptyParagraph })

    // Two in a row, and at either end.
    var twoBlank = blankSim(["alpha", "", "", "omega"], caret: 0)
    twoBlank.type("jjj")
    precondition(twoBlank.caret == 8 && twoBlank.settleFailures == 0)
    twoBlank.type("kk")
    precondition(twoBlank.caret == 6 && twoBlank.settleFailures == 0)
    var edgesBlank = blankSim(["", "alpha", ""], caret: 1)
    edgesBlank.type("k")
    precondition(edgesBlank.caret == 0 && edgesBlank.settleFailures == 0)
    edgesBlank.type("G")
    precondition(edgesBlank.caret == 7 && edgesBlank.settleFailures == 0)

    var e78Writes = blankSim(e78Paragraphs, caret: 205, profile: writeKeys)
    e78Writes.type("j")
    precondition(e78Writes.caret == 213 && e78Writes.settleFailures == 0)
    e78Writes.type("k")
    precondition(e78Writes.caret == 205 && e78Writes.settleFailures == 0)

    for profile in [writeKeys, keyProfile] {
        let atEnd = strandedChange(["ab cd", "ef gh"], caret: 5, profile: profile)
        precondition(atEnd.text == "ab cdX\nef gh" && atEnd.settleFailures == 1, "the repair leaves the caret at the paragraph's end")
    }
    let unstepped = strandedChange(["ab cd", "ef gh"], caret: 5, profile: writeKeys, ignored: [.right])
    precondition(unstepped.text == "ab cd\nXef gh" && unstepped.settleFailures == 2,
                 "keys the host ignores fail their settle, and a write lane then writes the start as read")
    let atStart = strandedChange(["ab cd", "ef gh"], caret: 6, profile: keyProfile, rebound: [.selectLeft: .selectAll])
    precondition(atStart.text == "ab cd\nXef gh" && atStart.settleFailures == 1, "and presses no ⇧← above a paragraph's start")
    let numbered = [Sim.ListLine(marker: "1."), Sim.ListLine(marker: "2."), Sim.ListLine()]
    precondition(strandedChange(["one", "two three", "four"], caret: 3, profile: writeKeys, lines: numbered).text
                 == "oneX\ntwo three\nfour", "the snapshot's text tells that a write to a list item's end needs keys, so ← collapses there too")
    let atDrawn = strandedChange(["ab x", "cd ef", "gh"], caret: 4, profile: writeKeys, lines: numbered, code: [3..<4])
    precondition(atDrawn.text == "ab xX\ncd ef\ngh" && atDrawn.settleFailures == 1,
                 "the caret Linear drew at the code span has gone with its <br>, so the repair reads the field again")
    var insideSpan = blankSim(["ab x cd ef", "gh"], caret: 4, profile: writeKeys)
    insideSpan.listLines = [Sim.ListLine(marker: "1."), Sim.ListLine(marker: "2.")]
    insideSpan.codeSpans = [3..<4]
    insideSpan.reboundChords = [.selectRight: .selectWordRight, Chord.paragraphEnd.shifted: .selectWordRight]
    insideSpan.type("C")
    insideSpan.reboundChords = [:]
    insideSpan.type("X")
    precondition(insideSpan.text == "ab xX cd ef\ngh" && insideSpan.settleFailures == 1,
                 "a code span's end inside a paragraph is written as read")
    for profile in [writeKeys, keyProfile] {
        let afterChip = strandedChange(["ab \u{2060}", "ef gh"], caret: 4, profile: profile, lines: [Sim.ListLine(), Sim.ListLine()])
        precondition(afterChip.text == "ab \u{2060}X\nef gh" && afterChip.settleFailures == 1,
                     "once the chip's image has changed AXValue, the field read again puts the caret past the chip's <br>")
    }
    var strandedToDo = blankSim(["one", "", "two"], caret: 4, profile: writeKeys)
    strandedToDo.listLines = [Sim.ListLine(), Sim.ListLine(leaves: 2, checkbox: true), Sim.ListLine()]
    strandedToDo.swallowsReplace = true
    strandedToDo.type("dd")
    precondition(strandedToDo.settleFailures == 1 && strandedToDo.selection == 4..<4, "a selection at a to-do's start is no caret placed there")

    // Beside a line put back, emptying one changes which empty paragraphs AXValue hides, so no length is checked after it.
    var emptied = blankSim(e78Paragraphs, caret: 214, profile: writeKeys)
    emptied.type("cc")
    precondition(emptied.text == [e78Paragraphs[0], e78Paragraphs[1], "ccccccc", "", ""].joined(separator: "\n"))
    precondition(emptied.settleFailures == 0 && emptied.state.field.mode == .insert)
    precondition(settleTraces(e78Planning("x", caret: 205).plan).last == "soft sel=203..203 len=217 edge=start",
                 "a line that stays non-empty keeps its length")

    let middleBlank = blank(1)
    precondition(scanned([paragraph(0, 1), middleBlank, paragraph(2, 3)], "L\nN") == [1])
    middleBlank.fails = true
    precondition(scanned([paragraph(0, 1), middleBlank, paragraph(2, 3)], "L\nN") == nil, "a failed read fails the scan")
    precondition(scanned([FakeNode("AXGroup", nil, 0, 3, [text(0, 1), text(1, 2), text(2, 3)])], "a\nb") == [],
                 "a soft break is a paragraph's own text")
    let quote = FakeNode("AXGroup", nil, 1, 4, [paragraph(1, 2), blank(2), paragraph(3, 4)])
    precondition(scanned([paragraph(0, 1), quote, paragraph(4, 5)], "Lq\nmN") == [2], "one nested in a quote")
    quote.children[0].fails = true
    precondition(scanned([paragraph(0, 1), quote, paragraph(4, 5)], "Lq\nmN") == nil, "and a failed read on the way down")
    let item = FakeNode("AXGroup", nil, 0, 3, [FakeNode("AXListMarker", nil, 0, 2), blank(2)])
    precondition(scanned([FakeNode("AXList", "AXContentList", 0, 3, [item])], "\u{2022} \n") == [],
                 "an empty list item's line is its marker's")
    precondition(scanned((0..<300).map { paragraph($0, $0 + 1) }, String(repeating: "x", count: 299) + "\n") == nil,
                 "a field past the budget keeps AXValue's lines")

    for mode in chromiumModes where mode.name != "reads" {
        for leaf in [false, true] {
            var host = Sim(text: "ab\ncd\nef", caret: 3, profile: keyProfile)
            mode.apply(&host)
            host.readModel = .textContent
            host.emulatesKeys = true
            host.endsInTextlessLeaf = leaf
            host.type("J")
            precondition(host.text == (leaf ? "ab\ncd\nef" : "ab\ncd ef") && host.bells == (leaf ? 1 : 0), "\(mode.name) leaf=\(leaf)")
        }
    }

    // A trailing blank line nets no gap, but emptying the line beside it still changes what AXValue shows.
    var trailingBlank = blankSim(["a", ""], caret: 0, profile: writeKeys)
    trailingBlank.type("x")
    precondition(trailingBlank.text == "\n" && trailingBlank.settleFailures == 0)
}
