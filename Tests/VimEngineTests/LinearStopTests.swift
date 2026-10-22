// MARK: - Linear's stops beside tables, sections, rules and nested blocks (LIN-1780)

let stopsProfile = adding([.wordKeys], to: keyProfile)
/// The plan's keys for `keys` from the start of the line holding `line` in `model`.
func linearKeys(_ keys: String, _ line: String, _ model: UnreachableLines.Model, profile: CapabilityProfile = stopsProfile) -> [Chord] {
    chords(webPhysical(keys, text: model.text, caret: lineStart(of: line, in: model.text), profile: profile, breaks: model.breaks))
}
func linearFound(_ value: String, _ raw: String, _ spec: String) -> UnreachableLines.Found? {
    let plain = MarkerText.plain(raw)
    let breaks = ParagraphBreaks(value: value, fieldText: plain)!
    let tree = fakeTree(spec)
    let restored = EmptyParagraphs.restore(value: value, fieldText: plain, aligned: breaks, found: scanned(tree, plain)!)!
    return unreachableScanned(tree, UnreachableLines.candidates(text: restored.text, breaks: restored.breaks, raw: raw, proseMirror: true))
}

// softlash/LIN-1780 scripts/live/evidence/tree-a.jsonl (Linear desktop 1.32.4): tables, rules and blocks nested in a quote.
let tablesValue = "Probe A: plain opening paragraph alpha.\nParagraph before table bravo.\nCell one\nCell two\nCell three\nCell four\n\n\nParagraph after table charlie.\n\u{2022}\nBullet before table delta\nCell five\nCell six\nCell seven\nCell eight\n\n\n\u{2022}\nBullet after table echo\nCSS\n\n\ncode before table foxtrot\nCell nine\nCell ten\nCell eleven\nCell twelve\n\n\nQuote after table golf\nParagraph before rule hotel.\n\nParagraph after rule india.\n\u{2022}\nBullet before rule juliet\n\nQuote after rule kilo\n\n\nParagraph after two rules lima.\nQuote mike\n\u{2022}\nBullet in quote november\n1.\nNumbered in quote oscar\nNested quote papa\nQuote paragraph quebec\nPlain closing paragraph romeo."
let tablesRaw = "Probe A: plain opening paragraph alpha.Paragraph before table bravo.Cell oneCell twoCell threeCell four\u{FFFC}\u{FFFC}Paragraph after table charlie.\u{2022}Bullet before table deltaCell fiveCell sixCell sevenCell eight\u{FFFC}\u{FFFC}\u{2022}Bullet after table echoCSS\u{FFFC}\u{FFFC}code before table foxtrotCell nineCell tenCell elevenCell twelve\u{FFFC}\u{FFFC}Quote after table golfParagraph before rule hotel.\u{FFFC}Paragraph after rule india.\u{2022}Bullet before rule juliet\u{FFFC}Quote after rule kilo\u{FFFC}\u{FFFC}Paragraph after two rules lima.Quote mike\u{2022}Bullet in quote november1.Numbered in quote oscarNested quote papaQuote paragraph quebecPlain closing paragraph romeo."
let tablesSpec = """
0/G/0/39 0.0/T/0/39 1/G/39/68 1.0/T/39/68 2/X/68/103 2.0/G/68/103 2.0.0/Y/68/103 2.0.0.0/O/68/84 2.0.0.0.0/G/68/76
2.0.0.0.0.0/G/68/76 2.0.0.0.0.0.0/G/68/76 2.0.0.0.0.0.0.0/T/68/76 2.0.0.0.1/G/76/84 2.0.0.0.1.0/G/76/84
2.0.0.0.1.0.0/G/76/84 2.0.0.0.1.0.0.0/T/76/84 2.0.0.1/O/84/103 2.0.0.1.0/G/84/94 2.0.0.1.0.0/G/84/94
2.0.0.1.0.0.0/G/84/94 2.0.0.1.0.0.0.0/T/84/94 2.0.0.1.1/G/94/103 2.0.0.1.1.0/G/94/103 2.0.0.1.1.0.0/G/94/103
2.0.0.1.1.0.0.0/T/94/103 2.0.0.2/U/9000/9000 2.0.0.3/U/9000/9000 2.0.0.4/G/9000/9000 2.1/G/103/103 3/G/103/133
3.0/T/103/133 4/L/133/159 4.0/G/133/159 4.0.0/G/133/134 4.0.0.0/T/133/134 4.0.1/G/134/159 4.0.1.0/T/134/159
5/X/159/196 5.0/G/159/196 5.0.0/Y/159/196 5.0.0.0/O/159/176 5.0.0.0.0/G/159/168 5.0.0.0.0.0/G/159/168
5.0.0.0.0.0.0/G/159/168 5.0.0.0.0.0.0.0/T/159/168 5.0.0.0.1/G/168/176 5.0.0.0.1.0/G/168/176 5.0.0.0.1.0.0/G/168/176
5.0.0.0.1.0.0.0/T/168/176 5.0.0.1/O/176/196 5.0.0.1.0/G/176/186 5.0.0.1.0.0/G/176/186 5.0.0.1.0.0.0/G/176/186
5.0.0.1.0.0.0.0/T/176/186 5.0.0.1.1/G/186/196 5.0.0.1.1.0/G/186/196 5.0.0.1.1.0.0/G/186/196 5.0.0.1.1.0.0.0/T/186/196
5.0.0.2/U/9000/9000 5.0.0.3/U/9000/9000 5.0.0.4/G/9000/9000 5.1/G/196/196 6/L/196/220 6.0/G/196/220 6.0.0/G/196/197
6.0.0.0/T/196/197 6.0.1/G/197/220 6.0.1.0/T/197/220 7/B/220/248 7.0/N/220/223 7.1/D/223/248 7.1.0/T/223/227
7.1.1/T/227/235 7.1.2/T/235/240 7.1.3/T/240/248 8/X/248/287 8.0/G/248/287 8.0.0/Y/248/287 8.0.0.0/O/248/265
8.0.0.0.0/G/248/257 8.0.0.0.0.0/G/248/257 8.0.0.0.0.0.0/G/248/257 8.0.0.0.0.0.0.0/T/248/257 8.0.0.0.1/G/257/265
8.0.0.0.1.0/G/257/265 8.0.0.0.1.0.0/G/257/265 8.0.0.0.1.0.0.0/T/257/265 8.0.0.1/O/265/287 8.0.0.1.0/G/265/276
8.0.0.1.0.0/G/265/276 8.0.0.1.0.0.0/G/265/276 8.0.0.1.0.0.0.0/T/265/276 8.0.0.1.1/G/276/287 8.0.0.1.1.0/G/276/287
8.0.0.1.1.0.0/G/276/287 8.0.0.1.1.0.0.0/T/276/287 8.0.0.2/U/9000/9000 8.0.0.3/U/9000/9000 8.0.0.4/G/9000/9000
8.1/G/287/287 9/Q/287/309 9.0/G/287/309/1 9.0.0/T/287/309/1 10/G/309/337 10.0/T/309/337 11/R/337/337 12/G/337/364
12.0/T/337/364 13/L/364/390 13.0/G/364/390 13.0.0/G/364/365 13.0.0.0/T/364/365 13.0.1/G/365/390 13.0.1.0/T/365/390
14/R/390/390 15/Q/390/411 15.0/G/390/411/1 15.0.0/T/390/411/1 16/R/411/411 17/R/411/411 18/G/411/442 18.0/T/411/442
19/Q/442/541 19.0/G/442/452/1 19.0.0/T/442/452/1 19.1/L/452/477/1 19.1.0/G/452/477/1 19.1.0.0/G/452/453/1
19.1.0.0.0/T/452/453/1 19.1.0.1/G/453/477/1 19.1.0.1.0/T/453/477/1 19.2/L/477/502/1 19.2.0/G/477/502/1
19.2.0.0/G/477/479/1 19.2.0.0.0/T/477/478/1 19.2.0.0.1/T/478/479/1 19.2.0.1/G/479/502/1 19.2.0.1.0/T/479/502/1
19.3/Q/502/519/2 19.3.0/G/502/519/2 19.3.0.0/T/502/519/2 19.4/G/519/541/1 19.4.0/T/519/541/1 20/G/541/571
20.0/T/541/571
"""

