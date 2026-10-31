// MARK: - The field document in one walk (LIN-2388)

// Tiptap (ProseMirror) in Chrome for Testing 153, W an AXCell, recorded 2026-10-29 by softlash/LIN-2048 (commit 10b9362) and converted by softlash/LIN-2369.

// Google Chrome for Testing 153.0.8010.52, field classes ['tiptap', 'ProseMirror'].
let tiptapBlocksValue = "Para zero\n• Item one\n• Item two\n1. Num one\nQuote one\ncode one\nQuote two\nPara one\n\nPara two\n\n\n• Item three\n\nQuote three\n\nSum closed\n• Item four\n\nSum open\nBody open\n• Body item\n• Nest item\nNest quote\nPara end"
let tiptapBlocksRaw = "Para zero• Item one• Item two1. Num oneQuote onecode oneQuote twoPara onePara two• Item threeQuote threeSum closed• Item fourSum openBody open• Body item• Nest itemNest quotePara end"
let tiptapBlocksSpec = """
0/G/0/9 0.0/T/0/9 1/L/9/29 1.0/G/9/19 1.0.0/M/9/11 1.0.1/G/11/19 1.0.1.0/T/11/19 1.1/G/19/29 1.1.0/M/19/21
1.1.1/G/21/29 1.1.1.0/T/21/29 2/L/29/39 2.0/G/29/39 2.0.0/M/29/32 2.0.1/G/32/39 2.0.1.0/T/32/39 3/G/39/48
3.0/G/39/48 3.0.0/T/39/48 4/G/48/56 4.0/D/48/56 4.0.0/T/48/56 5/G/56/65 5.0/G/56/65 5.0.0/T/56/65 6/G/65/73
6.0/T/65/73 7/R/73/73 8/G/73/81 8.0/T/73/81 9/R/81/81 10/R/81/81 11/L/81/93 11.0/G/81/93 11.0.0/M/81/83
11.0.1/G/83/93 11.0.1.0/T/83/93 12/R/93/93 13/G/93/104 13.0/G/93/104 13.0.0/T/93/104 14/J/104/104 15/G/104/114
15.0/T/104/114 16/L/114/125 16.0/G/114/125 16.0.0/M/114/116 16.0.1/G/116/125 16.0.1.0/T/116/125 17/J/125/125
18/G/125/133 18.0/T/125/133 19/G/133/142 19.0/T/133/142 20/L/142/153 20.0/G/142/153 20.0.0/M/142/144
20.0.1/G/144/153 20.0.1.0/T/144/153 21/G/153/174 21.0/L/153/164 21.0.0/G/153/164 21.0.0.0/M/153/155
21.0.0.1/G/155/164 21.0.0.1.0/T/155/164 21.1/G/164/174 21.1.0/G/164/174 21.1.0.0/T/164/174 22/G/174/182
22.0/T/174/182
"""

