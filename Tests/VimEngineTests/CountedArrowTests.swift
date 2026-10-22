// MARK: - Cheaper counted arrows (LIN-1686)

func routes(_ plan: PhysicalPlan) -> [Route?] {
    plan.steps.compactMap { step -> Route?? in
        guard case .settle(let expectation) = step else { return nil }
        return .some(expectation.route)
    }
}

func without(_ missed: Set<Route>, _ keys: String, text: String, caret: Int) -> PhysicalPlan {
    PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand(keys), state: .initial),
                             snapshot: FieldSnapshot(capabilities: keyProfile, text: text, selection: caret..<caret), missed: missed).plan
}

let noLineKeys = removing([.lineEndKey, .lineStartKey], from: keyProfile)

let joinedDoc: [(String, String?, Int, Bool, Bool)] = [
    ("Top paragraph", nil, 0, false, false), ("Numbered one", "1.", 0, false, false), ("Numbered two", "2.", 0, false, false),
    ("Bullet one", "\u{2022}", 0, false, true), ("Bullet two", "\u{2022}", 0, false, false),
    ("A to-do", nil, 2, true, true), ("Numbered again", "1.", 0, false, true), ("Middle paragraph", nil, 0, false, false),
    ("Bullet after", "\u{2022}", 0, false, false), ("Last paragraph.", nil, 0, false, false),
]
func joinedSim(_ profile: CapabilityProfile, caret: Int = 0) -> Sim {
    var host = Sim(text: joinedDoc.map(\.0).joined(separator: "\n"), caret: caret, profile: profile)
    host.emptyParagraphs = true
    host.listLines = joinedDoc.map { Sim.ListLine(marker: $0.1, leaves: $0.2, checkbox: $0.3, stop: $0.4) }
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}

// softlash/LIN-1726 scripts/block-boundary (Dia 1.51.0): every pair of paragraph, heading, list, code block and quote.
let blocksValue = "Boundary probe: plain opening paragraph alpha.\nMarkdown\n\n\ncode after paragraph bravo\n\nsecond code line charlie\nParagraph after code delta.\nQuote after paragraph echo\nParagraph after quote foxtrot.\n\n\nHeading golf\nCSS\n\n\ncode after heading hotel\n\n\nHeading after code india\nQuote after heading juliet\n\n\nHeading after quote kilo\n\u{2022}\nBullet before code lima\nCSS\n\n\ncode after bullet mike\nQuote after code november\nCSS\n\n\ncode after quote oscar\nCSS\n\n\ncode after code papa\n1.\nNumbered after code quebec\nQuote after numbered romeo\n\n\nTodo after quote sierra\nCSS\n\n\ncode after todo tango\n\n\nTodo after code uniform\nQuote after todo victor\nSecond quote paragraph whiskey\n\u{2022}\nBullet after quote xray\nPlain closing paragraph yankee."
let blocksRaw = "Boundary probe: plain opening paragraph alpha.Markdown\u{FFFC}\u{FFFC}code after paragraph bravo\nsecond code line charlieParagraph after code delta.Quote after paragraph echoParagraph after quote foxtrot.\u{FFFC}\u{FFFC}Heading golfCSS\u{FFFC}\u{FFFC}code after heading hotel\u{FFFC}\u{FFFC}Heading after code indiaQuote after heading juliet\u{FFFC}\u{FFFC}Heading after quote kilo\u{2022}Bullet before code limaCSS\u{FFFC}\u{FFFC}code after bullet mikeQuote after code novemberCSS\u{FFFC}\u{FFFC}code after quote oscarCSS\u{FFFC}\u{FFFC}code after code papa1.Numbered after code quebecQuote after numbered romeo\u{FFFC}\u{FFFC}Todo after quote sierraCSS\u{FFFC}\u{FFFC}code after todo tango\u{FFFC}\u{FFFC}Todo after code uniformQuote after todo victorSecond quote paragraph whiskey\u{2022}Bullet after quote xrayPlain closing paragraph yankee."
let blocksSpec = """
0/G/0/46 0.0/T/0/46 1/B/46/105 1.0/N/46/54 1.1/D/54/105 1.1.0/T/54/81 1.1.1/T/81/105 2/G/105/132 2.0/T/105/132
3/Q/132/158 3.0/G/132/158 3.0.0/T/132/158 4/G/158/188 4.0/T/158/188 5/H/188/200 5.0/G/188/188 5.1/T/188/200
6/B/200/227 6.0/N/200/203 6.1/D/203/227 6.1.0/T/203/207 6.1.1/T/207/227 7/H/227/251 7.0/G/227/227 7.1/T/227/251
8/Q/251/277 8.0/G/251/277 8.0.0/T/251/277 9/H/277/301 9.0/G/277/277 9.1/T/277/301 10/L/301/325 10.0/G/301/325
10.0.0/G/301/302 10.0.0.0/T/301/302 10.0.1/G/302/325 10.0.1.0/T/302/325 11/B/325/350 11.0/N/325/328 11.1/D/328/350
11.1.0/T/328/332 11.1.1/T/332/350 12/Q/350/375 12.0/G/350/375 12.0.0/T/350/375 13/B/375/400 13.0/N/375/378
13.1/D/378/400 13.1.0/T/378/382 13.1.1/T/382/389 13.1.2/T/389/394 13.1.3/T/394/400 14/B/400/423 14.0/N/400/403
14.1/D/403/423 14.1.0/T/403/407 14.1.1/T/407/414 14.1.2/T/414/418 14.1.3/T/418/423 15/L/423/451 15.0/G/423/451
15.0.0/G/423/425 15.0.0.0/T/423/424 15.0.0.1/T/424/425 15.0.1/G/425/451 15.0.1.0/T/425/451 16/Q/451/477 16.0/G/451/477
16.0.0/T/451/477 17/L/477/500 17.0/G/477/500 17.0.0/G/477/477 17.0.0.0/I/477/477 17.0.0.1/C/477/477 17.0.1/G/477/500
17.0.1.0/G/477/500 17.0.1.0.0/T/477/500 18/B/500/524 18.0/N/500/503 18.1/D/503/524 18.1.0/T/503/507 18.1.1/T/507/524
19/L/524/547 19.0/G/524/547 19.0.0/G/524/524 19.0.0.0/I/524/524 19.0.0.1/C/524/524 19.0.1/G/524/547 19.0.1.0/G/524/547
19.0.1.0.0/T/524/547 20/Q/547/600 20.0/G/547/570 20.0.0/T/547/570 20.1/G/570/600 20.1.0/T/570/600 21/L/600/624
21.0/G/600/624 21.0.0/G/600/601 21.0.0.0/T/600/601 21.0.1/G/601/624 21.0.1.0/T/601/624 22/G/624/655 22.0/T/624/655
"""

let blocksModel = folded(blocksValue, blocksRaw, fakeTree(blocksSpec))

