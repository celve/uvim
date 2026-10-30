// softlash/LIN-2369 recorded these 2026-10-29: Chromium 153's own and CSS-drawn lists, Quill 1.3.7's (Slack's box) and Linear 1.32.4's.
// A `g` marks text with a negative ChromeAXNodeId, which the page generates.

let quillMixedValue = "top\n•one\n•two\nend"
let quillMixedRaw = "top•one•twoend"
let quillMixedSpec = """
0/G/0/3 0.0/T/0/3 1/L/3/11 1.0/G/3/7 1.0.0/G/3/4 1.0.0.0/Tg/3/4 1.0.1/T/4/7 1.1/G/7/11 1.1.0/G/7/8 1.1.0.0/Tg/7/8
1.1.1/T/8/11 2/G/11/14 2.0/T/11/14
"""
let quillEmptyValue = "•one\n•\n•three"
let quillEmptyRaw = "•one•\n•three"
let quillEmptySpec = """
0/L/0/12 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/T/1/4 0.1/G/4/6 0.1.0/G/4/5 0.1.0.0/Tg/4/5 0.2/G/6/12
0.2.0/G/6/7 0.2.0.0/Tg/6/7 0.2.1/T/7/12
"""
let quillNestedValue = "1.one\na.two\n2.three"
let quillNestedRaw = "1.onea.two2.three"
let quillNestedSpec = """
0/L/0/17 0.0/G/0/5 0.0.0/G/0/2 0.0.0.0/Tg/0/1 0.0.0.1/Tg/1/2 0.0.1/T/2/5 0.1/G/5/10 0.1.0/G/5/7 0.1.0.0/Tg/5/6
0.1.0.1/Tg/6/7 0.1.1/T/7/10 0.2/G/10/17 0.2.0/G/10/12 0.2.0.0/Tg/10/11 0.2.0.1/Tg/11/12 0.2.1/T/12/17
"""
let quillFirstemptyValue = "•\n•two\n•three"
let quillFirstemptyRaw = "•\n•two•three"
let quillFirstemptySpec = """
0/L/0/12 0.0/G/0/2 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.1/G/2/6 0.1.0/G/2/3 0.1.0.0/Tg/2/3 0.1.1/T/3/6 0.2/G/6/12
0.2.0/G/6/7 0.2.0.0/Tg/6/7 0.2.1/T/7/12
"""
let quillOrderedValue = "1.one\n2.two\n3.three"
let quillOrderedRaw = "1.one2.two3.three"
let quillOrderedSpec = """
0/L/0/17 0.0/G/0/5 0.0.0/G/0/2 0.0.0.0/Tg/0/1 0.0.0.1/Tg/1/2 0.0.1/T/2/5 0.1/G/5/10 0.1.0/G/5/7 0.1.0.0/Tg/5/6
0.1.0.1/Tg/6/7 0.1.1/T/7/10 0.2/G/10/17 0.2.0/G/10/12 0.2.0.0/Tg/10/11 0.2.0.1/Tg/11/12 0.2.1/T/12/17
"""
let chromiumNativeValue = "Native list opening paragraph.\n• First bullet\n• Second bullet\n◦ Nested circle\n• \n• After empty\nMiddle paragraph.\n9. Nine\n10. Ten is longer\na. Nested alpha\nDrawn lists follow.\n•Drawn bullet\n•\n1. Drawn one\n2. Drawn two\nClosing paragraph."
let chromiumNativeRaw = "Native list opening paragraph.• First bullet• Second bullet◦ Nested circle• \n• After emptyMiddle paragraph.9. Nine10. Ten is longera. Nested alphaDrawn lists follow.•Drawn bullet•\n1. Drawn one2. Drawn twoClosing paragraph."
let chromiumNativeSpec = """
0/G/0/30 0.0/T/0/30 1/L/30/90 1.0/G/30/44 1.0.0/M/30/32 1.0.1/T/32/44 1.1/G/44/74 1.1.0/M/44/46 1.1.1/T/46/59
1.1.2/L/59/74 1.1.2.0/G/59/74 1.1.2.0.0/M/59/61 1.1.2.0.1/T/61/74 1.2/G/74/77 1.2.0/M/74/76 1.3/G/77/90
1.3.0/M/77/79 1.3.1/T/79/90 2/G/90/107 2.0/T/90/107 3/L/107/146 3.0/G/107/114 3.0.0/M/107/110 3.0.1/T/110/114
3.1/G/114/146 3.1.0/M/114/118 3.1.1/T/118/131 3.1.2/L/131/146 3.1.2.0/G/131/146 3.1.2.0.0/M/131/134
3.1.2.0.1/T/134/146 4/G/146/165 4.0/T/146/165 5/L/165/180 5.0/G/165/178 5.0.0/Tg/165/166 5.0.1/T/166/178
5.1/G/178/180 5.1.0/Tg/178/179 6/L/180/204 6.0/G/180/192 6.0.0/Tg/180/181 6.0.1/Tg/181/183 6.0.2/T/183/192
6.1/G/192/204 6.1.0/Tg/192/193 6.1.1/Tg/193/195 6.1.2/T/195/204 7/G/204/222 7.0/T/204/222
"""
let linearListsValue = "Top paragraph of the marker probe.\n•\nBullet one\n◦\nNested bullet\n•\nDouble nested bullet\n•\nBullet two\nMiddle paragraph after the bullets.\n1.\nNumbered one\na.\nNested numbered one\ni.\nRoman numbered one\n2.\nNumbered two\nParagraph before a late start.\n9.\nNinth item\n10.\nTenth item\n\n\nTo-do open\n\n\nTo-do done\nLast paragraph."
let linearListsRaw = "Top paragraph of the marker probe.•Bullet one◦Nested bullet•Double nested bullet•Bullet twoMiddle paragraph after the bullets.1.Numbered onea.Nested numbered onei.Roman numbered one2.Numbered twoParagraph before a late start.9.Ninth item10.Tenth item\u{FFFC}\u{FFFC}To-do open\u{FFFC}\u{FFFC}To-do doneLast paragraph."
let linearListsSpec = """
0/G/0/34 0.0/T/0/34 1/L/34/91 1.0/G/34/80 1.0.0/G/34/35 1.0.0.0/Tg/34/35 1.0.1/G/35/45 1.0.1.0/T/35/45 1.0.2/L/45/80
1.0.2.0/G/45/80 1.0.2.0.0/G/45/46 1.0.2.0.0.0/Tg/45/46 1.0.2.0.1/G/46/59 1.0.2.0.1.0/T/46/59 1.0.2.0.2/L/59/80
1.0.2.0.2.0/G/59/80 1.0.2.0.2.0.0/G/59/60 1.0.2.0.2.0.0.0/Tg/59/60 1.0.2.0.2.0.1/G/60/80 1.0.2.0.2.0.1.0/T/60/80
1.1/G/80/91 1.1.0/G/80/81 1.1.0.0/Tg/80/81 1.1.1/G/81/91 1.1.1.0/T/81/91 2/G/91/126 2.0/T/91/126 3/L/126/195
3.0/G/126/181 3.0.0/G/126/128 3.0.0.0/Tg/126/127 3.0.0.1/Tg/127/128 3.0.1/G/128/140 3.0.1.0/T/128/140
3.0.2/L/140/181 3.0.2.0/G/140/181 3.0.2.0.0/G/140/142 3.0.2.0.0.0/Tg/140/141 3.0.2.0.0.1/Tg/141/142
3.0.2.0.1/G/142/161 3.0.2.0.1.0/T/142/161 3.0.2.0.2/L/161/181 3.0.2.0.2.0/G/161/181 3.0.2.0.2.0.0/G/161/163
3.0.2.0.2.0.0.0/Tg/161/162 3.0.2.0.2.0.0.1/Tg/162/163 3.0.2.0.2.0.1/G/163/181 3.0.2.0.2.0.1.0/T/163/181
3.1/G/181/195 3.1.0/G/181/183 3.1.0.0/Tg/181/182 3.1.0.1/Tg/182/183 3.1.1/G/183/195 3.1.1.0/T/183/195 4/G/195/225
4.0/T/195/225 5/L/225/250 5.0/G/225/237 5.0.0/G/225/227 5.0.0.0/Tg/225/226 5.0.0.1/Tg/226/227 5.0.1/G/227/237
5.0.1.0/T/227/237 5.1/G/237/250 5.1.0/G/237/240 5.1.0.0/Tg/237/239 5.1.0.1/Tg/239/240 5.1.1/G/240/250
5.1.1.0/T/240/250 6/L/250/270 6.0/G/250/260 6.0.0/G/250/250 6.0.0.0/I/250/250 6.0.0.1/C/250/250 6.0.1/G/250/260
6.0.1.0/G/250/260 6.0.1.0.0/T/250/260 6.1/G/260/270 6.1.0/G/260/260 6.1.0.0/I/260/260 6.1.0.1/C/260/260
6.1.1/G/260/270 6.1.1.0/G/260/270 6.1.1.0.0/T/260/270 7/G/270/285 7.0/T/270/285
"""
let linearExample4Value = "•\na\n1.\nb\nZq end."
let linearExample4Raw = "•a1.bZq end."
let linearExample4Spec = """
0/L/0/2 0.0/G/0/2 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/G/1/2 0.0.1.0/T/1/2 1/L/2/5 1.0/G/2/5 1.0.0/G/2/4 1.0.0.0/Tg/2/3
1.0.0.1/Tg/3/4 1.0.1/G/4/5 1.0.1.0/T/4/5 2/G/5/12 2.0/T/5/12
"""