// Google Chrome for Testing 153.0.8010.52, field classes ['tiptap', 'ProseMirror'].
let tiptapTablesValue = "Para zero\nAone\nAtwo\nBone\nBtwo\nPara one\n• Item one\n• Item two\nCone\nCtwo\nDone\nDtwo\nQuote one\nEone\nEtwo\ncode one\nFone\nGone\nPara end"
let tiptapTablesRaw = "Para zeroAoneAtwoBoneBtwoPara one• Item one• Item twoConeCtwoDoneDtwoQuote oneEoneEtwocode oneFoneGonePara end"
let tiptapTablesSpec = """
0/G/0/9 0.0/T/0/9 1/Y/9/25 1.0/O/9/17 1.0.0/W/9/13 1.0.0.0/G/9/13 1.0.0.0.0/T/9/13 1.0.1/W/13/17 1.0.1.0/G/13/17
1.0.1.0.0/T/13/17 1.1/O/17/25 1.1.0/W/17/21 1.1.0.0/G/17/21 1.1.0.0.0/T/17/21 1.1.1/W/21/25 1.1.1.0/G/21/25
1.1.1.0.0/T/21/25 1.2/Ug/110/110 1.2.0/W/9/13 1.2.0.0/G/9/13 1.2.0.0.0/T/9/13 1.2.1/W/17/21 1.2.1.0/G/17/21
1.2.1.0.0/T/17/21 1.3/Ug/110/110 1.3.0/W/13/17 1.3.0.0/G/13/17 1.3.0.0.0/T/13/17 1.3.1/W/21/25 1.3.1.0/G/21/25
1.3.1.0.0/T/21/25 1.4/Eg/110/110 2/G/25/33 2.0/T/25/33 3/L/33/53 3.0/G/33/43 3.0.0/M/33/35 3.0.1/G/35/43
3.0.1.0/T/35/43 3.1/G/43/53 3.1.0/M/43/45 3.1.1/G/45/53 3.1.1.0/T/45/53 4/Y/53/69 4.0/O/53/61 4.0.0/W/53/57
4.0.0.0/G/53/57 4.0.0.0.0/T/53/57 4.0.1/W/57/61 4.0.1.0/G/57/61 4.0.1.0.0/T/57/61 4.1/O/61/69 4.1.0/W/61/65
4.1.0.0/G/61/65 4.1.0.0.0/T/61/65 4.1.1/W/65/69 4.1.1.0/G/65/69 4.1.1.0.0/T/65/69 4.2/Ug/110/110 4.2.0/W/53/57
4.2.0.0/G/53/57 4.2.0.0.0/T/53/57 4.2.1/W/61/65 4.2.1.0/G/61/65 4.2.1.0.0/T/61/65 4.3/Ug/110/110 4.3.0/W/57/61
4.3.0.0/G/57/61 4.3.0.0.0/T/57/61 4.3.1/W/65/69 4.3.1.0/G/65/69 4.3.1.0.0/T/65/69 4.4/Eg/110/110 5/G/69/78
5.0/G/69/78 5.0.0/T/69/78 6/Y/78/86 6.0/O/78/86 6.0.0/W/78/82 6.0.0.0/G/78/82 6.0.0.0.0/T/78/82 6.0.1/W/82/86
6.0.1.0/G/82/86 6.0.1.0.0/T/82/86 6.1/Ug/110/110 6.1.0/W/78/82 6.1.0.0/G/78/82 6.1.0.0.0/T/78/82 6.2/Ug/110/110
6.2.0/W/82/86 6.2.0.0/G/82/86 6.2.0.0.0/T/82/86 6.3/Eg/110/110 7/G/86/94 7.0/D/86/94 7.0.0/T/86/94 8/Y/94/98
8.0/O/94/98 8.0.0/W/94/98 8.0.0.0/G/94/98 8.0.0.0.0/T/94/98 8.1/Ug/110/110 8.1.0/W/94/98 8.1.0.0/G/94/98
8.1.0.0.0/T/94/98 8.2/Eg/110/110 9/Y/98/102 9.0/O/98/102 9.0.0/W/98/102 9.0.0.0/G/98/102 9.0.0.0.0/T/98/102
9.1/Ug/110/110 9.1.0/W/98/102 9.1.0.0/G/98/102 9.1.0.0.0/T/98/102 9.2/Eg/110/110 10/G/102/110 10.0/T/102/110
"""

// Google Chrome for Testing 153.0.8010.52, field classes ['tiptap', 'ProseMirror'].
let tiptapPublicTableValue = "Name\nDescription\nCyndi Lauper\nSinger\nSongwriter\nActress"
let tiptapPublicTableRaw = "NameDescriptionCyndi LauperSingerSongwriterActress"
let tiptapPublicTableSpec = """
0/Y/0/50 0.0/O/0/15 0.0.0/W/0/4 0.0.0.0/G/0/4 0.0.0.0.0/T/0/4 0.0.1/W/4/15 0.0.1.0/G/4/15 0.0.1.0.0/T/4/15
0.1/O/15/50 0.1.0/W/15/27 0.1.0.0/G/15/27 0.1.0.0.0/T/15/27 0.1.1/W/27/33 0.1.1.0/G/27/33 0.1.1.0.0/T/27/33
0.1.2/W/33/43 0.1.2.0/G/33/43 0.1.2.0.0/T/33/43 0.1.3/W/43/50 0.1.3.0/G/43/50 0.1.3.0.0/T/43/50 0.2/Ug/4280/4280
0.2.0/W/0/4 0.2.0.0/G/0/4 0.2.0.0.0/T/0/4 0.2.1/W/15/27 0.2.1.0/G/15/27 0.2.1.0.0/T/15/27 0.3/Ug/4280/4280
0.3.0/W/4/15 0.3.0.0/G/4/15 0.3.0.0.0/T/4/15 0.3.1/W/27/33 0.3.1.0/G/27/33 0.3.1.0.0/T/27/33 0.4/Ug/4280/4280
0.4.0/W/4/15 0.4.0.0/G/4/15 0.4.0.0.0/T/4/15 0.4.1/W/33/43 0.4.1.0/G/33/43 0.4.1.0.0/T/33/43 0.5/Ug/4280/4280
0.5.0/W/4/15 0.5.0.0/G/4/15 0.5.0.0.0/T/4/15 0.5.1/W/43/50 0.5.1.0/G/43/50 0.5.1.0.0/T/43/50 0.6/Gg/4280/4280
0.6.0/W/0/4 0.6.0.0/G/0/4 0.6.0.0.0/T/0/4 0.6.1/W/4/15 0.6.1.0/G/4/15 0.6.1.0.0/T/4/15 0.6.2/W/4/15 0.6.2.0/G/4/15
0.6.2.0.0/T/4/15 0.6.3/W/4/15 0.6.3.0/G/4/15 0.6.3.0.0/T/4/15
"""