let tablesModel = folded(tablesValue, tablesRaw, fakeTree(tablesSpec))

// In a table the length goes unchecked: the table's controls come and go with how the caret got there.
func settledLengths(_ plan: PhysicalPlan) -> [Int?] {
    plan.steps.compactMap { if case .settle(let expectation) = $0 { return .some(expectation.length) } else { return nil } }
}
func tablesPlan(_ keys: String, _ line: String) -> PhysicalPlan {
    webPhysical(keys, text: tablesModel.text, caret: lineStart(of: line, in: tablesModel.text), profile: stopsProfile,
                breaks: tablesModel.breaks)
}

let openValue = "Probe B: plain opening paragraph alpha.\n\u{2022}\nBullet before section bravo\n\nSection title charlie\nSection body delta\n\u{2022}\nBullet after section echo\n\nSection with list foxtrot\n\u{2022}\nBullet in section golf\nQuote in section hotel\nParagraph after section india.\n\nSection after paragraph juliet\nBody kilo\nQuote after section lima\nPlain closing paragraph mike."
let openRaw = "Probe B: plain opening paragraph alpha.\u{2022}Bullet before section bravo\u{FFFC}Section title charlieSection body delta\u{2022}Bullet after section echo\u{FFFC}Section with list foxtrot\u{2022}Bullet in section golfQuote in section hotelParagraph after section india.\u{FFFC}Section after paragraph julietBody kiloQuote after section limaPlain closing paragraph mike."
let openSpec = """
0/G/0/39 0.0/T/0/39 1/L/39/67 1.0/G/39/67 1.0.0/G/39/40 1.0.0.0/T/39/40 1.0.1/G/40/67 1.0.1.0/T/40/67 2/Z/67/106
2.0/G/67/88 2.0.0/G/67/67 2.0.1/G/67/88 2.0.1.0/T/67/88 2.1/G/88/106 2.1.0/T/88/106 3/L/106/132 3.0/G/106/132
3.0.0/G/106/107 3.0.0.0/T/106/107 3.0.1/G/107/132 3.0.1.0/T/107/132 4/Z/132/202 4.0/G/132/157 4.0.0/G/132/132
4.0.1/G/132/157 4.0.1.0/T/132/157 4.1/L/157/180 4.1.0/G/157/180 4.1.0.0/G/157/158 4.1.0.0.0/T/157/158
4.1.0.1/G/158/180 4.1.0.1.0/T/158/180 4.2/Q/180/202 4.2.0/G/180/202/1 4.2.0.0/T/180/202/1 5/G/202/232 5.0/T/202/232
6/Z/232/271 6.0/G/232/262 6.0.0/G/232/232 6.0.1/G/232/262 6.0.1.0/T/232/262 6.1/G/262/271 6.1.0/T/262/271 7/Q/271/295
7.0/G/271/295/1 7.0.0/T/271/295/1 8/G/295/324 8.0/T/295/324
"""
let openFound = linearFound(openValue, openRaw, openSpec)!

