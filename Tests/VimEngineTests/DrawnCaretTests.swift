// MARK: - Drawn carets beside code spans (LIN-1683)

// Dia 1.49.1 on linear.app, probed by softlash/LIN-1683 scripts/code-probe: the text, then each caret Linear drew.
let codeValue = [
    "Plain opening paragraph with a few words to move around in.",
    "Marks: a bold word then an italic word then code span then a link text and it is done.",
    "lead starts this paragraph with code and goes on.",
    "This paragraph ends with code tail",
    "Two spans one and two share a line here.",
    "Adjacent boldcode marks and x one letter.",
    "Last plain paragraph is here.",
].joined(separator: "\n")
let codeRaw = "Plain opening paragraph with a few words to move around in.Marks: a bold word then an italic word then code span then a link text and it is done.lead starts this paragraph with code and goes on.This paragraph ends with code tailTwo spans one and two share a line here.Adjacent boldcode marks and x one letter.Last plain paragraph is here."

let midStartOutsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/E/103/103 1.6/D/103/112 1.6.0/T/103/112 1.7/T/112/120 1.8/K/120/129 1.8.0/T/120/129 1.9/T/129/145
2/G/145/194 2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228
4/G/228/268 4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268
5/G/268/309 5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
let midStartInsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/E/103/103 1.5.1/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145
2/G/145/194 2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228
4/G/228/268 4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268
5/G/268/309 5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
let midEndInsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.5.1/E/112/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145
2/G/145/194 2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228
4/G/228/268 4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268
5/G/268/309 5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
let midEndOutsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/E/112/112 1.7/T/112/120 1.8/K/120/129 1.8.0/T/120/129 1.9/T/129/145
2/G/145/194 2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228
4/G/228/268 4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268
5/G/268/309 5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
let leadStartTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145 2/G/145/194
2.0/E/145/145 2.1/D/145/149 2.1.0/T/145/149 2.2/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228
4/G/228/268 4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268
5/G/268/309 5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
let tailEndOutsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145 2/G/145/194
2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/229 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228 3.2/E/228/228
4/G/229/269 4.0/T/229/239 4.1/D/239/242 4.1.0/T/239/242 4.2/T/242/247 4.3/D/247/250 4.3.0/T/247/250 4.4/T/250/269
5/G/269/310 5.0/T/269/278 5.1/S/278/282 5.1.0/T/278/282 5.2/D/282/286 5.2.0/T/282/286 5.3/T/286/297 5.4/D/297/298
5.4.0/T/297/298 5.5/T/298/310 6/G/310/339 6.0/T/310/339
""")
let tailEndInsideTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145 2/G/145/194
2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/229 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228 3.1.1/E/228/228
4/G/229/269 4.0/T/229/239 4.1/D/239/242 4.1.0/T/239/242 4.2/T/242/247 4.3/D/247/250 4.3.0/T/247/250 4.4/T/250/269
5/G/269/310 5.0/T/269/278 5.1/S/278/282 5.1.0/T/278/282 5.2/D/282/286 5.2.0/T/282/286 5.3/T/286/297 5.4/D/297/298
5.4.0/T/297/298 5.5/T/298/310 6/G/310/339 6.0/T/310/339
""")

let boldEndTree = fakeTree("""
0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145 2/G/145/194
2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228 4/G/228/268
4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268 5/G/268/309
5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.1.1/E/281/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296
5.4/D/296/297 5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
""")
func inserting(_ text: String, _ addition: String, at offset: Int) -> String {
    var units = Array(text.utf16)
    units.insert(contentsOf: addition.utf16, at: offset)
    return String(decoding: units, as: UTF16.self)
}
// Each measured state is the text with what the drawn caret added, then the caret's plain offset and model offset.
let midValue = (start: inserting(codeValue, "\n\n", at: 104), end: inserting(codeValue, "\n\n", at: 113))
let midRaw = (start: inserting(codeRaw, "\u{FFFC}", at: 103), end: inserting(codeRaw, "\u{FFFC}", at: 112))
let tailValue = inserting(codeValue, "\n", at: 232)
let tailRaw = inserting(codeRaw, "\u{FFFC}\n", at: 228)
typealias CodeState = (name: String, value: String, raw: String, tree: [FakeNode], caret: Int, model: Int,
                       place: UnreachableLines.Caret.Place)