// Linear desktop 1.32.7 with the caret on the block stop between two root lists (plain 18), recorded by softlash/LIN-2048 (74d9655): the stop is root 2, an E one unit wide.
// Linear 1.32.7, field classes ['ProseMirror', 'editor', 'show-inline-comments', 'ProseMirror-focused'].
let linearCaretOnStopValue = "Para zero\n•\nItem one\n1.\nNum one\nQuote one\nPlaintext\n\n\n\ncode one\nPara one\n\nPara two\n\n\n•\nItem three\nCell one\nCell two\nCell three\nCell four\n\n\nPara end"
let linearCaretOnStopRaw = "Para zero•Item one\n1.Num oneQuote onePlaintextcode onePara onePara two•Item threeCell oneCell twoCell threeCell fourPara end"
let linearCaretOnStopSpec = """
0/G/0/9 0.0/T/0/9 1/L/9/18 1.0/G/9/18 1.0.0/G/9/10 1.0.0.0/Tg/9/10 1.0.1/G/10/18 1.0.1.0/T/10/18 2/E/18/19 3/L/19/28
3.0/G/19/28 3.0.0/G/19/21 3.0.0.0/Tg/19/20 3.0.0.1/Tg/20/21 3.0.1/G/21/28 3.0.1.0/T/21/28 4/B/28/37 4.0/G/28/37
4.0.0/T/28/37 5/B/37/54 5.0/N/37/46 5.0.0/G/37/46 5.0.0.0/G/37/46 5.0.0.0.0/T/37/46 5.0.0.1/G/46/46
5.0.0.1.0/I/46/46 5.0.0.2/G/46/46 5.0.0.2.0/I/46/46 5.0.0.3/J/46/46 5.0.0.3.0/I/46/46 5.1/D/46/54 5.1.0/T/46/54
6/G/54/62 6.0/T/54/62 7/R/62/62 8/G/62/70 8.0/T/62/70 9/R/70/70 10/R/70/70 11/L/70/81 11.0/G/70/81 11.0.0/G/70/71
11.0.0.0/Tg/70/71 11.0.1/G/71/81 11.0.1.0/T/71/81 12/X/81/116 12.0/G/81/116 12.0.0/Y/81/116 12.0.0.0/O/81/97
12.0.0.0.0/W/81/89 12.0.0.0.0.0/G/81/89 12.0.0.0.0.0.0/G/81/89 12.0.0.0.0.0.0.0/T/81/89 12.0.0.0.1/W/89/97
12.0.0.0.1.0/G/89/97 12.0.0.0.1.0.0/G/89/97 12.0.0.0.1.0.0.0/T/89/97 12.0.0.1/O/97/116 12.0.0.1.0/W/97/107
12.0.0.1.0.0/G/97/107 12.0.0.1.0.0.0/G/97/107 12.0.0.1.0.0.0.0/T/97/107 12.0.0.1.1/W/107/116 12.0.0.1.1.0/G/107/116
12.0.0.1.1.0.0/G/107/116 12.0.0.1.1.0.0.0/T/107/116 12.0.0.2/Ug/223/223 12.0.0.2.0/W/81/89 12.0.0.2.0.0/G/81/89
12.0.0.2.0.0.0/G/81/89 12.0.0.2.0.0.0.0/T/81/89 12.0.0.2.1/W/97/107 12.0.0.2.1.0/G/97/107 12.0.0.2.1.0.0/G/97/107
12.0.0.2.1.0.0.0/T/97/107 12.0.0.3/Ug/223/223 12.0.0.3.0/W/89/97 12.0.0.3.0.0/G/89/97 12.0.0.3.0.0.0/G/89/97
12.0.0.3.0.0.0.0/T/89/97 12.0.0.3.1/W/107/116 12.0.0.3.1.0/G/107/116 12.0.0.3.1.0.0/G/107/116
12.0.0.3.1.0.0.0/T/107/116 12.0.0.4/Gg/223/223 12.0.0.4.0/W/81/89 12.0.0.4.0.0/G/81/89 12.0.0.4.0.0.0/G/81/89
12.0.0.4.0.0.0.0/T/81/89 12.0.0.4.1/W/89/97 12.0.0.4.1.0/G/89/97 12.0.0.4.1.0.0/G/89/97 12.0.0.4.1.0.0.0/T/89/97
12.1/G/116/116 12.1.0/G/116/116 12.1.0.0/E/116/116 12.1.0.1/P/116/116 12.1.0.1.0/E/116/116 13/G/116/124
13.0/T/116/124
"""