// A paragraph inside a section made a quote keeps every root and the text, so the containers' children witness it.
let openTree = fakeTree(openSpec)
func openWitness(_ children: @escaping (FakeNode) -> [FakeNode]?, roots: [FakeNode] = openTree) -> Int? {
    UnreachableLines.witness(roots: roots, containers: openFound.containers, children: children, identity: ObjectIdentifier.init)
}

func testLinearStops() {
    let tablesFound = linearFound(tablesValue, tablesRaw, tablesSpec)!
    precondition(tablesFound.tables == [.init(range: 68..<103, lastRow: 84), .init(range: 159..<196, lastRow: 176),
                                        .init(range: 248..<287, lastRow: 265)], "each table and its last row, past its columns")
    precondition(tablesFound.stops == [
        .init(at: 159, kind: .boxedGap), .init(at: 196, kind: .boxedGap), .init(at: 248, kind: .boxedGap), .init(at: 287, kind: .boxedGap),
        .init(at: 337, kind: .rule), .init(at: 390, kind: .rule), .init(at: 411, kind: .rule), .init(at: 411, kind: .ruleGap),
        .init(at: 411, kind: .rule),
    ], "a stop beside a table only where a list, code block or quote is on its other side, and every rule's")
    precondition(tablesFound.joins == [220, 477, 502] && tablesFound.controls == [220..<223], "the stops inside a quote too")

    precondition(tablesModel.breaks.lastRows == Set(["Cell three", "Cell seven", "Cell eleven"].map { lineStart(of: $0, in: tablesModel.text) })
                 && tablesModel.breaks.cells.count == 12 && roundTrips(tablesModel))
    // The plans the key lane ran in Linear, every crossing right (softlash/LIN-1780 scripts/live/evidence/sweeps).
    precondition(linearKeys("j", "Paragraph before table bravo", tablesModel) == [.paragraphEnd, .right], "no stop beside a paragraph")
    precondition(linearKeys("j", "Bullet before table delta", tablesModel) == [.paragraphEnd, .right, .right], "→ → into a table")
    precondition(linearKeys("j", "Cell seven", tablesModel) == [.paragraphEnd, .wordRight]
                 && linearKeys("j", "Cell eight", tablesModel) == [.paragraphEnd, .wordRight], "⌥→ to the next cell, and out past the stop")
    precondition(linearKeys("k", "Cell eight", tablesModel) == [.paragraphStart, .left, .paragraphStart])
    precondition(linearKeys("k", "Bullet after table echo", tablesModel)
                 == [.paragraphStart, .up, .up, .paragraphStart, .paragraphEnd, .wordRight], "← skips the table, ↑ enters its last row")
    precondition(linearKeys("k", "Paragraph after table charlie", tablesModel)
                 == [.paragraphStart, .up, .paragraphStart, .paragraphEnd, .wordRight])
    precondition(linearKeys("2k", "Bullet after table echo", tablesModel) == [.paragraphStart, .up, .up, .paragraphStart]
                 && linearKeys("3k", "Bullet after table echo", tablesModel)
                 == [.paragraphStart, .up, .up, .paragraphStart, .left, .paragraphStart])
    precondition(linearKeys("j", "Paragraph before rule hotel", tablesModel) == [.paragraphEnd, .right, .right]
                 && linearKeys("k", "Paragraph after rule india", tablesModel) == [.paragraphStart, .left, .left, .paragraphStart],
                 "a rule is one more arrow either way")
    precondition(linearKeys("j", "Quote after rule kilo", tablesModel) == [.paragraphEnd] + Array(repeating: .right, count: 4)
                 && linearKeys("k", "Paragraph after two rules lima", tablesModel)
                 == [.paragraphStart] + Array(repeating: .left, count: 4) + [.paragraphStart], "two rules and the stop between them")
    precondition(linearKeys("j", "Bullet in quote november", tablesModel) == [.paragraphEnd, .selectRight, .right]
                 && linearKeys("j", "Numbered in quote oscar", tablesModel) == [.paragraphEnd, .selectRight, .right])

    precondition(settledLengths(tablesPlan("j", "Bullet before table delta")).last == .some(nil)
                 && settledLengths(tablesPlan("j", "Cell five")).allSatisfy { $0 == nil }
                 && settledLengths(tablesPlan("j", "Cell eight")).last == .some(nil)
                 && settledLengths(tablesPlan("j", "Paragraph before table bravo")).first != .some(nil))

    // softlash/LIN-1780 scripts/live/evidence/tree-c.jsonl: rules beside code blocks and tables, two tables, a section, a to-do.
    let combosValue = "Probe C: plain opening paragraph alpha.\nCSS\n\n\ncode before rule bravo\n\nCSS\n\n\ncode after rule charlie\nQuote before rule delta\n\nCell one\nCell two\nCell three\nCell four\n\n\nCell five\nCell six\nCell seven\nCell eight\n\n\n\n\n\u{2022}\nBullet after two rules echo\n\nSection foxtrot\nCell nine\nCell ten\nCell eleven\nCell twelve\n\n\n\n\nTodo after table hotel\nPlain closing paragraph india."
    let combosRaw = "Probe C: plain opening paragraph alpha.CSS\u{FFFC}\u{FFFC}code before rule bravo\u{FFFC}CSS\u{FFFC}\u{FFFC}code after rule charlieQuote before rule delta\u{FFFC}Cell oneCell twoCell threeCell four\u{FFFC}\u{FFFC}Cell fiveCell sixCell sevenCell eight\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}\u{2022}Bullet after two rules echo\u{FFFC}Section foxtrotCell nineCell tenCell elevenCell twelve\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}Todo after table hotelPlain closing paragraph india."
    let combosSpec = """
    0/G/0/39 0.0/T/0/39 1/B/39/64 1.0/N/39/42 1.1/D/42/64 1.1.0/T/42/46 1.1.1/T/46/64 2/R/64/64 3/B/64/90 3.0/N/64/67
    3.1/D/67/90 3.1.0/T/67/71 3.1.1/T/71/90 4/Q/90/113 4.0/G/90/113/1 4.0.0/T/90/113/1 5/R/113/113 6/X/113/148
    6.0/G/113/148 6.0.0/Y/113/148 6.0.0.0/O/113/129 6.0.0.0.0/G/113/121 6.0.0.0.0.0/G/113/121 6.0.0.0.0.0.0/G/113/121
    6.0.0.0.0.0.0.0/T/113/121 6.0.0.0.1/G/121/129 6.0.0.0.1.0/G/121/129 6.0.0.0.1.0.0/G/121/129 6.0.0.0.1.0.0.0/T/121/129
    6.0.0.1/O/129/148 6.0.0.1.0/G/129/139 6.0.0.1.0.0/G/129/139 6.0.0.1.0.0.0/G/129/139 6.0.0.1.0.0.0.0/T/129/139
    6.0.0.1.1/G/139/148 6.0.0.1.1.0/G/139/148 6.0.0.1.1.0.0/G/139/148 6.0.0.1.1.0.0.0/T/139/148 6.0.0.2/U/9000/9000
    6.0.0.3/U/9000/9000 6.0.0.4/G/9000/9000 6.1/G/148/148 7/X/148/185 7.0/G/148/185 7.0.0/Y/148/185 7.0.0.0/O/148/165
    7.0.0.0.0/G/148/157 7.0.0.0.0.0/G/148/157 7.0.0.0.0.0.0/G/148/157 7.0.0.0.0.0.0.0/T/148/157 7.0.0.0.1/G/157/165
    7.0.0.0.1.0/G/157/165 7.0.0.0.1.0.0/G/157/165 7.0.0.0.1.0.0.0/T/157/165 7.0.0.1/O/165/185 7.0.0.1.0/G/165/175
    7.0.0.1.0.0/G/165/175 7.0.0.1.0.0.0/G/165/175 7.0.0.1.0.0.0.0/T/165/175 7.0.0.1.1/G/175/185 7.0.0.1.1.0/G/175/185
    7.0.0.1.1.0.0/G/175/185 7.0.0.1.1.0.0.0/T/175/185 7.0.0.2/U/9000/9000 7.0.0.3/U/9000/9000 7.0.0.4/G/9000/9000
    7.1/G/185/185 8/R/185/185 9/R/185/185 10/L/185/213 10.0/G/185/213 10.0.0/G/185/186 10.0.0.0/T/185/186 10.0.1/G/186/213
    10.0.1.0/T/186/213 11/Z/213/228 11.0/G/213/228 11.0.0/G/213/213 11.0.1/G/213/228 11.0.1.0/T/213/228 12/X/228/267
    12.0/G/228/267 12.0.0/Y/228/267 12.0.0.0/O/228/245 12.0.0.0.0/G/228/237 12.0.0.0.0.0/G/228/237
    12.0.0.0.0.0.0/G/228/237 12.0.0.0.0.0.0.0/T/228/237 12.0.0.0.1/G/237/245 12.0.0.0.1.0/G/237/245
    12.0.0.0.1.0.0/G/237/245 12.0.0.0.1.0.0.0/T/237/245 12.0.0.1/O/245/267 12.0.0.1.0/G/245/256 12.0.0.1.0.0/G/245/256
    12.0.0.1.0.0.0/G/245/256 12.0.0.1.0.0.0.0/T/245/256 12.0.0.1.1/G/256/267 12.0.0.1.1.0/G/256/267
    12.0.0.1.1.0.0/G/256/267 12.0.0.1.1.0.0.0/T/256/267 12.0.0.2/U/9000/9000 12.0.0.3/U/9000/9000 12.0.0.4/G/9000/9000
    12.1/G/267/267 13/L/267/289 13.0/G/267/289 13.0.0/G/267/267 13.0.0.0/I/267/267 13.0.0.1/C/267/267 13.0.1/G/267/289
    13.0.1.0/G/267/289 13.0.1.0.0/T/267/289 14/G/289/319 14.0/T/289/319
    """
    let combosFound = linearFound(combosValue, combosRaw, combosSpec)!
    precondition(combosFound.stops == [
        .init(at: 64, kind: .rule), .init(at: 113, kind: .rule), .init(at: 113, kind: .boxedGap), .init(at: 148, kind: .boxedGap),
        .init(at: 185, kind: .backGap), .init(at: 185, kind: .rule), .init(at: 185, kind: .ruleGap), .init(at: 185, kind: .rule),
        .init(at: 228, kind: .upGap), .init(at: 267, kind: .boxedGap),
    ] && combosFound.joins == [90, 213])
    let combosModel = folded(combosValue, combosRaw, fakeTree(combosSpec))
    precondition(linearKeys("j", "Quote before rule delta", combosModel) == [.paragraphEnd, .right, .right, .right], "rule, stop, cell")
    precondition(linearKeys("j", "Cell four", combosModel) == [.paragraphEnd, .wordRight], "into the next table")
    precondition(linearKeys("j", "Cell eight", combosModel) == [.paragraphEnd] + Array(repeating: .right, count: 4),
                 "→ into rules after a table skips the stop between them")
    precondition(linearKeys("k", "Bullet after two rules echo", combosModel)
                 == [.paragraphStart] + Array(repeating: .left, count: 5) + [.paragraphStart], "← meets it")
    precondition(linearKeys("j", "Section foxtrot", combosModel) == [.paragraphEnd, .right], "no stop below a collapsed title")
    precondition(linearKeys("k", "Todo after table hotel", combosModel)
                 == [.paragraphStart, .up, .up, .paragraphStart, .paragraphEnd, .wordRight])

    // softlash/LIN-1780 scripts/live/evidence/tree-b-initial.jsonl and tree-b-open.jsonl: the same sections, collapsed and open.
    let collapsedValue = "Probe B: plain opening paragraph alpha.\n\u{2022}\nBullet before section bravo\n\nSection title charlie\n\u{2022}\nBullet after section echo\n\nSection with list foxtrot\nParagraph after section india.\n\nSection after paragraph juliet\nQuote after section lima\nPlain closing paragraph mike."
    let collapsedRaw = "Probe B: plain opening paragraph alpha.\u{2022}Bullet before section bravo\u{FFFC}Section title charlie\u{2022}Bullet after section echo\u{FFFC}Section with list foxtrotParagraph after section india.\u{FFFC}Section after paragraph julietQuote after section limaPlain closing paragraph mike."
    let collapsedSpec = """
    0/G/0/39 0.0/T/0/39 1/L/39/67 1.0/G/39/67 1.0.0/G/39/40 1.0.0.0/T/39/40 1.0.1/G/40/67 1.0.1.0/T/40/67 2/Z/67/88
    2.0/G/67/88 2.0.0/G/67/67 2.0.1/G/67/88 2.0.1.0/T/67/88 3/L/88/114 3.0/G/88/114 3.0.0/G/88/89 3.0.0.0/T/88/89
    3.0.1/G/89/114 3.0.1.0/T/89/114 4/Z/114/139 4.0/G/114/139 4.0.0/G/114/114 4.0.1/G/114/139 4.0.1.0/T/114/139
    5/G/139/169 5.0/T/139/169 6/Z/169/199 6.0/G/169/199 6.0.0/G/169/169 6.0.1/G/169/199 6.0.1.0/T/169/199 7/Q/199/223
    7.0/G/199/223/1 7.0.0/T/199/223/1 8/G/223/252 8.0/T/223/252
    """
    let collapsedFound = linearFound(collapsedValue, collapsedRaw, collapsedSpec)!
    precondition(collapsedFound.joins == [67, 114] && collapsedFound.stops == [.init(at: 88, kind: .upGap), .init(at: 199, kind: .upGap)],
                 "after a collapsed section only ↑ stops")
    let collapsedModel = folded(collapsedValue, collapsedRaw, fakeTree(collapsedSpec))
    precondition(linearKeys("j", "Section title charlie", collapsedModel) == [.paragraphEnd, .right]
                 && linearKeys("j", "Bullet before section bravo", collapsedModel) == [.paragraphEnd, .right, .right])
    precondition(linearKeys("k", "Bullet after section echo", collapsedModel, profile: noLineKeys).prefix(3) == [.up, .up, .lineStart]
                 && linearKeys("k", "Paragraph after section india", collapsedModel, profile: noLineKeys).prefix(2) == [.up, .lineStart])

    precondition(openFound.joins == [67, 106, 132, 180, 271] && openFound.stops.isEmpty, "an open section stops as a quote does")
    let openModel = folded(openValue, openRaw, fakeTree(openSpec))
    precondition(linearKeys("j", "Section body delta", openModel) == [.paragraphEnd, .selectRight, .right]
                 && linearKeys("j", "Bullet in section golf", openModel) == [.paragraphEnd, .selectRight, .right])
    precondition(openFound.containers == [[2], [4], [4, 2], [6], [7]] && tablesFound.containers == [[9], [15], [19], [19, 3]])

    let quotedChild = openTree[4].children.enumerated().map { $0.offset == 1 ? fakeTree("0/Q/157/180")[0] : $0.element }
    precondition(openWitness(\.children) == openWitness(\.children)
                 && openWitness { $0 === openTree[4] ? quotedChild : $0.children } != openWitness(\.children)
                 && openWitness(\.children, roots: Array(openTree.prefix(5))) == nil
                 && UnreachableLines.witness(roots: openTree, containers: [], children: \.children, identity: ObjectIdentifier.init)
                    == openTree.reduce(into: Hasher()) { $0.combine(ObjectIdentifier($1)) }.finalize())

    // An `AXSplitter` is a rule only where the roots show Linear's classes.
    let ruledSpec = "0/G/0/5 0.0/T/0/5 1/R/5/5 2/G/5/10 2.0/T/5/10 3/R/10/10 4/R/10/10 5/G/10/15 5.0/T/10/15"
    let ruleCandidates = UnreachableLines.Candidates(markers: [], chips: [], stops: true)
    precondition(unreachableScanned(fakeTree(ruledSpec), ruleCandidates)?.stops.map(\.kind) == [.rule, .rule, .ruleGap, .rule]
                 && unreachableScanned(fakeTree(ruledSpec, linear: false), ruleCandidates)?.stops == [])

    // The keys between and around rules, stops and tables, as measured in Linear.
    var ruleKeys = KeyModel(text: "a\nb\nc", anchor: 1, focus: 1, stops: [2: [.rule], 4: [.rule, .ruleGap, .rule]])
    precondition(ruleKeys.press(.right) && ruleKeys.inGap && ruleKeys.press(.right) && ruleKeys.selection == 2..<2 && !ruleKeys.inGap)
    precondition(ruleKeys.press(.left) && ruleKeys.inGap && ruleKeys.press(.paragraphStart) && ruleKeys.selection == 2..<2,
                 "⌃A on a selected rule goes below it")
    precondition(ruleKeys.press(.up) && ruleKeys.inGap && ruleKeys.press(.up) && ruleKeys.selection == 1..<1, "↑ lands at the end above")
    precondition(ruleKeys.press(.down) && ruleKeys.inGap && !ruleKeys.press(.paragraphEnd), "⌃E on a selected rule is not known")
    ruleKeys = KeyModel(text: "a\nb\nc", anchor: 3, focus: 3, stops: [4: [.rule, .ruleGap, .rule]])
    precondition((1...3).allSatisfy { _ in ruleKeys.press(.right) && ruleKeys.inGap } && ruleKeys.press(.right)
                 && ruleKeys.selection == 4..<4)
    var upOnly = KeyModel(text: "a\nb", anchor: 1, focus: 1, stops: [2: [.upGap]])
    precondition(upOnly.press(.right) && upOnly.selection == 2..<2 && !upOnly.inGap && upOnly.press(.up) && upOnly.inGap)
    var backKeys = KeyModel(text: "a\nb", anchor: 2, focus: 2, stops: [2: [.backGap, .rule]])
    precondition(backKeys.press(.left) && backKeys.press(.left) && backKeys.inGap && backKeys.press(.left) && backKeys.selection == 1..<1)
    backKeys = KeyModel(text: "a\nb", anchor: 1, focus: 1, stops: [2: [.backGap, .rule]])
    precondition(backKeys.press(.right) && backKeys.press(.right) && backKeys.selection == 2..<2, "→ skips the stop before a rule")
    // "p", a one-row table of two cells, "q".
    var tableKeys = KeyModel(text: "p\nc1\nc2\nq", anchor: 4, focus: 4, cells: [2, 5], lastRows: [2])
    precondition(tableKeys.press(.wordRight) && tableKeys.selection == 5..<5 && tableKeys.press(.paragraphEnd)
                 && tableKeys.press(.wordRight) && tableKeys.selection == 8..<8, "⌥→ from a cell's end to the next line's start")
    precondition(tableKeys.press(.left) && tableKeys.selection == 1..<1, "← from the line below skips the table")
    tableKeys = KeyModel(text: "p\nc1\nc2\nq", anchor: 8, focus: 8, cells: [2, 5], lastRows: [2])
    precondition(tableKeys.press(.up) && tableKeys.selection == 2..<2, "↑ enters the last row's first cell")
    precondition(!tableKeys.press(.down) && !tableKeys.press(.up), "rows are not laid out")
    tableKeys = KeyModel(text: "p\nc1\nc2\nq", anchor: 4, focus: 4, stops: [8: [.boxedGap]], cells: [2, 5], lastRows: [2])
    precondition(!tableKeys.press(.right), "→ from a last-row cell leaves for the stop below")
    var offColumn = KeyModel(text: "p\nc1\nc2\nq", anchor: 9, focus: 9, cells: [2, 5], lastRows: [2])
    precondition(!offColumn.press(.up), "↑ from past column 0 lands where the caret's x falls")

    // The Sim's Linear with those blocks: every sweep lands where the plain Sim does.
    let ruledDoc: [(String, Sim.ListLine)] = [
        ("Top paragraph", .init()), ("After a rule", .init(ruled: 1, before: [.rule])), ("Bullet", .init(marker: "\u{2022}")),
        ("Quote after a rule", .init(ruled: 1, before: [.rule])), ("After two rules", .init(ruled: 2, before: [.rule, .ruleGap, .rule])),
        ("Title", .init(leaves: 1, stop: true)), ("Bullet below", .init(marker: "\u{2022}", before: [.upGap])), ("Last paragraph.", .init()),
    ]
    let tabledDoc: [(String, Sim.ListLine)] = [
        ("Top paragraph", .init()), ("Bullet", .init(marker: "\u{2022}")), ("Cell one", .init(before: [.boxedGap], cell: true)),
        ("Cell two", .init(cell: true)), ("Cell three", .init(lastRow: true)), ("Cell four", .init(cell: true)),
        ("Bullet after", .init(marker: "\u{2022}", leaves: 2, before: [.boxedGap])), ("Paragraph", .init()),
        ("Cell five", .init(cell: true)), ("Cell six", .init(lastRow: true)), ("Last paragraph.", .init(leaves: 2)),
    ]
    for (doc, profiles) in [(ruledDoc, [stopsProfile, writeKeys, noLineKeys]), (tabledDoc, [stopsProfile, writeKeys])] {
        for profile in profiles {
            let down = String(repeating: "j", count: doc.count)
            for keys in [down + String(repeating: "k", count: doc.count), "3j2k4j5j3k", "9jkkkkkkkk", "5ljjjjjjjjjjkkkkkkkkkk",
                         "$jjjjjjjjjjkkkkkkkkkk"] {
                var host = blockSim(profile, doc)
                var plain = Sim(text: host.text, caret: 0, profile: profile)
                plain.emulatesKeys = true
                for key in keys {
                    host.type(String(key))
                    plain.type(String(key))
                    precondition(host.caret == plain.caret && host.text == plain.text, "\(doc[0].0) \(keys) at \(key)")
                }
                precondition(host.settleFailures == 0 && host.bells == 0, "\(doc[0].0) \(keys)")
            }
        }
    }
}