let codeStates: [CodeState] = [
    ("outside a start", midValue.start, midRaw.start, midStartOutsideTree, 103, 104, .middle),
    ("inside a start", midValue.start, midRaw.start, midStartInsideTree, 103, 104, .middle),
    ("inside an end", midValue.end, midRaw.end, midEndInsideTree, 112, 113, .middle),
    ("outside an end", midValue.end, midRaw.end, midEndOutsideTree, 112, 113, .middle),
    ("a paragraph's start", inserting(codeValue, "\n", at: 147), inserting(codeRaw, "\u{FFFC}", at: 145), leadStartTree, 145, 147, .start),
    ("outside a paragraph's end", tailValue, tailRaw, tailEndOutsideTree, 228, 231, .end),
    ("inside a paragraph's end", tailValue, tailRaw, tailEndInsideTree, 228, 231, .end),
    ("inside bold before code", inserting(codeValue, "\n\n", at: 286), inserting(codeRaw, "\u{FFFC}", at: 281), boldEndTree, 281, 286,
     .middle),
]

func codeBuild(_ state: CodeState, side: ParagraphBreaks.Side) -> FieldSnapshot {
    let plain = MarkerText.plain(state.raw)
    let aligned = ParagraphBreaks(value: state.value, fieldText: plain)!
    var reads = FieldSnapshot.Reads(
        field: FieldReads(text: state.value, plain: state.caret..<state.caret, markers: MarkerReads(
            breaks: aligned, value: aligned.valueRange(state.caret..<state.caret) { _ in side }
        )),
        length: state.value.utf16.count, webContent: true, blocks: 7, marked: state.caret..<state.caret, markerText: state.raw
    )
    var memo: EmptyParagraphs.Memo?
    var unreachable: UnreachableLines.Memo?
    return FieldSnapshot.Step.run(taking: { need in
        switch need {
        case .side(let end): reads.sides.updateValue(side, forKey: end)
        case .emptyParagraph: reads.inEmptyParagraph = true
        case .emptyParagraphs(let value, let raw, _):
            memo = EmptyParagraphs.Memo(value: value, markers: raw, blocks: reads.blocks, found: scanned(state.tree, plain))
        case .unreachable(let value, let raw, let candidates, _):
            unreachable = UnreachableLines.Memo(value: value, markers: raw, blocks: reads.blocks,
                                                found: unreachableScanned(state.tree, candidates))
        }
    }) {
        FieldSnapshot.build(reads, capabilities: keyProfile, answer: .textContent, anchor: nil, cursor: nil, memo: memo,
                            unreachable: unreachable)
    }.snapshot
}

let tailSnapshot = codeBuild(codeStates[5], side: .end)
func tailPlan(_ keys: String) -> PhysicalPlan {
    PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: FieldSnapshot(
        capabilities: writeKeys, text: tailSnapshot.text, selection: tailSnapshot.selection, webContent: true,
        breaks: tailSnapshot.breaks, foldedLength: tailSnapshot.foldedLength, holdsDrawnCaret: true, drawnBreak: tailSnapshot.drawnBreak
    ))
}

// A Sim of Linear's editor with code spans moves and edits as Vim does, in both lanes.
let codeDoc = ["Marks then code span then a link.", "lead starts here", "ends with tail", "x is one letter", "last line"]
func codeSim(_ profile: CapabilityProfile, caret: Int = 0) -> Sim {
    var host = Sim(text: codeDoc.joined(separator: "\n"), caret: caret, profile: profile)
    host.emptyParagraphs = true
    host.listLines = codeDoc.map { _ in Sim.ListLine() }
    host.codeSpans = [11..<20, 34..<38, 61..<65, 66..<67]
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}