/// Each recorded tree as both scans read it apart, and the one walk.
let documentTrees: [(name: String, value: String, raw: String, spec: String)] = [
    ("quillMixed", quillMixedValue, quillMixedRaw, quillMixedSpec), ("quillEmpty", quillEmptyValue, quillEmptyRaw, quillEmptySpec),
    ("quillNested", quillNestedValue, quillNestedRaw, quillNestedSpec),
    ("quillFirstempty", quillFirstemptyValue, quillFirstemptyRaw, quillFirstemptySpec),
    ("quillOrdered", quillOrderedValue, quillOrderedRaw, quillOrderedSpec),
    ("chromiumNative", chromiumNativeValue, chromiumNativeRaw, chromiumNativeSpec),
    ("linearLists", linearListsValue, linearListsRaw, linearListsSpec),
    ("linearExample4", linearExample4Value, linearExample4Raw, linearExample4Spec),
    ("linearCaretOnStop", linearCaretOnStopValue, linearCaretOnStopRaw, linearCaretOnStopSpec),
    ("tiptapBlocks", tiptapBlocksValue, tiptapBlocksRaw, tiptapBlocksSpec),
    ("tiptapTables", tiptapTablesValue, tiptapTablesRaw, tiptapTablesSpec),
    ("tiptapPublicTable", tiptapPublicTableValue, tiptapPublicTableRaw, tiptapPublicTableSpec),
    ("dia1", dia1Value, dia1Raw, dia1Spec), ("dia7", dia7Value, dia7Raw, dia7Spec),
]

/// Plain paragraphs between Chrome 153's blank lines, then a list of `items` Linear draws: enough blank lines run the walk's
/// share for them out, and enough items its whole budget.
func blankListField(blanks: Int, items: Int) -> (value: String, raw: String, spec: String) {
    var value: [String] = ["Top"], raw = "Top", spec = ["0/G/0/3 0.0/T/0/3"], at = 3, root = 1
    for index in 0..<blanks {
        let text = "Between \(index)"
        spec.append("\(root)/E/\(at)/\(at + 1) \(root + 1)/G/\(at + 1)/\(at + 1 + text.utf16.count) \(root + 1).0/T/\(at + 1)/\(at + 1 + text.utf16.count)")
        value += ["", text]
        raw += "\n" + text
        at += 1 + text.utf16.count
        root += 2
    }
    let start = at
    var children: [String] = []
    for index in 0..<items {
        let text = "Item \(index)"
        let path = "\(root).\(index)"
        children.append("\(path)/G/\(at)/\(at + 1 + text.utf16.count) \(path).0/G/\(at)/\(at + 1) \(path).0.0/Tg/\(at)/\(at + 1) "
                        + "\(path).1/G/\(at + 1)/\(at + 1 + text.utf16.count) \(path).1.0/T/\(at + 1)/\(at + 1 + text.utf16.count)")
        value += ["\u{2022}", text]
        raw += "\u{2022}" + text
        at += 1 + text.utf16.count
    }
    spec.append("\(root)/L/\(start)/\(at)")
    return (value.joined(separator: "\n"), raw, (spec + children).joined(separator: " "))
}