func testGeneratedMarkers() {
    // A list item's leading generated text is its marker, as long as the tree has it, whichever editor draws it (LIN-2372).
    let recorded: [(String, String, String, Bool, String)] = [
        ("chromiumNative", chromiumNativeValue, chromiumNativeRaw, false, "Native list opening paragraph.\nFirst bullet\nSecond bullet\nNested circle\n\nAfter empty\nMiddle paragraph.\nNine\nTen is longer\nNested alpha\nDrawn lists follow.\nDrawn bullet\n\nDrawn one\nDrawn two\nClosing paragraph."),
        ("quillMixed", quillMixedValue, quillMixedRaw, false, "top\none\ntwo\nend"),
        ("quillEmpty", quillEmptyValue, quillEmptyRaw, false, "one\n\nthree"),
        ("quillNested", quillNestedValue, quillNestedRaw, false, "one\ntwo\nthree"),
        ("quillFirstempty", quillFirstemptyValue, quillFirstemptyRaw, false, "\ntwo\nthree"),
        ("quillOrdered", quillOrderedValue, quillOrderedRaw, false, "one\ntwo\nthree"),
        ("linearLists", linearListsValue, linearListsRaw, true, "Top paragraph of the marker probe.\nBullet one\nNested bullet\nDouble nested bullet\nBullet two\nMiddle paragraph after the bullets.\nNumbered one\nNested numbered one\nRoman numbered one\nNumbered two\nParagraph before a late start.\nNinth item\nTenth item\nTo-do open\nTo-do done\nLast paragraph."),
        ("linearExample4", linearExample4Value, linearExample4Raw, true, "a\nb\nZq end."),
    ]
    let specs = [chromiumNativeSpec, quillMixedSpec, quillEmptySpec, quillNestedSpec, quillFirstemptySpec, quillOrderedSpec,
                 linearListsSpec, linearExample4Spec]
    for ((name, value, raw, proseMirror, text), spec) in zip(recorded, specs) {
        let model = folded(value, raw, fakeTree(spec, linear: proseMirror), proseMirror: proseMirror)
        precondition(model.text == text && roundTrips(model), "\(name): \(model.text.debugDescription)")
    }

    let unfamiliar = folded("\u{25B8}one\na)two", "\u{25B8}onea)two",
                            fakeTree("0/L/0/9 0.0/G/0/4 0.0.0/Tg/0/1 0.0.1/T/1/4 0.1/G/4/9 0.1.0/Tg/4/5 0.1.1/Tg/5/6 0.1.2/T/6/9",
                                     linear: false), proseMirror: false)
    precondition(unfamiliar.text == "one\ntwo" && roundTrips(unfamiliar), "a shape no list of bullets names, and a two-node counter")

    let typed = folded("\u{2022}typed\n\u{2022}\u{2022}x\n- y\n\u{25B8} z", "\u{2022}typed\u{2022}\u{2022}x- y\u{25B8} z", fakeTree("""
    0/G/0/6 0.0/T/0/6 1/L/6/9 1.0/G/6/9 1.0.0/Tg/6/7 1.0.1/T/7/9 2/G/9/12 2.0/T/9/12 3/L/12/15 3.0/G/12/15 3.0.0/T/12/15
    """, linear: false), proseMirror: false)
    precondition(typed.text == "\u{2022}typed\n\u{2022}x\n- y\n\u{25B8} z" && roundTrips(typed), "typed bullets stay text: \(typed.text)")
    let trailing = fakeTree("0/L/0/3 0.0/G/0/3 0.0.0/T/0/1 0.0.1/Tg/1/2 0.0.2/T/2/3", linear: false)
    precondition(unreachableScanned(trailing, UnreachableLines.Candidates(markers: [0..<1], chips: []))?.markers == [],
                 "generated text after the item's own is no marker")
    let column = fakeTree("0/L/0/3 0.0/G/0/3 0.0.0/Ug/0/1 0.0.1/T/1/3", linear: false)
    precondition(unreachableScanned(column, UnreachableLines.Candidates(markers: [0..<1], chips: []))?.markers == [],
                 "nor is a node Chromium makes itself, which is no text")

    let symbols = folded("+one\n\u{1F600}two\n\u{00B7}three", "+one\u{1F600}two\u{00B7}three", fakeTree("""
    0/L/0/14 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/T/1/4 0.1/G/4/9 0.1.0/G/4/6 0.1.0.0/Tg/4/6 0.1.1/T/6/9 0.2/G/9/15
    0.2.0/G/9/10 0.2.0.0/Tg/9/10 0.2.1/T/10/15
    """, linear: false), proseMirror: false)
    precondition(symbols.text == "one\ntwo\nthree" && roundTrips(symbols), "a plus, an emoji and a middle dot: \(symbols.text)")
    let typedSymbols = folded("+one\n\u{1F600}two", "+one\u{1F600}two",
                              fakeTree("0/G/0/4 0.0/T/0/4 1/G/4/9 1.0/T/4/9", linear: false), proseMirror: false)
    precondition(typedSymbols.text == "+one\n\u{1F600}two", "and typed, they stay text")

    // As many Quill items as #81's walk confirmed within its budget, each `::before` group read through to its text.
    let items = 190
    let long = fakeTree((0..<items).map { i in
        "0.\(i)/G/\(i * 5)/\(i * 5 + 5) 0.\(i).0/G/\(i * 5)/\(i * 5 + 1) 0.\(i).0.0/Tg/\(i * 5)/\(i * 5 + 1) 0.\(i).1/T/\(i * 5 + 1)/\(i * 5 + 5)"
    }.joined(separator: " ") + " 0/L/0/\(items * 5)", linear: false)
    let longText = Array(repeating: "\u{2022}item", count: items).joined(separator: "\n")
    let longFound = unreachableScanned(long, UnreachableLines.candidates(
        text: longText, breaks: ParagraphBreaks(offsets: (1..<items).map { $0 * 6 - 1 })
    ))
    precondition(longFound?.markers == (0..<items).map { $0 * 5..<$0 * 5 + 1 }, "\(items) markers within the budget")

    let lastEmpty = folded("\u{2022}one\n\u{2022}\n", "\u{2022}one\u{2022}\n", fakeTree(
        "0/L/0/6 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/T/1/4 0.1/G/4/6 0.1.0/G/4/5 0.1.0.0/Tg/4/5", linear: false
    ), proseMirror: false)
    precondition(lastEmpty.text == "one\n" && roundTrips(lastEmpty), "an empty last item: \(lastEmpty.text.debugDescription)")

    let failing = fakeTree(quillEmptySpec, linear: false)
    failing[0].children[1].children[0].fails = true
    precondition(unreachableScanned(failing, UnreachableLines.candidates(text: "\u{2022}one\n\u{2022}\n\u{2022}three",
                                                                         breaks: ParagraphBreaks(offsets: [4]))) == nil,
                 "a failed read of a marker's group fails the walk")
}