// Spans one letter long at the edges of list items, to-dos and lines beside chips, where writes are reached by keys.
let listCodeDoc: [(String, String?, Int, Bool)] = [
    ("Top line ab x", nil, 0, false), ("\u{2060} tail", nil, 0, false), ("x hi", "\u{2022}", 0, false),
    ("item ends y", "\u{2022}", 0, false), ("z", nil, 0, false), ("q to do", nil, 2, true), ("done r", nil, 2, true),
    ("\u{2060}", nil, 0, false), ("w", "1.", 0, false), ("Last code", nil, 0, false),
]

func listCodeSim(_ profile: CapabilityProfile, caret: Int, spans: [Range<Int>]) -> Sim {
    var host = Sim(text: listCodeDoc.map(\.0).joined(separator: "\n"), caret: caret, profile: profile)
    host.emptyParagraphs = true
    host.listLines = listCodeDoc.map { Sim.ListLine(marker: $0.1, leaves: $0.2, checkbox: $0.3) }
    host.codeSpans = spans
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}

func testDrawnCarets() {
    let codeTree = fakeTree("""
    0/G/0/59 0.0/T/0/59 1/G/59/145 1.0/T/59/68 1.1/S/68/77 1.1.0/T/68/77 1.2/T/77/86 1.3/F/86/97 1.3.0/T/86/97
    1.4/T/97/103 1.5/D/103/112 1.5.0/T/103/112 1.6/T/112/120 1.7/K/120/129 1.7.0/T/120/129 1.8/T/129/145 2/G/145/194
    2.0/D/145/149 2.0.0/T/145/149 2.1/T/149/194 3/G/194/228 3.0/T/194/224 3.1/D/224/228 3.1.0/T/224/228 4/G/228/268
    4.0/T/228/238 4.1/D/238/241 4.1.0/T/238/241 4.2/T/241/246 4.3/D/246/249 4.3.0/T/246/249 4.4/T/249/268 5/G/268/309
    5.0/T/268/277 5.1/S/277/281 5.1.0/T/277/281 5.2/D/281/285 5.2.0/T/281/285 5.3/T/285/296 5.4/D/296/297
    5.4.0/T/296/297 5.5/T/297/309 6/G/309/338 6.0/T/309/338
    """)

    let noCaret = UnreachableLines.Found(markers: [], chips: [])
    precondition(folded(codeValue, codeRaw, codeTree).text == codeValue, "code spans alone are no lines")
    for state in codeStates {
        let plain = MarkerText.plain(state.raw)
        let aligned = ParagraphBreaks(value: state.value, fieldText: plain)!
        let candidates = UnreachableLines.candidates(text: state.value, breaks: aligned, raw: state.raw)
        precondition(candidates.carets == [state.caret], state.name)
        precondition(unreachableScanned(state.tree, candidates)?.carets == [.init(offset: state.caret, place: state.place)], state.name)
        precondition(scanned(state.tree, plain) == [], "\(state.name): the <br> after a drawn caret is no empty paragraph")
        let model = folded(state.value, state.raw, state.tree)
        precondition(model.text == codeValue, "\(state.name): the model is the text without the drawn caret")
        let withoutBreak = model.drawnBreak.map { String(plain.prefix($0)) + String(plain.dropFirst($0 + 1)) } ?? plain
        precondition(model.breaks.fieldText(model.text, at: 0..<model.text.utf16.count) == withoutBreak && roundTrips(model), state.name)
        precondition(model.breaks.fieldOffset(state.model) == state.caret, state.name)
        let unfolded = UnreachableLines.fold(text: state.value, breaks: aligned, raw: state.raw, found: noCaret).text
        precondition(state.place == .start || unfolded != codeValue, "\(state.name): undiscovered, the drawn caret's line stays")
    }
    let tailModel = folded(tailValue, tailRaw, tailEndOutsideTree)
    precondition(tailModel.drawnBreak == 228 && tailModel.breaks.fieldOffset(232) == 228,
                 "offsets past the <br> after a caret drawn at a paragraph's end are the field's once the caret leaves")
    precondition(unreachableScanned([FakeNode("AXGroup", nil, 0, 4, [text(0, 2), FakeNode("AXGroup", "AXEmptyGroup", 2, 2), text(2, 4)])],
                                    UnreachableLines.Candidates(markers: [], chips: [], carets: [2]))?.carets == [],
                 "an empty group away from code is no drawn caret")
    precondition(unreachableScanned(midStartOutsideTree, UnreachableLines.Candidates(markers: [], chips: [], carets: [103]), budget: 8)
                 == nil, "past its budget")
    precondition(DrawnCaret.isCaret(parent: "AXCodeStyleGroup", previous: nil, next: nil)
                 && DrawnCaret.isCaret(parent: nil, previous: nil, next: "AXCodeStyleGroup")
                 && !DrawnCaret.isCaret(parent: "AXStrongStyleGroup", previous: "AXApplicationGroup", next: nil))
    precondition(DrawnCaret.isInline(role: "AXLink", subrole: nil) && DrawnCaret.isInline(role: "AXGroup", subrole: "AXStrongStyleGroup")
                 && !DrawnCaret.isInline(role: "AXGroup", subrole: nil))
    precondition([.middle, .start, .end].map(DrawnCaret.length) == [2, 1, 1], "two lines' worth inside a paragraph, one at its start or end")
    precondition(DrawnCaret.side(.start) == .start(skipping: 0) && DrawnCaret.side(.end) == .end)

    var lingering = codeStates[5]
    lingering.caret = 229
    precondition(codeBuild(lingering, side: .end).selection == 232..<232, "a read past the <br> is the next line's start")
    for state in codeStates {
        let snapshot = codeBuild(state, side: DrawnCaret.side(state.place))
        precondition(snapshot.text == codeValue && snapshot.selection == state.model..<state.model, state.name)
        precondition(snapshot.holdsDrawnCaret && !snapshot.caretInEmptyParagraph && snapshot.foldedLength > 0, state.name)
        let x = PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("x"), state: .initial), snapshot: snapshot)
        precondition(!x.steps.contains(.bell) && settleTraces(x).allSatisfy { $0.contains("len=nil") },
                     "\(state.name): its lines leave with the caret, so no length is checked")
    }

    precondition(tailPlan("j").steps.first == .setSelection(263..<263) && settleTraces(tailPlan("j")).first == "sel=262..262 len=nil",
                 "a write while the caret is drawn meets the <br>, which is gone once it lands")
    precondition(tailPlan("w").steps.first == .setSelection(229..<229), "the next paragraph's start is past the <br>")
    precondition(tailPlan("h").steps.first == .setSelection(227..<227), "and this one's end before it")

    precondition(ChromiumParagraphs(text: "ab cd e\nf", lines: [Sim.ListLine(), Sim.ListLine()], caret: 3, drawn: 3).shown
                 == ("ab \n\ncd e\nf", "ab \u{FFFC}cd ef", []), "a caret drawn mid-paragraph is a line of its own")
    precondition(ChromiumParagraphs(text: "ab\ncd\nef", lines: [Sim.ListLine(), Sim.ListLine(), Sim.ListLine()], caret: 5, drawn: 5)
                 .shown == ("ab\ncd\n\nef", "abcd\u{FFFC}\nef", []), "and at a paragraph's end, one with a <br> after it")
    var toggling = codeSim(writeKeys)
    toggling.perform([.setSelection(11..<11), .press(.right, count: 1)])
    precondition(toggling.readSelection == 11..<11, "a caret written at a code span's start is outside it, and → steps in")
    toggling.perform([.press(.right, count: 1), .press(.left, count: 1), .press(.left, count: 1)])
    precondition(toggling.readSelection == 11..<11, "then ← steps out")
    toggling.perform([.press(.selectRight, count: 1), .press(.right, count: 1)])
    precondition(toggling.readSelection == 12..<12, "shifted keys cross the edge")
    for profile in [keyProfile, writeKeys] {
        let down = String(repeating: "j", count: codeDoc.count)
        for keys in ["lllllllllllllllllllllllllllllll" + String(repeating: "h", count: 31), down + String(repeating: "k", count: codeDoc.count),
                     "wwwwwwwwwwwwwwwwbbbbbbbbbbbbbbbb", "eeeeeeeeeeee", "5l3lj2lkj$jjk0jjj^", "fsfcfpfk", "jlhjjlh",
                     "jjj$hhlxlx", "wwxwwdwjx", "wwwcwX", "jA", "jjdd", "jwD", "wwwwD", "jjjwD", "llllllllllllhx",
                     "llllllllllllhyw", "llllllllllllhD", "jlhdw", "jjjlhx", "llllllllllllhhlx"] {
            var code = codeSim(profile)
            var plain = Sim(text: code.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                code.type(String(key))
                plain.type(String(key))
                precondition(code.caret == plain.caret && code.text == plain.text, "\(keys) at \(key)")
            }
            code.feed("<Esc>")
            plain.feed("<Esc>")
            precondition(code.caret == plain.caret && code.text == plain.text, "\(keys) then Esc")
            precondition(code.settleFailures == 0 && code.bells == 0 && code.unsupportedSteps == 0, "\(keys): \(code.settleFailures)")
        }
    }

    let listCodeStarts = listCodeDoc.indices.map { listCodeDoc.prefix($0).map { $0.0.utf16.count + 1 }.reduce(0, +) }
    let listCodeSpans = [(0, 12, 13), (2, 0, 1), (3, 10, 11), (5, 0, 1), (6, 5, 6), (8, 0, 1), (9, 5, 9)].map {
        listCodeStarts[$0.0] + $0.1 ..< listCodeStarts[$0.0] + $0.2
    }

    for caret in listCodeSpans.flatMap({ [$0.lowerBound, $0.upperBound] }) {
        for keys in ["AQ", "$", "l", "k", "2j", "dd", "yyp", "dw", "Vjd"] {
            var code = listCodeSim(writeKeys, caret: caret, spans: listCodeSpans)
            var plain = listCodeSim(writeKeys, caret: caret, spans: [])
            for key in keys {
                code.type(String(key))
                plain.type(String(key))
            }
            code.feed("<Esc>")
            plain.feed("<Esc>")
            precondition(code.caret == plain.caret && code.text == plain.text && code.bells == plain.bells
                         && code.settleFailures == plain.settleFailures, "\(keys) from \(caret)")
        }
    }
    for (text, spans, caret, keys) in [
        ("foo code\n\u{2060} text", [4..<8], 4, ["dd"]), ("ab x\n\u{2060} tail", [3..<4], 0, ["AQ"]),
        ("aa\nx hi\n\u{2060} tail", [3..<4], 0, ["j", "x"]), ("ab x\nyyyy\nz\n\u{2060} tail", [3..<4], 4, ["2j"]),
    ] {
        var code = Sim(text: text, caret: caret, profile: writeKeys)
        code.emptyParagraphs = true
        code.listLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { _ in Sim.ListLine() }
        code.codeSpans = spans
        code.emulatesKeys = true
        code.readModel = .textContent
        var plain = Sim(text: text, caret: caret, profile: writeKeys)
        plain.emulatesKeys = true
        for command in keys {
            code.type(command)
            plain.type(command)
            if code.state.field.mode == .insert { code.feed("<Esc>"); plain.feed("<Esc>") }
        }
        precondition(code.caret == plain.caret && code.text == plain.text && code.settleFailures == 0, "\(text) \(keys)")
    }

    // A quick command's snapshot can come before Linear draws the caret, and a write beside a line ending in code can draw one.
    for (profile, text, spans, kinds, caret, keys) in [
        (keyProfile, "ab code zz", [3..<7], "p", 4, ["yiw", "x"]), (writeKeys, "e\nd\n", [0..<1], "1.,t,p", 4, ["AQ"]),
        (writeKeys, "e\nd\n", [0..<1], "1.,t,p", 4, ["IQ"]), (writeKeys, "ab\ne\nd\n", [3..<4], "p,1.,t,p", 0, ["3j", "AQ"]),
    ] {
        func sim(_ spans: [Range<Int>]) -> Sim {
            var host = Sim(text: text, caret: caret, profile: profile)
            host.emptyParagraphs = true
            host.listLines = kinds.split(separator: ",").map {
                $0 == "p" ? Sim.ListLine() : $0 == "t" ? Sim.ListLine(leaves: 2, checkbox: true) : Sim.ListLine(marker: String($0))
            }
            host.codeSpans = spans
            host.drawsLate = true
            host.emulatesKeys = true
            host.readModel = .textContent
            return host
        }
        var code = sim(spans)
        var plain = sim([])
        for command in keys {
            code.type(command)
            plain.type(command)
            if code.state.field.mode == .insert { code.feed("<Esc>"); plain.feed("<Esc>") }
        }
        precondition(code.caret == plain.caret && code.text == plain.text && code.settleFailures == plain.settleFailures,
                     "\(text) \(keys)")
    }

    // A paragraph's first code span: ⇧→ selects from inside it, and only ⇧⌃E needs ⌃A first, the field's start included.
    var firstSpan = Sim(text: "aa\ncode x", caret: 3, profile: keyProfile)
    firstSpan.emptyParagraphs = true
    firstSpan.listLines = [Sim.ListLine(), Sim.ListLine()]
    firstSpan.codeSpans = [3..<7]
    firstSpan.emulatesKeys = true
    firstSpan.readModel = .textContent
    precondition(firstSpan.perform([.press(.right, count: 1), .press(.selectRight, count: 1)]) && firstSpan.selection == 3..<4)
    precondition(paragraphPlanning("D", text: "code x\nzz", caret: 0, profile: keyProfile).plan.steps.first
                 == .press(.paragraphStart, count: 1))
    precondition(paragraphPlanning("x", text: "code x\nzz", caret: 0, profile: keyProfile).plan.steps.first
                 == .press(.selectRight, count: 1))
    let noLineStart = removing([.lineStartKey], from: keyProfile)
    for (text, span, caret, left) in [("aa\ncode x", 3..<7, 3, "aa\n"), ("code x\nzz", 0..<4, 0, "\nzz")] {
        for profile in [keyProfile, noLineStart] {
            var host = Sim(text: text, caret: caret, profile: profile)
            host.emptyParagraphs = true
            host.listLines = [Sim.ListLine(), Sim.ListLine()]
            host.codeSpans = [span]
            host.emulatesKeys = true
            host.readModel = .textContent
            precondition(host.perform([.press(.right, count: 1)]))
            host.type("D")
            precondition(host.text == left && host.settleFailures == 0, "\(text) D")
        }
    }

    // A caret read past the text's end, as stepping inside a field's first code span gives, is no caret to plan from.
    let pastEnd = FieldSnapshot.Step.run(taking: { _ in }) {
        FieldSnapshot.build(FieldSnapshot.Reads(field: FieldReads(text: "code x\nzz", plain: 94..<94), length: 9, webContent: true),
                            capabilities: keyProfile, answer: .value, anchor: nil, cursor: nil, memo: nil)
    }.snapshot
    precondition(pastEnd.selection == nil)
    _ = PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand("D"), state: .initial), snapshot: pastEnd)

    // No write-lane plan has a counted ← run, whose first ← a caret the last plan wrote at a code span's end can take.
    for caret in listCodeSpans.flatMap({ [$0.lowerBound, $0.upperBound] }) + listCodeStarts {
        for keys in ["h", "3h", "b", "2b", "x", "X", "3X", "dw", "db", "d3h", "c2h", "D", "A", "I", "0", "$", "j", "k", "dd",
                     "yy", "p", "J", "~", "v3h", "2h", "vb"] {
            var host = listCodeSim(writeKeys, caret: caret, spans: listCodeSpans)
            var (reads, observed) = host.read()
            var memo: EmptyParagraphs.Memo?
            var unreachable: UnreachableLines.Memo?
            let snapshot = FieldSnapshot.Step.run(taking: { host.take($0, into: &reads, memo: &memo, unreachable: &unreachable) }) {
                FieldSnapshot.build(reads, capabilities: writeKeys, answer: observed.after, anchor: nil, cursor: nil, memo: memo,
                                    unreachable: unreachable)
            }.snapshot
            let steps = PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: host.state), snapshot: snapshot).steps
            var written = true
            for step in steps {
                switch step {
                case .setSelection: written = true
                case .press(.selectLeft, let count), .press(.left, let count):
                    precondition(!written || count < 2, "\(keys) from \(caret)")
                case .press: written = false
                default: break
                }
            }
        }
    }
}