func testFieldDocument() {
    for (name, value, raw, spec) in documentTrees {
        for linear in [true, false] {
            let tree = fakeTree(spec, linear: linear)
            for proseMirror in [true, false] {
                let request = documentRequest(value, raw, caret: nil, proseMirror: proseMirror)
                let document = documentWalk(request, tree, roots: nil).document
                var apart = EmptyBlockScan<FakeNode>(budget: EmptyParagraphs.readBudget - 2, block: \.block,
                                                     offset: { node, end in end ? node.end : node.start })
                let plain = Array(MarkerText.plain(raw).utf16)
                let empty = plain.contains(10) ? apart.run(blocks: tree, plain: plain) : []
                let candidates = request.candidates(restoring: empty)
                var runs = UnreachableScan<FakeNode>(budget: UnreachableLines.readBudget - 2, block: \.block,
                                                     offset: { node, end in end ? node.end : node.start })
                let found = candidates.isEmpty ? UnreachableLines.Found(markers: [], chips: []) : runs.run(blocks: tree, candidates: candidates)
                precondition(document.emptyParagraphs == empty && document.candidates == candidates && document.found == found,
                             "\(name) linear=\(linear) proseMirror=\(proseMirror): one walk finds what the two scans did")
                precondition(document.reads <= apart.reads + runs.reads, "\(name): a node both read is read once")
            }
        }
    }
    let shared = documentWalk(documentRequest(dia1Value, dia1Raw, caret: nil), dia1Tree, roots: nil).document
    let offset: (FakeNode, Bool) -> Int? = { node, end in end ? node.end : node.start }
    var dia1Empty = EmptyBlockScan<FakeNode>(budget: EmptyParagraphs.readBudget, block: \.block, offset: offset)
    var dia1Runs = UnreachableScan<FakeNode>(budget: UnreachableLines.readBudget, block: \.block, offset: offset)
    _ = dia1Empty.run(blocks: dia1Tree, plain: Array(dia1Plain.utf16))
    _ = dia1Runs.run(blocks: dia1Tree, candidates: shared.candidates)
    precondition(shared.reads < dia1Empty.reads + dia1Runs.reads, "dia1's roots are read once, not twice")

    // The blank lines may spend only their share, first; the markers keep the rest of the budget.
    let crowded = blankListField(blanks: 120, items: 20)
    let crowdedWalk = documentWalk(documentRequest(crowded.value, crowded.raw, caret: nil, proseMirror: false),
                                   fakeTree(crowded.spec, linear: false), roots: nil).document
    precondition(crowdedWalk.emptyParagraphs == nil && crowdedWalk.exhausted == .emptyParagraphs
                 && crowdedWalk.found?.markers.count == 20, "past their share the blank lines stay AXValue's, and the markers fold")
    let fitting = blankListField(blanks: 20, items: 20)
    let fittingWalk = documentWalk(documentRequest(fitting.value, fitting.raw, caret: nil, proseMirror: false),
                                   fakeTree(fitting.spec, linear: false), roots: nil).document
    precondition(fittingWalk.emptyParagraphs?.count == 20 && fittingWalk.exhausted == [] && fittingWalk.found?.markers.count == 20)
    let long = blankListField(blanks: 0, items: 230)
    let longWalk = documentWalk(documentRequest(long.value, long.raw, caret: nil, proseMirror: false),
                                fakeTree(long.spec, linear: false), roots: nil, budget: FieldDocument.readBudget - 2).document
    var alone = UnreachableScan<FakeNode>(budget: UnreachableLines.readBudget - 2, block: \.block,
                                          offset: { node, end in end ? node.end : node.start })
    precondition(alone.run(blocks: fakeTree(long.spec, linear: false), candidates: longWalk.candidates) == nil && alone.exhausted)
    precondition(longWalk.found?.markers.count == 230, "a list past main's 1536 reads folds on what the blank lines left")
    let starved = documentWalk(documentRequest(long.value, long.raw, caret: nil, proseMirror: false),
                               fakeTree(long.spec, linear: false), roots: nil, budget: 300).document
    precondition(starved.found == nil && starved.exhausted == .found, "past the whole budget the markers stay lines")

    // A caret coming beside a text-less leaf asks the walk again only where no line was worth confirming.
    let leafRaw = "ab\u{FFFC}cd"
    let leafTree = fakeTree("0/G/0/4 0.0/T/0/2 0.1/I/2/2 0.2/T/2/4")
    func leafRequest(_ caret: Int) -> FieldDocument.Request { documentRequest("abcd", leafRaw, caret: caret, proseMirror: false) }
    let leafMemo = documentWalk(leafRequest(0), leafTree, roots: nil)
    precondition(leafMemo.document.candidates.isEmpty)
    precondition(leafMemo.carried(leafRequest(1), blocks: 1, roots: nil) == .success(leafMemo), "a caret beside no leaf changes nothing")
    precondition(leafMemo.carried(leafRequest(2), blocks: 1, roots: nil) == .failure(.candidates),
                 "beside the image it is a drawn caret's candidate")
    let leafWalked = documentWalk(leafRequest(2), leafTree, roots: nil)
    precondition(leafWalked.document.candidates.carets == [2] && leafWalked.carried(leafRequest(1), blocks: 1, roots: nil)
                 == .success(leafWalked), "once walked with candidates, a caret moving on keeps the memo, as main's did")
    precondition(documentRequest("one", "one").isIdle && !documentRequest("a\nb", "a\nb", folds: false).isIdle,
                 "a line of plain text asks for no walk, and a blank line for the blank lines' part alone")

    // The runs are the document: text tiles what the rest leave, every U+FFFC is a leaf, and what the model hides of the field's
    // text is its generated runs and its chips' labels, in order.
    for (name, value, raw, spec) in documentTrees {
        for linear in [true, false] {
            let document = documentWalk(documentRequest(value, raw, caret: nil), fakeTree(spec, linear: linear), roots: nil).document
            let plain = Array(MarkerText.plain(raw).utf16)
            let tiles = (document.runs.filter { !$0.range.isEmpty }.map(\.range)
                + (document.emptyParagraphs ?? []).map { $0..<($0 + 1) }).sorted { $0.lowerBound < $1.lowerBound }
            precondition(tiles.first?.lowerBound ?? 0 == 0 && tiles.last?.upperBound ?? 0 == plain.count
                         && zip(tiles, tiles.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound }, "\(name): the runs tile the text")
            let leaves = document.runs.filter { if case .leaf = $0.kind { true } else { false } }.count
            precondition(leaves == raw.utf16.filter { $0 == 0xFFFC }.count, "\(name): each object is a leaf")
            func text(_ range: Range<Int>) -> String { String(decoding: plain[range], as: UTF16.self) }
            let aligned = ParagraphBreaks(value: value, fieldText: MarkerText.plain(raw))!
            let restored = EmptyParagraphs.restore(value: value, fieldText: MarkerText.plain(raw), aligned: aligned,
                                                   found: document.emptyParagraphs!)
            let model = UnreachableLines.fold(text: restored?.text ?? value, breaks: restored?.breaks ?? aligned, raw: raw,
                                              found: document.found!)
            let hidden = model.breaks.hidden
            let generated = document.runs.compactMap { if case .generated = $0.kind { text($0.range) } else { nil } }.joined()
            let labels = document.runs.compactMap { if case .atom = $0.kind { text($0.range.dropFirst()) } else { nil } }.joined()
            precondition(hidden.filter { $0.kind == .prefix || $0.kind == .structure }.map(\.text).joined() == generated,
                         "\(name) linear=\(linear): the model hides the generated runs")
            precondition(hidden.filter { $0.kind == .atom }.map(\.text).joined() == labels, "\(name): and the chips' labels")
        }
    }
    let none = UnreachableLines.Found(markers: [], chips: [])
    let objectInside = FieldDocument(markers: "ab\u{FFFC}cd", emptyParagraphs: [], found: none).runs
    precondition(objectInside == [.init(range: 0..<2, kind: .text), .init(range: 2..<2, kind: .leaf(drawn: nil)),
                                  .init(range: 2..<4, kind: .text)], "an object inside text splits it: \(objectInside)")
    let stopInside = FieldDocument(markers: "abcd", emptyParagraphs: [], found: UnreachableLines.Found(markers: [], chips: [], joins: [2]))
    precondition(stopInside.runs == [.init(range: 0..<2, kind: .text), .init(range: 2..<2, kind: .stop(nil)),
                                     .init(range: 2..<4, kind: .text)] && stopInside.found?.joins == [2], "and so does a stop")
    let slackList = documentWalk(documentRequest(quillEmptyValue, quillEmptyRaw, caret: nil, proseMirror: false),
                                 fakeTree(quillEmptySpec, linear: false), roots: nil).document
    precondition(slackList.runs.map(\.kind) == [.generated(.marker), .text, .generated(.marker), .text, .generated(.marker), .text],
                 "field-model.md §5's Slack list: \(slackList.runs)")

    // The Sim walks Chrome 153's tree for plain paragraphs, as the runtime does.
    for paragraphs in [["L", "", "N"], ["", "", "L"], ["a", "", "bc", "", "", "d", ""]] {
        var host = blankSim(paragraphs, caret: 0)
        let snapshot = host.snapshot(anchor: nil).snapshot
        precondition(snapshot.text == paragraphs.joined(separator: "\n") && snapshot.holdsEmptyParagraphs, "\(paragraphs)")
    }
}