func crossing(_ line: String, _ keys: String = "j", profile: CapabilityProfile = keyProfile) -> [Chord] {
    chords(webPhysical(keys, text: blocksModel.text, caret: lineStart(of: line, in: blocksModel.text), profile: profile,
                       breaks: blocksModel.breaks))
}

let blockDoc: [(String, Sim.ListLine)] = [
    ("Top paragraph", .init()), ("code one", .init(marker: "Markdown", leaves: 2, controls: true)),
    ("Middle paragraph", .init()), ("A quote", .init()), ("Bullet one", .init(marker: "\u{2022}", stop: true)),
    ("code two", .init(marker: "CSS", leaves: 2, stop: true, controls: true)), ("Quote two", .init(stop: true)),
    ("code three", .init(marker: "CSS", leaves: 2, stop: true, controls: true)),
    ("code four", .init(marker: "Plaintext", leaves: 2, stop: true, controls: true)),
    ("A to-do", .init(leaves: 2, checkbox: true, stop: true)), ("Quote three", .init(stop: true)),
    ("Numbered", .init(marker: "1.", stop: true)), ("Last paragraph.", .init()),
]

func testCountedArrows() {
    let tenTwice = "abcdefghij\nabcdefghij"
    precondition(chords(physical("j", text: tenTwice, caret: 2, profile: keyProfile)) == [.paragraphEnd, .right, .right, .right])
    precondition(chords(physical("j", text: tenTwice, caret: 8, profile: keyProfile))
                 == [.paragraphEnd, .right, .paragraphEnd, .left, .left])
    precondition(chords(physical("j", text: tenTwice, caret: 10, profile: keyProfile)) == [.paragraphEnd, .right, .paragraphEnd])
    precondition(chords(physical("k", text: tenTwice, caret: 19, profile: keyProfile)) == [.paragraphStart, .left, .left, .left])
    precondition(chords(physical("k", text: tenTwice, caret: 13, profile: keyProfile))
                 == [.paragraphStart, .left, .paragraphStart, .right, .right])
    precondition(chords(physical("j", text: tenTwice, caret: 5, profile: keyProfile)).count == 7, "a tie counts from the start")
    let nearEnd = physical("j", text: tenTwice, caret: 8, profile: keyProfile)
    precondition(nearEnd.traceShape == "P!PP!P2!C" && nearEnd.steps[1] == .settle(Expectation(
        landing: .exact(10..<10), length: 21,
        blame: .init(capability: .lineEndKey, unmoved: [8..<8], leavesCaret: true, offTarget: true)
    )), "the extra ⌃E rides the unblamed hops")

    precondition(routes(nearEnd) == [nil, .lineEnd, .lineEnd], "the settles past the extra ⌃E are an optional route's")
    precondition(routes(physical("k", text: tenTwice, caret: 19, profile: keyProfile)) == [nil, .lineStart, .lineStart])
    precondition(routes(physical("j", text: tenTwice, caret: 2, profile: keyProfile)) == [nil, nil, nil])

    precondition(chords(without([.lineEnd], "j", text: tenTwice, caret: 8))
                 == [.paragraphEnd, .right] + Array(repeating: .right, count: 8), "a route that missed leaves `j` its start way")
    precondition(chords(without([.lineStart], "k", text: tenTwice, caret: 19))
                 == [.paragraphStart, .left, .paragraphStart] + Array(repeating: .right, count: 8))
    precondition(chords(without([.lineStart, .selectBack], "j", text: tenTwice, caret: 8)).count == 5, "other routes' misses leave this one")
    let tenBreak = ParagraphBreaks(offsets: [10])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 8, profile: keyProfile, breaks: tenBreak))
                 == [.paragraphEnd, .right, .paragraphEnd, .selectLeft, .selectLeft, .left, .selectLeft, .right])
    precondition(chords(physical("j", text: tenTwice, caret: 6, profile: keyProfile)).suffix(5) == [.paragraphEnd, .left, .left, .left, .left])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 6, profile: keyProfile, breaks: tenBreak))
                 == [.paragraphEnd, .right] + Array(repeating: .selectRight, count: 6) + [.right], "where those tip it to the start")

    let twenty = String(repeating: "word ", count: 20) + "end."
    precondition(chords(physical("fd", text: twenty, caret: 0, profile: keyProfile)) == [.right, .right, .right])
    let farFind = physical("t.", text: twenty, caret: 0, profile: keyProfile)
    var routedEnd = Expectation(landing: .exact(102..<102), length: 104)
    routedEnd.route = .lineEnd
    precondition(Array(farFind.steps.prefix(3)) == [.press(.paragraphEnd, count: 1), .press(.left, count: 2), .settle(routedEnd)],
                 "one settle, marked as an optional route's")
    precondition(routedEnd.traceFields == "sel=102..102 len=104 route=line-end")
    precondition(chords(physical("t.", text: twenty, caret: 98, profile: keyProfile)) == [.paragraphEnd, .left, .left])
    precondition(chords(physical("t.", text: twenty, caret: 99, profile: keyProfile)) == Array(repeating: .right, count: 3),
                 "a tie counts from the caret")
    precondition(chords(without([.lineEnd], "t.", text: twenty, caret: 0)) == Array(repeating: .right, count: 102))
    precondition(chords(without([.lineStart], "t.", text: twenty, caret: 0)) == [.paragraphEnd, .left, .left])
    let wordFirst = "aw" + String(repeating: "x", count: 100)
    precondition(chords(physical("Fw", text: wordFirst, caret: 101, profile: keyProfile)) == [.paragraphStart, .right])
    precondition(chords(physical("Fw", text: twenty, caret: 99, profile: keyProfile)) == Array(repeating: .left, count: 4))
    precondition(chords(physical("Fw", text: twenty, caret: 102, profile: removing([.lineStartKey, .lineEndKey], from: keyProfile)))
                 == Array(repeating: .left, count: 7), "without the line keys it counts from the caret")
    var fromStart = Sim(text: twenty, caret: 103, profile: keyProfile)
    fromStart.emulatesKeys = true
    fromStart.type("2Fw")
    precondition(fromStart.caret == 90 && fromStart.settleFailures == 0)
    fromStart.type("0e")
    precondition(fromStart.caret == 3)

    precondition(chords(physical("X", text: twenty, caret: 50, profile: keyProfile)) == [.selectLeft, .deleteBack])
    precondition(chords(physical("db", text: twenty, caret: 52, profile: keyProfile)) == [.selectLeft, .selectLeft, .deleteBack])
    precondition(chords(physical("d^", text: twenty, caret: 60, profile: keyProfile)) == [Chord.paragraphStart.shifted, .deleteBack])
    precondition(chords(physical("dt.", text: twenty, caret: 0, profile: keyProfile))
                 == [Chord.paragraphEnd.shifted, .selectLeft, .deleteBack])
    precondition(chords(physical("x", text: twenty, caret: 3, profile: keyProfile)) == [.selectRight, .deleteBack])
    let chipInLine = ParagraphBreaks(hidden: [.init(at: 3, text: "LIN-1 chip", kind: .atom)])
    precondition(chords(webPhysical("dt.", text: "ab\u{2060}cd. and more", caret: 0, profile: keyProfile, breaks: chipInLine))
                 == Array(repeating: .selectRight, count: 5) + [.deleteBack], "⇧⌃E would stop at the chip")
    precondition(chords(without([.lineStart], "d^", text: twenty, caret: 60)) == Array(repeating: .selectLeft, count: 60) + [.deleteBack])
    precondition(chords(without([.lineEnd], "dt.", text: twenty, caret: 0)) == Array(repeating: .selectRight, count: 103) + [.deleteBack])
    precondition(chords(without([.selectBack], "X", text: twenty, caret: 50)) == [.left, .selectRight, .deleteBack])
    precondition(routes(physical("d^", text: twenty, caret: 60, profile: keyProfile)).first == .some(.lineStart)
                 && routes(physical("X", text: twenty, caret: 50, profile: keyProfile)).first == .some(.selectBack)
                 && routes(physical("x", text: twenty, caret: 3, profile: keyProfile)).first == .some(nil))
    for (keys, caret, left) in [("X", 50, String(twenty.prefix(49) + twenty.dropFirst(50))), ("dF ", 99, String(twenty.prefix(95) + twenty.dropFirst(99))),
                                ("d^", 60, String(twenty.dropFirst(60))), ("dt.", 0, ".")] {
        var host = Sim(text: twenty, caret: caret, profile: keyProfile)
        host.emulatesKeys = true
        host.type(keys)
        precondition(host.text == left && host.settleFailures == 0, keys)
    }
    precondition(chords(webPhysical("de", text: "ab\ncd", caret: 0, profile: removing([.lineStartKey], from: keyProfile),
                                    breaks: ParagraphBreaks(offsets: [2])))
                 == [.selectRight, .selectRight, .deleteBack], "⇧⌃E's ⇧→ ← at a paragraph's start would cost more")
    precondition(chords(webPhysical("de", text: "abcd\ncd", caret: 0, profile: keyProfile, breaks: ParagraphBreaks(offsets: [4])))
                 == [.paragraphStart, Chord.paragraphEnd.shifted, .deleteBack])

    var strayed = RunAttribution()
    strayed.record(.press(.paragraphEnd, count: 1))
    strayed.record(.settle(routedEnd), passed: false, selection: 0..<0, length: 104)
    precondition(strayed.missedRoute == .lineEnd && strayed.evidence.isEmpty, "a route's miss is no evidence on its key")
    var dark = RunAttribution()
    dark.record(.settle(routedEnd), passed: false, selection: nil, length: 104)
    var landed = RunAttribution()
    landed.record(.settle(routedEnd), passed: true, selection: 102..<102, length: 104)
    precondition(dark.missedRoute == nil && landed.missedRoute == nil, "a read that went dark is not the route's miss")
    var missedRoutes = Strikes()
    missedRoutes.miss(.lineEnd, judgedUnder: .value, app: "1")
    missedRoutes.pass([Evidence(.key(.lineEndKey), .supports(nil), why: .settled, seen: .settle(0))])
    precondition(missedRoutes.missed(judgedUnder: .value, app: "1") == [.lineEnd] && !missedRoutes.isEmpty, "no pass brings it back")
    precondition(missedRoutes.missed(judgedUnder: .textContent, app: "1").isEmpty && missedRoutes.missed(judgedUnder: .value, app: "2").isEmpty)

    // softlash/LIN-1686 scripts/route-faults runs these against `main`, which counts and never fails them.
    for rich in [false, true] {
        for (line, keys, caret, key, opposite, further, left, landing) in [
            (twenty, "t.", 0, Chord.paragraphEnd, Chord.paragraphStart, Chord.documentEnd, twenty, 102),
            (wordFirst, "Fw", 101, .paragraphStart, .paragraphEnd, .documentStart, wordFirst, 1),
            (twenty, "d^", 60, Chord.paragraphStart.shifted, Chord.paragraphEnd.shifted, Chord.documentStart.shifted,
             String(twenty.dropFirst(60)), 0),
            (twenty, "dt.", 0, Chord.paragraphEnd.shifted, Chord.paragraphStart.shifted, Chord.documentEnd.shifted, ".", 0),
        ] {
            for acts in [nil, opposite, further] {
                var host = Sim(text: "prefix\n" + line + "\nnext", caret: caret + 7, profile: keyProfile)
                host.emulatesKeys = true
                if rich {
                    host.emptyParagraphs = true
                    host.readModel = .textContent
                }
                if let acts { host.reboundChords = [key: acts] } else { host.ignoredChords = [key] }
                host.learn(with: Sim.Learner(chromium: rich, probed: keyProfile))
                let fault = "\(keys) rich \(rich) as \(acts.map { "\($0)" } ?? "nothing")"
                host.type(keys)
                precondition(host.settleFailures == 1 && host.blamed.isEmpty && !host.learner!.strikes.isEmpty, fault)
                for _ in 0..<2 {
                    host.refocus(.sameElement, text: "prefix\n" + line + "\nnext", caret: caret + 7)
                    host.type(keys)
                    precondition(host.settleFailures == 1 && host.text == "prefix\n" + left + "\nnext" && host.caret == landing + 7, fault)
                }
            }
        }
    }
    var lineEnd = Sim(text: tenTwice, caret: 10, profile: keyProfile)
    lineEnd.emulatesKeys = true
    lineEnd.ignoredChords = [.paragraphEnd]
    lineEnd.learn(with: Sim.Learner(probed: keyProfile))
    lineEnd.type("j")
    precondition(lineEnd.settleFailures == 1 && lineEnd.caret == 11, "`j`'s way by the line's end misses where ⌃E does nothing")
    lineEnd.refocus(.sameElement, text: tenTwice, caret: 10)
    lineEnd.type("j")
    precondition(lineEnd.settleFailures == 1 && lineEnd.caret == 21)
    var noShiftLeft = Sim(text: twenty, caret: 50, profile: keyProfile)
    noShiftLeft.emulatesKeys = true
    noShiftLeft.ignoredChords = [.selectLeft]
    noShiftLeft.learn(with: Sim.Learner(probed: keyProfile))
    noShiftLeft.type("X")
    precondition(noShiftLeft.settleFailures == 1 && noShiftLeft.text == twenty)
    noShiftLeft.type("X")
    precondition(noShiftLeft.settleFailures == 1 && noShiftLeft.text == String(twenty.prefix(49) + twenty.dropFirst(50)))

    let paste = webPhysical("\"+p", text: "x", caret: 0, profile: keyProfile, breaks: ParagraphBreaks())
    precondition(chords(paste) == [.selectRight, .right] && paste.traceShape.hasPrefix("PPV"), "a put's keys go before ⌘V unsettled")
    var yankedBack = Sim(text: twenty, caret: 52, profile: keyProfile)
    yankedBack.emulatesKeys = true
    yankedBack.type("yb")
    precondition(yankedBack.caret == 50 && yankedBack.readSelection == 50..<50
                 && yankedBack.state.session.register("\"") == .content(RegisterContent(text: "wo", wise: .character)))

    // softlash/LIN-1686 scripts/list-boundary (Dia 1.49.1): a plain → or ↓ from a list's last item stops before the next list.
    var gapKeys = KeyModel(text: "a\nb\nc", anchor: 1, focus: 1, gaps: [2])
    precondition(gapKeys.press(.right) && gapKeys.selection == 1..<1 && gapKeys.inGap)
    precondition(gapKeys.press(.paragraphStart) && gapKeys.press(Chord.paragraphEnd.shifted) && gapKeys.inGap, "⌃A and ⇧⌃E stay")
    precondition(gapKeys.press(.right) && gapKeys.selection == 2..<2 && !gapKeys.inGap)
    gapKeys = KeyModel(text: "a\nb\nc", anchor: 0, focus: 0, gaps: [2])
    precondition(gapKeys.press(.down) && gapKeys.inGap && gapKeys.press(.selectRight) && gapKeys.selection == 2..<2)
    gapKeys = KeyModel(text: "a\nb\nc", anchor: 1, focus: 1, gaps: [2])
    precondition(gapKeys.press(.right) && gapKeys.press(.left) && gapKeys.selection == 1..<1 && !gapKeys.inGap)
    precondition(gapKeys.press(.selectRight) && gapKeys.selection == 1..<2, "⇧→ crosses")
    gapKeys = KeyModel(text: "a\nb\nc", anchor: 2, focus: 2, gaps: [2])
    precondition(gapKeys.press(.left) && gapKeys.selection == 1..<1, "← from the next list skips it")
    // softlash/LIN-1726 scripts/block-boundary (Dia 1.51.0): ↑ from the line after a stop enters it, and ↑ again leaves upward.
    gapKeys = KeyModel(text: "ab\ncd\nef", anchor: 4, focus: 4, gaps: [3])
    precondition(gapKeys.press(.up) && gapKeys.selection == 2..<2 && gapKeys.inGap)
    precondition(gapKeys.press(.up) && gapKeys.selection == 0..<0 && !gapKeys.inGap)
    gapKeys = KeyModel(text: "ab\ncd\nef", anchor: 7, focus: 7, gaps: [3])
    precondition(gapKeys.press(.up) && gapKeys.selection == 4..<4 && !gapKeys.inGap, "no stop above a line that starts no block")

    let boundaryValue = "LIN-1686 boundary probe: plain opening paragraph here.\n1.\nNumbered one alpha\n2.\nNumbered two bravo\n\u{2022}\nBullet one charlie\n\u{2022}\nBullet two delta\n1.\nNumbered again echo\n\n\nTodo one foxtrot\n\n\nTodo two golf\n1.\nNumbered after todo hotel\n\u{2022}\nDash bullet india\n\u{2022}\nStar bullet juliet\n\n\nTodo after star kilo\n\u{2022}\nStar after todo lima\nParagraph after list mike.\n\u{2022}\nBullet after paragraph november\n\n\nHeading after list oscar\nPlain closing paragraph papa."
    let boundaryRaw = "LIN-1686 boundary probe: plain opening paragraph here.1.Numbered one alpha2.Numbered two bravo\u{2022}Bullet one charlie\u{2022}Bullet two delta1.Numbered again echo\u{FFFC}\u{FFFC}Todo one foxtrot\u{FFFC}\u{FFFC}Todo two golf1.Numbered after todo hotel\u{2022}Dash bullet india\u{2022}Star bullet juliet\u{FFFC}\u{FFFC}Todo after star kilo\u{2022}Star after todo limaParagraph after list mike.\u{2022}Bullet after paragraph november\u{FFFC}\u{FFFC}Heading after list oscarPlain closing paragraph papa."
    let boundarySpec = """
    0/G/0/54 0.0/T/0/54 1/L/54/94 1.0/G/54/74 1.0.0/G/54/56 1.0.0.0/T/54/55 1.0.0.1/T/55/56 1.0.1/G/56/74 1.0.1.0/T/56/74
    1.1/G/74/94 1.1.0/G/74/76 1.1.0.0/T/74/75 1.1.0.1/T/75/76 1.1.1/G/76/94 1.1.1.0/T/76/94 2/L/94/130 2.0/G/94/113 2.0.0/G/94/95
    2.0.0.0/T/94/95 2.0.1/G/95/113 2.0.1.0/T/95/113 2.1/G/113/130 2.1.0/G/113/114 2.1.0.0/T/113/114 2.1.1/G/114/130
    2.1.1.0/T/114/130 3/L/130/151 3.0/G/130/151 3.0.0/G/130/132 3.0.0.0/T/130/131 3.0.0.1/T/131/132 3.0.1/G/132/151
    3.0.1.0/T/132/151 4/L/151/180 4.0/G/151/167 4.0.0/G/151/151 4.0.0.0/I/151/151 4.0.0.1/C/151/151 4.0.1/G/151/167
    4.0.1.0/G/151/167 4.0.1.0.0/T/151/167 4.1/G/167/180 4.1.0/G/167/167 4.1.0.0/I/167/167 4.1.0.1/C/167/167 4.1.1/G/167/180
    4.1.1.0/G/167/180 4.1.1.0.0/T/167/180 5/L/180/207 5.0/G/180/207 5.0.0/G/180/182 5.0.0.0/T/180/181 5.0.0.1/T/181/182
    5.0.1/G/182/207 5.0.1.0/T/182/207 6/L/207/225 6.0/G/207/225 6.0.0/G/207/208 6.0.0.0/T/207/208 6.0.1/G/208/225
    6.0.1.0/T/208/225 7/L/225/244 7.0/G/225/244 7.0.0/G/225/226 7.0.0.0/T/225/226 7.0.1/G/226/244 7.0.1.0/T/226/244
    8/L/244/264 8.0/G/244/264 8.0.0/G/244/244 8.0.0.0/I/244/244 8.0.0.1/C/244/244 8.0.1/G/244/264 8.0.1.0/G/244/264
    8.0.1.0.0/T/244/264 9/L/264/285 9.0/G/264/285 9.0.0/G/264/265 9.0.0.0/T/264/265 9.0.1/G/265/285 9.0.1.0/T/265/285
    10/G/285/311 10.0/T/285/311 11/L/311/343 11.0/G/311/343 11.0.0/G/311/312 11.0.0.0/T/311/312 11.0.1/G/312/343
    11.0.1.0/T/312/343 12/H/343/367 12.0/G/343/343 12.0.0/G/343/343 12.0.0.0/E/343/343 12.0.0.1/P/343/343 12.1/T/343/367
    13/G/367/396 13.0/T/367/396
    """
    let boundaryTree = fakeTree(boundarySpec)
    let boundaryModel = folded(boundaryValue, boundaryRaw, boundaryTree)

    precondition(boundaryModel.breaks.gaps == Set(["Bullet one charlie", "Numbered again echo", "Todo one foxtrot",
        "Numbered after todo hotel", "Dash bullet india", "Star bullet juliet", "Todo after star kilo", "Star after todo lima",
    ].map { lineStart(of: $0, in: boundaryModel.text) }), "a stop before every list right after a list, and nowhere else")
    precondition(roundTrips(boundaryModel))
    let boundaryCandidates = UnreachableLines.candidates(text: boundaryValue, breaks: ParagraphBreaks(value: boundaryValue,
        fieldText: MarkerText.plain(boundaryRaw))!, raw: boundaryRaw)
    precondition((1...400).contains { budget in
        guard let found = unreachableScanned(boundaryTree, boundaryCandidates, budget: budget) else { return false }
        return found.joins.isEmpty && found.markers.count == 10
    }, "running out of reads on the lists loses only the joins")
    precondition(unreachableScanned(boundaryTree, UnreachableLines.Candidates(markers: [], chips: []))?.joins == [],
                 "nothing that starts a list and no ProseMirror editor, no joins read")
    let otherBoundary = fakeTree(boundarySpec, linear: false)
    let markedJoins = unreachableScanned(otherBoundary, boundaryCandidates)?.joins ?? []
    precondition(!markedJoins.isEmpty && unreachableScanned(otherBoundary, UnreachableLines.candidates(text: boundaryValue,
        breaks: ParagraphBreaks(value: boundaryValue, fieldText: MarkerText.plain(boundaryRaw))!, raw: boundaryRaw, proseMirror: true))?
        .joins == markedJoins, "another ProseMirror editor's lists join where its text shows a marker, as on main")
    let ownLists = fakeTree("0/G/0/3 0.0/T/0/3 1/L/3/6 1.0/G/3/6 1.0.0/M/3/5 1.0.1/T/5/6 2/L/6/10 2.0/G/6/10 2.0.0/M/6/9 2.0.1/T/9/10")
    let ownCandidates = UnreachableLines.candidates(text: "Top\n\u{2022} a\n1. b", breaks: ParagraphBreaks(offsets: [3, 7]), raw: "Top\u{2022} a1. b")
    precondition(unreachableScanned(ownLists, ownCandidates)?.joins == [6]
                 && folded("Top\n\u{2022} a\n1. b", "Top\u{2022} a1. b", ownLists).breaks.gaps.isEmpty, "Chromium's own lists have no stop")
    let todosModel = folded("Top\n\n\nTodo a\n\n\nTodo b\nEnd", "Top\u{FFFC}\u{FFFC}Todo a\u{FFFC}\u{FFFC}Todo bEnd", fakeTree("""
    0/G/0/3 0.0/T/0/3 1/L/3/9 1.0/G/3/9 1.0.0/G/3/3 1.0.0.0/I/3/3 1.0.0.1/C/3/3 1.0.1/G/3/9 1.0.1.0/T/3/9 2/L/9/15 2.0/G/9/15
    2.0.0/G/9/9 2.0.0.0/I/9/9 2.0.0.1/C/9/9 2.0.1/G/9/15 2.0.1.0/T/9/15 3/G/15/18 3.0/T/15/18
    """))
    precondition(todosModel.text == "Top\nTodo a\nTodo b\nEnd" && todosModel.breaks.gaps == [11], "two to-do lists alone stop too")
    // softlash/LIN-1726 evidence/tree-empty-above-todo.jsonl: below an empty paragraph a to-do's image and checkbox have no lines.
    let bareTodo = folded(
        "Corner probe: plain opening paragraph alpha.\nTodo under paragraph bravo\nQuote after todo charlie\nPlain closing paragraph delta.",
        "Corner probe: plain opening paragraph alpha.\n\u{FFFC}\u{FFFC}Todo under paragraph bravoQuote after todo charliePlain closing paragraph delta.",
        fakeTree("""
        0/G/0/44 0.0/T/0/44 1/E/44/45 2/L/45/71 2.0/G/45/71 2.0.0/G/45/45 2.0.0.0/I/45/45 2.0.0.1/C/45/45 2.0.1/G/45/71
        2.0.1.0/G/45/71 2.0.1.0.0/T/45/71 3/Q/71/95 3.0/G/71/95 3.0.0/T/71/95 4/G/95/125 4.0/T/95/125
        """))
    precondition(bareTodo.breaks.hidden == [.init(at: lineStart(of: "Quote after todo", in: bareTodo.text), text: "", kind: .gap)]
                 && roundTrips(bareTodo), "with no marker and no leaf's line, the stop is read and kept all the same")
    // evidence/tree-empty-quote-line.jsonl: the same to-do below a quote's empty last line.
    let quotedBareTodo = folded(
        "Corner probe: plain opening paragraph alpha.\nQuote before todo bravo\nTodo after quote charlie\nPlain closing paragraph delta.",
        "Corner probe: plain opening paragraph alpha.Quote before todo bravo\n\u{FFFC}\u{FFFC}Todo after quote charliePlain closing paragraph delta.",
        fakeTree("""
        0/G/0/44 0.0/T/0/44 1/Q/44/68 1.0/G/44/67 1.0.0/T/44/67 1.1/E/67/68 2/L/68/92 2.0/G/68/92 2.0.0/G/68/68
        2.0.0.0/I/68/68 2.0.0.1/C/68/68 2.0.1/G/68/92 2.0.1.0/G/68/92 2.0.1.0.0/T/68/92 3/G/92/122 3.0/T/92/122
        """))
    let quotedBareStart = lineStart(of: "Todo after quote", in: quotedBareTodo.text)
    precondition(quotedBareTodo.breaks.hidden == [.init(at: quotedBareStart, text: "", kind: .boxedGap)] && roundTrips(quotedBareTodo)
                 && chords(webPhysical("j", text: quotedBareTodo.text, caret: quotedBareStart - 1, profile: keyProfile,
                                       breaks: quotedBareTodo.breaks)) == [.paragraphEnd, .right, .right],
                 "its stop is a to-do's by the leaves at the list's start, though none has a line")
    precondition(!UnreachableLines.candidates(text: "Top\nEnd", breaks: ParagraphBreaks(offsets: [3]), raw: "TopEnd").roots)

    let gapBreaks = ParagraphBreaks(offsets: [10], hidden: [
        .init(at: 11, text: ""), .init(at: 11, text: ""), .init(at: 11, text: "", kind: .boxedGap),
    ])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: keyProfile, breaks: gapBreaks))
                 == [.paragraphEnd, .right, .right], "a to-do, behind its checkbox's leaves, takes → →")
    let markedGap = ParagraphBreaks(offsets: [10], hidden: [.init(at: 11, text: "\u{2022}"), .init(at: 11, text: "", kind: .gap)])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: keyProfile, breaks: markedGap))
                 == [.paragraphEnd, .selectRight, .right], "a marked item is crossed into by ⇧→ →, which Dia reads right sooner")
    let quoteGap = ParagraphBreaks(offsets: [10], hidden: [.init(at: 11, text: "", kind: .gap)])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: keyProfile, breaks: quoteGap))
                 == [.paragraphEnd, .selectRight, .right], "and so is a quote, where → → reads one past for ~150 ms (LIN-1726)")
    precondition(webPhysical("j", text: tenTwice, caret: 0, profile: writeKeys, breaks: quoteGap).steps
                 == webPhysical("j", text: tenTwice, caret: 0, profile: writeKeys, breaks: ParagraphBreaks(offsets: [10])).steps
                 && webPhysical("dd", text: tenTwice, caret: 0, profile: writeKeys, breaks: quoteGap).steps.first
                 == webPhysical("dd", text: tenTwice, caret: 0, profile: writeKeys, breaks: ParagraphBreaks(offsets: [10])).steps.first,
                 "a stop folds no text, so a write lane plans a quote's first line as any paragraph's")
    let thrice = tenTwice + "\nabcdefghij"
    let foldedQuote = ParagraphBreaks(offsets: [10, 21], hidden: [.init(at: 11, text: "", kind: .gap), .init(at: 22, text: "\u{2022}")])
    let foldedPlain = ParagraphBreaks(offsets: [10, 21], hidden: [.init(at: 22, text: "\u{2022}")])
    precondition([("j", 0), ("k", 22), ("dd", 11), ("d$", 11)].allSatisfy { keys, caret in
        webPhysical(keys, text: thrice, caret: caret, profile: writeKeys, breaks: foldedQuote).steps
            == webPhysical(keys, text: thrice, caret: caret, profile: writeKeys, breaks: foldedPlain).steps
    }, "and so it does where the field folds a marker elsewhere")
    let bareTodoGap = ParagraphBreaks(offsets: [10], hidden: [.init(at: 11, text: "", kind: .boxedGap)])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: keyProfile, breaks: bareTodoGap))
                 == [.paragraphEnd, .right, .right], "a to-do whose checkbox has no line of its own still takes → →")
    precondition(["j", "$", "o", "dd", "J"].allSatisfy { keys in
        webPhysical(keys, text: tenTwice, caret: 0, profile: writeKeys, breaks: bareTodoGap).steps
            == webPhysical(keys, text: tenTwice, caret: 0, profile: writeKeys, breaks: ParagraphBreaks(offsets: [10])).steps
    }, "stops alone leave a field unfolded for the write lane, and an edit's length known")
    let codeGap = ParagraphBreaks(offsets: [10], hidden: [
        .init(at: 11, text: "CSS"), .init(at: 11, text: ""), .init(at: 11, text: ""), .init(at: 11, text: "", kind: .gap),
    ])
    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: keyProfile, breaks: codeGap))
                 == [.paragraphEnd, .selectRight, .right], "and a code block, behind its label and images")
    precondition(chords(webPhysical("w", text: tenTwice, caret: 3, profile: keyProfile, breaks: gapBreaks))
                 == [.paragraphEnd, .right, .right])
    precondition(chords(webPhysical("2$", text: tenTwice, caret: 0, profile: keyProfile, breaks: gapBreaks))
                 == [.paragraphEnd, .right, .right, .paragraphEnd])
    precondition(chords(webPhysical("k", text: tenTwice, caret: 11, profile: keyProfile, breaks: gapBreaks))
                 == [.paragraphStart, .left, .paragraphStart], "← from below never stops")

    precondition(chords(webPhysical("j", text: tenTwice, caret: 0, profile: noLineKeys, breaks: gapBreaks))
                 == [.down, .down, .lineStart], "lane B's ↓ stops there too")
    precondition(chords(webPhysical("k", text: tenTwice, caret: 11, profile: noLineKeys, breaks: gapBreaks))
                 == [.up, .up, .lineStart], "and its ↑ from below")

    var afterCode = Sim(text: "ab\ncd ef\ngh", caret: 4, profile: keyProfile)
    afterCode.emptyParagraphs = true
    afterCode.listLines = [Sim.ListLine(marker: "\u{2022}"), Sim.ListLine(marker: "\u{2022}"),
                           Sim.ListLine(leaves: 2, checkbox: true, stop: true)]
    afterCode.codeSpans = [6..<8]
    afterCode.emulatesKeys = true
    afterCode.readModel = .textContent
    afterCode.type("$j")
    precondition(afterCode.caret == 11 && afterCode.settleFailures == 0, "the stop holds while a caret drawn at code ends the item above")
    var stopped = joinedSim(keyProfile, caret: 27)
    stopped.perform([.press(.paragraphEnd, count: 1), .press(.right, count: 1)])
    precondition(stopped.caret == 39, "one → from a list's end stops between the lists")
    for profile in [keyProfile, writeKeys] {
        let down = String(repeating: "j", count: joinedDoc.count)
        for keys in [down + String(repeating: "k", count: joinedDoc.count), "3j2k4j5j3k", "9jkkkkkkkk", "5ljjjjjjjjjkkkk",
                     "$jjjjjjjjjkkkk", "jjjwwwwwwwwwwbbbbbbbbbb", "jjjjjjeeeee", "jj2$", "jjdd", "jjjj0jj^jj$"] {
            var joined = joinedSim(profile)
            var plain = Sim(text: joined.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                joined.type(String(key))
                plain.type(String(key))
                precondition(joined.caret == plain.caret && joined.text == plain.text, "\(keys) at \(key)")
            }
            precondition(joined.settleFailures == 0 && joined.bells == 0, keys)
        }
    }

    let blocksBreaks = ParagraphBreaks(value: blocksValue, fieldText: MarkerText.plain(blocksRaw))!
    let blocksCandidates = UnreachableLines.candidates(text: blocksValue, breaks: blocksBreaks, raw: blocksRaw, proseMirror: true)
    let blocksFound = unreachableScanned(fakeTree(blocksSpec), blocksCandidates)!
    precondition(blocksFound.controls == [46..<54, 200..<203, 325..<328, 375..<378, 400..<403, 500..<503], "each code block's label")
    precondition(blocksFound.joins == [325, 350, 375, 400, 423, 451, 477, 500, 524, 547, 600])

    let blocksLines = blocksModel.text.split(separator: "\n", omittingEmptySubsequences: false)
    precondition(blocksLines.count == 26 && !blocksLines.contains("CSS") && !blocksLines.contains("Markdown"), "a label is no line")
    precondition(blocksModel.breaks.gaps == Set(["code after bullet mike", "Quote after code november", "code after quote oscar",
        "code after code papa", "Numbered after code quebec", "Quote after numbered romeo", "Todo after quote sierra",
        "code after todo tango", "Todo after code uniform", "Quote after todo victor", "Bullet after quote xray",
    ].map { lineStart(of: $0, in: blocksModel.text) }), "a stop between any two of list, code block and quote, and nowhere else")
    precondition(roundTrips(blocksModel))
    precondition(Set(blocksModel.breaks.hidden.filter { $0.kind == .boxedGap }.map(\.at))
                 == Set(["Todo after quote sierra", "Todo after code uniform"].map { lineStart(of: $0, in: blocksModel.text) }),
                 "only a to-do's stop is boxed")
    precondition(blocksModel.breaks.fieldOffset(lineStart(of: "code after bullet mike", in: blocksModel.text)) == 328)

    precondition(crossing("Bullet before code lima") == [.paragraphEnd, .selectRight, .right])
    precondition(crossing("code after bullet mike") == [.paragraphEnd, .selectRight, .right])
    precondition(crossing("Quote after numbered romeo") == [.paragraphEnd, .right, .right], "a to-do after a quote")
    precondition(crossing("Boundary probe") == [.paragraphEnd, .right] && crossing("Heading golf") == [.paragraphEnd, .right]
                 && crossing("Paragraph after code delta") == [.paragraphEnd, .right], "one → beside a paragraph or heading")
    precondition(crossing("code after bullet mike", "k") == [.paragraphStart, .left, .paragraphStart])
    precondition(crossing("code after bullet mike", "k", profile: noLineKeys).prefix(3) == [.up, .up, .lineStart]
                 && crossing("code after heading hotel", "k", profile: noLineKeys).prefix(2) == [.up, .lineStart])
    precondition((1...400).contains { budget in
        guard let found = unreachableScanned(fakeTree(blocksSpec), blocksCandidates, budget: budget) else { return false }
        return found.joins.isEmpty && found.controls.isEmpty && found.markers.count == 3
    }, "running out of reads on the roots loses only the stops and labels")
    let listsThenBlocks = fakeTree("0/L/0/2 0.0/G/0/2 1/L/2/4 1.0/G/2/4 2/B/4/8 2.0/N/4/6 2.1/D/6/8 3/Q/8/10 3.0/G/8/10")
    let rootsOnly = UnreachableLines.Candidates(markers: [], chips: [], roots: true, stops: true)
    precondition(unreachableScanned(listsThenBlocks, rootsOnly)
                 == UnreachableLines.Found(markers: [], chips: [], joins: [2, 4, 8], controls: [4..<6], containers: [[3]]))
    // The roots and the second list's start are 6 reads, the code block's two children and three more starts 8, the quote's child 1.
    precondition((6...14).allSatisfy { budget in
        unreachableScanned(listsThenBlocks, rootsOnly, budget: budget) == UnreachableLines.Found(markers: [], chips: [], joins: [2])
    } && unreachableScanned(listsThenBlocks, rootsOnly, budget: 15)?.joins == [2, 4, 8], "the lists' stops are read first, as on main")
    let othersFound = unreachableScanned(fakeTree(blocksSpec, linear: false), blocksCandidates)!
    precondition(othersFound.joins.isEmpty && othersFound.controls.isEmpty && othersFound.markers.count == 3,
                 "without Linear's class another editor's quote or code gets no stop")
    precondition(folded(blocksValue, blocksRaw, fakeTree(blocksSpec, linear: false)).text.contains("\nCSS\n"))
    precondition(unreachableScanned(fakeTree(blocksSpec), UnreachableLines.candidates(text: blocksValue, breaks: blocksBreaks, raw: blocksRaw))
                 == UnreachableLines.Found(markers: othersFound.markers, chips: []), "nor does an editor that is not ProseMirror's")
    // Two quotes show nothing in the text: a ProseMirror editor's roots are read, and Linear's classes make the stop.
    let twoQuotesSpec = "0/Q/0/3 0.0/G/0/3 0.0.0/T/0/3 1/Q/3/6 1.0/G/3/6 1.0.0/T/3/6"
    let twoQuotes = fakeTree(twoQuotesSpec)
    let quoteCandidates = UnreachableLines.candidates(text: "one\ntwo", breaks: ParagraphBreaks(offsets: [3]), raw: "onetwo", proseMirror: true)
    precondition(!quoteCandidates.roots && quoteCandidates.stops && !quoteCandidates.isEmpty
                 && UnreachableLines.candidates(text: "one\ntwo", breaks: ParagraphBreaks(offsets: [3]), raw: "onetwo").isEmpty
                 && UnreachableLines.candidates(text: "one", breaks: ParagraphBreaks(), raw: "one", proseMirror: true).isEmpty,
                 "another editor's text, or a single line, asks nothing")
    precondition(unreachableScanned(twoQuotes, quoteCandidates)?.joins == [3]
                 && unreachableScanned(fakeTree(twoQuotesSpec, linear: false), quoteCandidates)?.joins == [])
    precondition(folded("one\ntwo", "onetwo", twoQuotes).breaks == ParagraphBreaks(offsets: [3], hidden: [.init(at: 4, text: "", kind: .gap)])
                 && UnreachableLines.fold(text: "a\nb", breaks: ParagraphBreaks(offsets: [1]), raw: "ab",
                                          found: .init(markers: [], chips: [], joins: [1])).breaks.gaps == [2],
                 "a stop that was read is kept though nothing folds")
    // Review round 2's case: another ProseMirror editor's lists, no marker in the text and no Linear class, get no stop.
    let bareLists = "0/G/0/1 0.0/T/0/1 1/L/1/2 1.0/G/1/2 1.0.0/T/1/2 2/L/2/3 2.0/G/2/3 2.0.0/T/2/3 3/G/3/4 3.0/T/3/4"
    let otherLists = folded("p\na\nb\nc", "pabc", fakeTree(bareLists, linear: false))
    let linearLists = folded("p\na\nb\nc", "pabc", fakeTree(bareLists))
    precondition(otherLists.breaks.gaps.isEmpty && linearLists.breaks.gaps == [4])
    precondition(chords(webPhysical("k", text: otherLists.text, caret: 4, profile: noLineKeys, breaks: otherLists.breaks)).prefix(2)
                 == [.up, .lineStart]
                 && chords(webPhysical("k", text: linearLists.text, caret: 4, profile: noLineKeys, breaks: linearLists.breaks)).prefix(3)
                 == [.up, .up, .lineStart], "one ↑ where nothing shows a stop is drawn")
    // Review round 3's case: Linear's blocks are told by their own classes wherever they stand, after any number of rules.
    for rules in 0...4 {
        let spec = (0..<rules).map { "\($0)/R/0/0" } + [
            "\(rules)/L/0/5 \(rules).0/G/0/5 \(rules).0.0/G/0/1 \(rules).0.0.0/T/0/1 \(rules).0.1/G/1/5 \(rules).0.1.0/T/1/5",
            "\(rules + 1)/Q/5/11 \(rules + 1).0/G/5/11 \(rules + 1).0.0/T/5/11",
        ]
        let model = folded("\u{2022}\nitem\nquoted", "\u{2022}itemquoted", fakeTree(spec.joined(separator: " ")))
        precondition(model.breaks.gaps == [lineStart(of: "quoted", in: model.text)]
                     && chords(webPhysical("j", text: model.text, caret: 0, profile: keyProfile, breaks: model.breaks))
                     == [.paragraphEnd, .selectRight, .right], "\(rules) rules")
    }
    let threeRules = fakeTree("0/R/0/0 1/R/0/0 2/R/0/0 3/Q/0/3 3.0/G/0/3 3.0.0/T/0/3 4/Q/3/6 4.0/G/3/6 4.0.0/T/3/6")
    precondition(unreachableScanned(threeRules, quoteCandidates)?.joins == [3])
    let section = fakeTree("""
    0/L/0/2 0.0/G/0/2 1/B/2/4 1.0/G/2/4 1.0.0/T/2/4 2/L/4/6 2.0/G/4/6 3/B/6/8 3.0/D/6/8 4/L/8/10 4.0/G/8/10 5/B/10/14 5.0/G/10/12
    5.0.0/T/10/12 5.1/E/12/13 6/L/14/16 6.0/G/14/16 7/B/16/20 7.0/G/16/18 7.0.0/T/16/18 7.1/D/18/20
    """)
    precondition(unreachableScanned(section, rootsOnly) == UnreachableLines.Found(markers: [], chips: []),
                 "a collapsible section, open or not, and code with no controls before it are not closed, and their text stays")
    // softlash/LIN-1726 evidence/tree-empty-code.jsonl: `D` leaves the label, the two images, and an empty group where the code was.
    let emptiedCode = fakeTree("""
    0/L/0/24 0.0/G/0/24 0.0.0/G/0/1 0.0.0.0/T/0/1 0.0.1/G/1/24 0.0.1.0/T/1/24 1/B/24/34 1.0/N/24/33 1.1/E/33/34 2/Q/34/59 2.0/G/34/59
    2.0.0/T/34/59
    """)
    let emptiedCodeModel = folded("\u{2022}\nBullet before code lima\nPlaintext\n\n\nQuote after code november",
                              "\u{2022}Bullet before code limaPlaintext\u{FFFC}\u{FFFC}\nQuote after code november", emptiedCode)
    precondition(emptiedCodeModel.text == "Bullet before code lima\n\nQuote after code november" && emptiedCodeModel.breaks.gaps == [24, 25]
                 && roundTrips(emptiedCodeModel), "an emptied code block keeps its label folded and its stops")

    // A to-do below an empty paragraph, and one below a quote's empty last line, as softlash/LIN-1726 measured them.
    let bareDoc: [(String, Sim.ListLine)] = [
        ("Top paragraph", .init()), ("", .init()), ("A to-do", .init(leaves: 2, checkbox: true)), ("A quote", .init(stop: true)),
        ("", .init()), ("Second to-do", .init(leaves: 2, checkbox: true, stop: true)), ("Last paragraph.", .init()),
    ]

    for profile in [keyProfile, writeKeys, removing([.lineStartKey], from: keyProfile), noLineKeys] {
        let down = String(repeating: "j", count: blockDoc.count)
        for keys in [down + String(repeating: "k", count: blockDoc.count), "3j2k4j5j3k", "9jkkkkkkkk", "5ljjjjjjjjjjjjkkkkkkkkkkkk",
                     "$jjjjjjjjjjjjkkkkkkkkkkkk", "jjjwwwwwwwwwwwwwwwwbbbbbbbbbbbbbbbb", "jjjjeeeeeeeeeeee", "jjjj2$", "jjjj0jj^jj$"] {
            var blocks = blockSim(profile)
            var plain = Sim(text: blocks.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                blocks.type(String(key))
                plain.type(String(key))
                precondition(blocks.caret == plain.caret && blocks.text == plain.text, "\(keys) at \(key)")
            }
            precondition(blocks.settleFailures == 0 && blocks.bells == 0, keys)
        }
        for keys in ["jjjjjjkkkkkk", "$jjjjjjkkkkkk", "wwwwwwwwwwbbbbbbbbbb", "jjeeeeee"] {
            var bare = blockSim(profile, bareDoc)
            var plain = Sim(text: bare.text, caret: 0, profile: profile)
            plain.emulatesKeys = true
            for key in keys {
                bare.type(String(key))
                plain.type(String(key))
                precondition(bare.caret == plain.caret && bare.text == plain.text, "bare \(keys) at \(key)")
            }
            precondition(bare.settleFailures == 0 && bare.bells == 0, "bare \(keys)")
        }
    }
    // Quotes alone, a paragraph shaped like a marker above them, and a to-do below an empty line: each stop is read (LIN-1726).
    for (doc, caret, landing) in [
        ([("one", Sim.ListLine()), ("two", .init(stop: true))], 0, 4),
        ([("1.", .init()), ("one", .init()), ("two", .init(stop: true))], 3, 7),
        ([("", .init()), ("task", .init(leaves: 2, checkbox: true)), ("quoted", .init(stop: true))], 1, 6),
    ] {
        var host = blockSim(keyProfile, doc, caret: caret)
        host.type("j")
        precondition(host.caret == landing && host.settleFailures == 0 && host.bells == 0, "\(doc.map(\.0))")
    }
    // A paragraph made a quote, or a quote made a paragraph, keeps the text and the block count: the stops are read again.
    var quoted = blockSim(keyProfile, [("item", .init(marker: "\u{2022}")), ("one", .init()), ("two", .init())], caret: 9)
    quoted.type("k")
    quoted.listLines?[1].stop = true
    quoted.type("k")
    quoted.type("j")
    precondition(quoted.caret == 5 && quoted.settleFailures == 0 && quoted.bells == 0, "a stop made after the last read")
    var unquoted = blockSim(keyProfile, [
        ("item", .init(marker: "\u{2022}")), ("one", .init(stop: true)), ("task", .init(leaves: 2, checkbox: true, stop: true)),
    ], caret: 0)
    unquoted.type("j")
    unquoted.listLines?[1].stop = false
    unquoted.listLines?[2].stop = false
    unquoted.type("j")
    precondition(unquoted.caret == 9 && unquoted.settleFailures == 0 && unquoted.bells == 0, "a stop gone since the last read")
}
