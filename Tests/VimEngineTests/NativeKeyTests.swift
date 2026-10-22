// MARK: - Native keys (nativeMotions)

// The probe claims every native key where the caret reads.
let claimedKeys = Capability.nativeKeys

let nativeRead = adding(claimedKeys.union([.nativeMotions]), to: readProfile)
let nativeAX = adding(claimedKeys.union([.nativeMotions]), to: axProfile)
let nativeBlind = CapabilityProfile(available: [.nativeMotions])

func wordBlame(_ p: Int) -> Expectation.Blame { Expectation.Blame(capability: .wordKeys, unmoved: [p..<p]) }
func capped(_ expectation: Expectation, _ longest: Int) -> Expectation {
    var capped = expectation
    capped.longest = longest
    return capped
}
func kept(_ expectation: Expectation, _ slot: Int) -> Expectation {
    var kept = expectation
    kept.keeps = slot
    return kept
}
let spanBlame = Expectation.Blame(capability: .wordKeys, unmoved: [])
func proven(_ within: Range<Int>, length: Int) -> Expectation {
    var proven = capped(Expectation(landing: .between(0, 1), length: length, blame: spanBlame), within.count)
    proven.within = within
    return proven
}
func selectedBack(_ end: Landing, length: Int, within: Range<Int>) -> [PhysicalStep] {
    [.press(.wordRight, count: 1), .settle(kept(Expectation(landing: end, length: length), 1)),
     .press(.selectWordLeft, count: 1), .settle(proven(within, length: length))]
}
func moveBlame(_ atom: Capability, _ p: Int?) -> Expectation.Blame {
    Expectation.Blame(capability: atom, unmoved: p.map { [$0..<$0] } ?? [], leavesCaret: true)
}
func webMoveBlame(_ atom: Capability, _ p: Int?) -> Expectation.Blame {
    Expectation.Blame(capability: atom, unmoved: [], leavesCaret: true,
                      exemptions: p.map { [.init(.webContent, unmoved: [$0..<$0])] } ?? [])
}

// In Chromium text content checks leave in field offsets, and a boundary caret names its side.
let chromiumBreak = ParagraphBreaks(offsets: [2])

let nativeThreeParagraphs = "one two\nthree four\nfive six"

func testNativeKeys() {
    let lineKeys = claimedKeys.subtracting([.wordKeys, .paragraphKeys])

    let nativeBlockRead = adding(claimedKeys.union([.nativeMotions]), to: CapabilityProfile(available: [
        .readText, .readLength, .readCaret, .readSelectedText,
    ]))

    let prose = "say hello world"
    let nativeParagraphs = "alpha beta\ngamma delta\n\nepsilon zeta"

    // With the option off, plans are unchanged.
    let nativeCorpus = ["w", "3w", "e", "b", "ge", "W", "ciw", "diw", "yiw", "caw", "d2iw", "ciW", "dw", "d3w", "de",
                        "cw", "db", "yw", "}", "{", "3}", "gj", "gk", "<C-f>", "<C-b>", "d}", "x", "dd", "j", "k", "$"]
    for base in [axProfile, readProfile, blindProfile, blockProfile, noInsertProfile] {
        for keys in nativeCorpus {
            precondition(
                physical(keys, text: prose + "\nnext line", caret: 6, profile: adding(claimedKeys, to: base))
                    == physical(keys, text: prose + "\nnext line", caret: 6, profile: adding(lineKeys, to: base)),
                "claimed keys without nativeMotions changed \(keys)"
            )
        }
    }
    for keys in ["}", "{", "gj", "gk", "<C-f>", "<C-b>"] {
        precondition(physical(keys, text: nativeParagraphs, caret: 3, profile: adding(claimedKeys, to: readProfile)).steps == [.bell])
    }

    precondition(physical("w", text: prose, caret: 6, profile: nativeRead).steps == [
        .press(.wordRight, count: 1),
        .settle(Expectation(landing: .caretAfter(6, strict: true), length: 15, blame: moveBlame(.wordKeys, 6))),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("e", text: prose, caret: 6, profile: nativeRead) == physical("w", text: prose, caret: 6, profile: nativeRead))
    precondition(physical("3w", text: prose, caret: 0, profile: nativeRead).steps.first == .press(.wordRight, count: 3))
    precondition(physical("b", text: prose, caret: 6, profile: nativeRead).steps == [
        .press(.wordLeft, count: 1),
        .settle(Expectation(landing: .caretBefore(6, strict: true), length: 15, blame: moveBlame(.wordKeys, 6))),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("b", text: prose, caret: 0, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretBefore(0, strict: false), length: 15, blame: moveBlame(.wordKeys, nil))))
    precondition(physical("w", text: prose, caret: 15, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(15, strict: false), length: 15, blame: moveBlame(.wordKeys, nil))))
    precondition(physical("w", text: "ab\ncd\nef", caret: 6, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(6, strict: true), length: 8, blame: moveBlame(.wordKeys, 6))))

    precondition(webPhysical("w", text: "ab\ncd", caret: 3, profile: nativeRead, breaks: chromiumBreak).steps[1]
        == .settle(Expectation(landing: .caretAfter(2, strict: true), length: 5, blame: webMoveBlame(.wordKeys, 2))))
    precondition(webPhysical("w", text: "ab\ncd", caret: 2, profile: nativeRead, breaks: chromiumBreak).steps[1]
        == .settle(Expectation(landing: .caretAfter(2, strict: false), length: 5, blame: moveBlame(.wordKeys, nil))))
    let boundaryCiw = webPhysical("ciw", text: "ab\ncd", caret: 2, profile: nativeRead, breaks: chromiumBreak).steps
    precondition(boundaryCiw[2] == .settle(kept(Expectation(landing: .exact(2..<2), length: 5, edge: .paragraphStart), 0)))
    precondition(boundaryCiw[6] == .settle(kept(Expectation(landing: .exact(2..<2), length: 5, edge: .paragraphEnd), 1)))
    precondition(webPhysical("w", text: "ab\ncd\nef", caret: 6, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(6, strict: true), length: 8, blame: webMoveBlame(.wordKeys, 6))))
    precondition(webPhysical("ciw", text: prose, caret: 6, profile: nativeRead).steps.allSatisfy {
        guard case .settle(let expectation) = $0 else { return true }
        return expectation.checkedKey == nil
    })
    precondition(physical("w", text: "ab\ncd\nef", caret: 5, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(5, strict: true), length: 8, blame: moveBlame(.wordKeys, 5))))
    precondition(physical("w", text: prose, selection: 4..<9, profile: nativeRead).steps.prefix(2)
        == [.press(.left, count: 1), .press(.wordRight, count: 1)])

    let nativeCiw = physical("ciw", text: prose, caret: 4, profile: nativeRead)
    precondition(nativeCiw.steps == [
        .press(.wordRight, count: 1),
        .press(.wordLeft, count: 1),
        .settle(kept(Expectation(landing: .caretBefore(4, strict: false), length: 15), 0)),
    ] + selectedBack(.caretAfter(4, strict: true), length: 15, within: 4..<9) + [
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(nil)),
    ])
    precondition(nativeCiw.mutatesText)
    precondition(physical("diw", text: prose, caret: 8, profile: nativeRead).steps.suffix(3) == [
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("yiw", text: prose, caret: 6, profile: nativeRead).steps.suffix(4) == [
        .clipboardCopy,
        .commit(.yanked(into: nil, content: .pasteboard, wise: .character)),
        .press(.left, count: 1),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("\"_diw", text: prose, caret: 6, profile: nativeRead).steps.suffix(2)
        == [.press(.deleteBack, count: 1), .commit(.setCursor(nil))])
    // The character under the caret picks the keys, so no dictionary is needed.
    let roundTripKeys: [PhysicalStep] = [.press(.wordRight, count: 1), .press(.wordLeft, count: 1)]
    precondition(physical("ciw", text: prose, caret: 6, profile: nativeRead).steps.prefix(7) == roundTripKeys + [
        .settle(kept(Expectation(landing: .caretBefore(6, strict: false), length: 15), 0)),
    ] + selectedBack(.caretAfter(6, strict: true), length: 15, within: 4..<9))
    precondition(physical("ciw", text: prose, caret: 9, profile: nativeRead).steps.prefix(9) == roundTripKeys + [
        .settle(kept(Expectation(landing: .exact(10..<10), length: 15), 0)),
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .caretBefore(9, strict: true), length: 15), 0)),
    ] + selectedBack(.exact(9..<9), length: 15, within: 4..<9))
    precondition(physical("ciw", text: prose, caret: 15, profile: nativeRead).steps.prefix(7) == roundTripKeys + [
        .settle(kept(Expectation(landing: .caretBefore(15, strict: false), length: 15), 0)),
    ] + selectedBack(.exact(15..<15), length: 15, within: 10..<15))
    precondition(physical("ciw", text: "今天天气很好", caret: 2, profile: nativeRead).steps.prefix(7) == roundTripKeys + [
        .settle(kept(Expectation(landing: .caretBefore(2, strict: false), length: 6), 0)),
    ] + selectedBack(.caretAfter(2, strict: true), length: 6, within: 0..<6))
    precondition(physical("ciw", text: "one two\nthree four", caret: 13, profile: nativeRead).steps.prefix(9) == roundTripKeys + [
        .settle(kept(Expectation(landing: .exact(14..<14), length: 18), 0)),
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .caretBefore(13, strict: true), length: 18), 0)),
    ] + selectedBack(.exact(13..<13), length: 18, within: 8..<13))
    for demoted in [Capability.lineStartKey, .lineEndKey] {
        precondition(physical("ciw", text: "abc def\nghi", caret: 7, profile: removing([demoted], from: nativeRead))
            == physical("ciw", text: "abc def\nghi", caret: 7, profile: nativeRead))
    }
    precondition(physical("ciw", text: "abc\n\ndef", caret: 3, profile: nativeRead).steps.prefix(9) == roundTripKeys + [
        .settle(kept(Expectation(landing: .exact(5..<5), length: 8), 0)),
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .caretBefore(3, strict: true), length: 8), 0)),
    ] + selectedBack(.exact(3..<3), length: 8, within: 0..<3))
    for (text, caret) in [("   ", 1), ("a  b", 2), ("• b", 1), ("a\n\nb", 2)] {
        precondition(physical("ciw", text: text, caret: caret, profile: nativeRead).steps == [.bell], text)
    }

    precondition(physical("dw", text: prose, caret: 4, profile: nativeRead).steps == [
        .press(.wordRight, count: 1), .settle(kept(Expectation(landing: .caretAfter(4, strict: true), length: 15), 1)),
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .exact(4..<4), length: 15), 0)),
        .press(.selectWordRight, count: 1),
        .settle(proven(4..<9, length: 15)),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("dw", text: prose, caret: 6, profile: nativeRead).steps.prefix(2) == [
        .press(.selectWordRight, count: 1),
        .settle(Expectation(landing: .exact(6..<9), length: 15, blame: wordBlame(6))),
    ])
    precondition(physical("d3w", text: prose, caret: 0, profile: nativeRead).steps.first == .press(.wordRight, count: 3))
    precondition(physical("cw", text: prose, caret: 4, profile: nativeRead).steps.prefix(2)
        == physical("dw", text: prose, caret: 4, profile: nativeRead).steps.prefix(2))
    precondition(physical("de", text: prose, caret: 4, profile: nativeRead).steps
        == physical("dw", text: prose, caret: 4, profile: nativeRead).steps)
    precondition(physical("db", text: prose, caret: 9, profile: nativeRead).steps.prefix(6) == [
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .caretBefore(9, strict: true), length: 15), 0)),
        .press(.wordRight, count: 1), .settle(kept(Expectation(landing: .exact(9..<9), length: 15), 1)),
        .press(.selectWordLeft, count: 1),
        .settle(proven(4..<9, length: 15)),
    ])
    precondition(physical("db", text: prose, caret: 8, profile: nativeRead).steps.first == .press(.selectWordLeft, count: 1))
    precondition(physical("yw", text: prose, caret: 4, profile: nativeRead).steps.contains(.clipboardCopy))
    precondition(physical("dw", text: "今天天气很好", caret: 2, profile: nativeRead).steps.prefix(6) == [
        .press(.wordRight, count: 1), .settle(kept(Expectation(landing: .caretAfter(2, strict: true), length: 6), 1)),
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .exact(2..<2), length: 6), 0)),
        .press(.selectWordRight, count: 1),
        .settle(proven(2..<6, length: 6)),
    ])
    precondition(physical("db", text: "今天天气很好", caret: 4, profile: nativeRead).steps.prefix(6) == [
        .press(.wordLeft, count: 1), .settle(kept(Expectation(landing: .caretBefore(4, strict: true), length: 6), 0)),
        .press(.wordRight, count: 1), .settle(kept(Expectation(landing: .exact(4..<4), length: 6), 1)),
        .press(.selectWordLeft, count: 1),
        .settle(proven(0..<4, length: 6)),
    ])

    for keys in ["caw", "d2iw", "ciW", "W", "dW", "ge", "x", "dd", "$", "dj", "yk", "+", "-"] {
        precondition(physical(keys, text: prose, caret: 6, profile: nativeRead)
            == physical(keys, text: prose, caret: 6, profile: adding(claimedKeys, to: readProfile)),
            "nativeMotions must leave \(keys) alone")
    }
    let wordsDemoted = removing([.wordKeys], from: nativeRead)
    for keys in ["w", "b", "ciw", "dw", "db"] {
        precondition(physical(keys, text: prose, caret: 6, profile: wordsDemoted)
            == physical(keys, text: prose, caret: 6, profile: removing([.nativeMotions], from: wordsDemoted)),
            "demoted wordKeys must count \(keys)")
    }
    precondition(physical("}", text: nativeParagraphs, caret: 3, profile: removing([.paragraphKeys], from: nativeRead)).steps
        == [.bell])

    precondition(physical("}", text: nativeParagraphs, caret: 3, profile: nativeRead).steps == [
        .press(.paragraphForward, count: 1),
        .settle(Expectation(
            landing: .caretAfter(3, strict: true), length: 36,
            blame: moveBlame(.paragraphKeys, 3)
        )),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("3{", text: nativeParagraphs, caret: 14, profile: nativeRead).steps.first
        == .press(.paragraphBackward, count: 3))
    precondition(physical("}", text: nativeParagraphs, caret: 36, profile: nativeRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(36, strict: false), length: 36, blame: moveBlame(.paragraphKeys, nil))))
    precondition(physical("gj", text: nativeParagraphs, caret: 3, profile: nativeRead).steps == [
        .press(.down, count: 1),
        .settle(Expectation(landing: .caretAfter(3, strict: true), length: 36)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("gk", text: nativeParagraphs, caret: 14, profile: nativeRead).steps[0...1] == [
        .press(.up, count: 1), .settle(Expectation(landing: .caretBefore(14, strict: true), length: 36)),
    ])
    precondition(physical("<C-f>", text: nativeParagraphs, caret: 3, profile: nativeRead).steps[0...1] == [
        .press(.pageForward, count: 1), .settle(Expectation(landing: .caretAfter(3, strict: true), length: 36)),
    ])
    precondition(physical("2<C-b>", text: nativeParagraphs, caret: 14, profile: nativeRead).steps.first
        == .press(.pageBackward, count: 2))
    // `j`/`k` press ↓/↑ only once ⌃E/⌃A are demoted.
    for keys in ["j", "3j", "k", "2k"] {
        precondition(physical(keys, text: nativeParagraphs, caret: 14, profile: nativeRead)
            == physical(keys, text: nativeParagraphs, caret: 14, profile: removing([.nativeMotions], from: nativeRead)), keys)
    }
    precondition(physical("j", text: nativeParagraphs, caret: 3, profile: removing([.lineEndKey], from: nativeRead)).steps == [
        .press(.down, count: 1),
        .settle(Expectation(landing: .caretAfter(3, strict: true), length: 36)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("3k", text: nativeParagraphs, caret: 30, profile: removing([.lineStartKey], from: nativeRead)).steps[0...1] == [
        .press(.up, count: 3), .settle(Expectation(landing: .caretBefore(30, strict: true), length: 36)),
    ])
    precondition(physical("k", text: nativeParagraphs, caret: 30, profile: removing([.lineEndKey], from: nativeRead))
        == physical("k", text: nativeParagraphs, caret: 30, profile: removing([.lineEndKey, .nativeMotions], from: nativeRead)))
    precondition(physical("j", text: "one block", caret: 2, profile: nativeBlockRead)
        == physical("j", text: "one block", caret: 2, profile: removing([.nativeMotions], from: nativeBlockRead)))
    // ⇧⌥↓ lands elsewhere than ⌥↓ (measured), so operators and Visual ring.
    for keys in ["d}", "y{", "dgj", "d<C-f>"] {
        precondition(physical(keys, text: nativeParagraphs, caret: 3, profile: nativeRead).steps == [.bell], keys)
    }
    var nativeVisual = VimState.initial
    nativeVisual.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: 3))
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("}"), state: nativeVisual),
        snapshot: FieldSnapshot(capabilities: nativeRead, text: nativeParagraphs, selection: 3..<4, anchor: 3)
    ).steps == [.bell])

    for keys in ["w", "b", "e", "ciw", "dw", "db", "j", "k"] {
        precondition(physical(keys, text: prose, caret: 6, profile: nativeAX)
            == physical(keys, text: prose, caret: 6, profile: adding(claimedKeys, to: axProfile)), keys)
    }
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("}"), state: .initial),
        snapshot: FieldSnapshot(capabilities: nativeAX, text: nativeParagraphs, selection: 3..<4, cursor: 3..<4)
    ).steps == [
        .setSelection(3..<3),
        .press(.paragraphForward, count: 1),
        .settle(Expectation(
            landing: .caretAfter(3, strict: true), length: 36,
            blame: moveBlame(.paragraphKeys, 3)
        )),
        .commit(.setCursor(nil)),
    ])

    precondition(physical("ciw", profile: nativeBlind).steps == [
        .press(.wordRight, count: 1),
        .press(.wordLeft, count: 1),
        .press(.selectWordRight, count: 1),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(nil)),
    ])
    for keys in ["w", "b", "e", "dw", "db", "yw", "3j", "k"] {
        precondition(physical(keys, profile: nativeBlind) == physical(keys, profile: blindProfile), keys)
    }
    precondition(physical("}", profile: nativeBlind).steps == [.press(.paragraphForward, count: 1), .commit(.setCursor(nil))])
    precondition(physical("3gj", profile: nativeBlind).steps == [.press(.down, count: 3), .commit(.setCursor(nil))])
    precondition(physical("<C-b>", profile: nativeBlind).steps == [.press(.pageBackward, count: 1), .commit(.setCursor(nil))])

    precondition(physical("}", text: "one block", caret: 2, profile: nativeBlockRead).steps
        == [.press(.paragraphForward, count: 1), .commit(.setCursor(nil))])
    precondition(physical("w", text: "one block", caret: 0, profile: nativeBlockRead).steps[1]
        == .settle(Expectation(landing: .caretAfter(0, strict: true), length: 9, blame: moveBlame(.wordKeys, 0))))
    precondition(physical("}", text: "one block", caret: 2, profile: adding(claimedKeys.union([.nativeMotions]), to: blockProfile)).steps
        == [.press(.paragraphForward, count: 1), .commit(.setCursor(nil))])

    precondition(KeyNotation.token(keyCode: 3, chord: [.control], characters: controlCharacter("f"), profile: nativeRead) == "<C-f>")
    precondition(KeyNotation.token(keyCode: 11, chord: [.control], characters: controlCharacter("b"), profile: nativeBlind) == "<C-b>")
    precondition(KeyNotation.token(keyCode: 3, chord: [.control], characters: controlCharacter("f"), profile: readProfile) == nil)
    precondition(KeyNotation.token(keyCode: 3, chord: [.control], characters: controlCharacter("f")) == nil)
    precondition(KeyNotation.token(keyCode: 2, chord: [.control], characters: controlCharacter("d"), profile: nativeRead) == nil)

    for (doc, word, carets) in [
        (prose, 4..<9, [4, 6, 8, 9]), ("abc def\nghi", 4..<7, [7]), ("\nx\ny", 1..<2, [1]),
        (nativeThreeParagraphs, 8..<13, [8, 10, 12, 13]), (nativeThreeParagraphs, 19..<23, [19, 21, 23]), (nativeThreeParagraphs, 14..<18, [18]),
    ] {
        for caret in carets {
            var keyed = keyedSim(doc, caret: caret)
            keyed.type("ciwX")
            keyed.feed("<Esc>")
            let context = "ciw at \(caret) in \(doc.debugDescription): \(keyed.text.debugDescription)"
            precondition(keyed.text == TextModel(doc).replacing(word, with: "X"), context)
            precondition(keyed.pasteboard == TextModel(doc).substring(word), context)
            precondition(keyed.settleFailures == 0 && keyed.unsupportedSteps == 0 && keyed.state.field.mode == .normal, context)
        }
        // Uncorrected Chromium reads: these carets get their word or nothing.
        for caret in carets {
            var misread = keyedSim(doc, caret: caret, chromium: true)
            misread.type("ciw")
            precondition(misread.pasteboard == nil ? misread.text == doc : misread.pasteboard == TextModel(doc).substring(word),
                         "ciw at \(caret) in \(doc.debugDescription) under Chromium's reads")
        }
    }

    for chromium in [false, true] {
        for (keys, caret, landing) in [("w", 10, 13), ("e", 10, 13), ("3w", 0, 13), ("b", 10, 8), ("}", 10, 18), ("{", 10, 8),
                                       ("2}", 1, 18), ("b", 8, 4)] {
            var keyed = keyedSim(nativeThreeParagraphs, caret: caret, chromium: chromium)
            keyed.type(keys)
            precondition(keyed.caret == landing && keyed.settleFailures == 0 && keyed.unsupportedSteps == 0,
                         "\(keys) from \(caret), chromium=\(chromium) landed \(keyed.caret)")
        }
    }
    var dwKeyed = keyedSim(prose, caret: 4)
    dwKeyed.type("dw")
    precondition(dwKeyed.text == "say  world" && dwKeyed.pasteboard == "hello" && dwKeyed.settleFailures == 0)
    var dbKeyed = keyedSim(prose, caret: 9)
    dbKeyed.type("db")
    precondition(dbKeyed.text == "say  world" && dbKeyed.pasteboard == "hello")
    var cwKeyed = keyedSim(nativeThreeParagraphs, caret: 8)
    cwKeyed.type("cwX")
    cwKeyed.feed("<Esc>")
    precondition(cwKeyed.text == "one two\nX four\nfive six" && cwKeyed.settleFailures == 0)
    var emptyLineKeyed = keyedSim("a\n\nb", caret: 2)
    emptyLineKeyed.type("ciw")
    precondition(emptyLineKeyed.text == "a\n\nb" && emptyLineKeyed.selection.isEmpty && emptyLineKeyed.bells == 1)

    let wrappedProse = "alpha beta gamma delta\nnext line"
    var rowKeyed = keyedSim(wrappedProse, caret: 3)
    rowKeyed.wrapWidth = 8
    rowKeyed.type("gj")
    precondition(rowKeyed.caret == 11 && rowKeyed.settleFailures == 0)
    rowKeyed.type("gk")
    precondition(rowKeyed.caret == 3 && rowKeyed.settleFailures == 0)
    let longText = (1...30).map { "line \($0)" }.joined(separator: "\n")
    var pageKeyed = keyedSim(longText, caret: 0)
    pageKeyed.type("\u{06}")
    precondition(pageKeyed.caret == TextModel(longText).verticalMove(from: 0, by: 10, firstNonBlank: false)
                 && pageKeyed.settleFailures == 0)
    pageKeyed.type("\u{02}")
    precondition(pageKeyed.caret == 0 && pageKeyed.settleFailures == 0)

    var hopKeyed = keyedSim(wrappedProse, caret: 3)
    hopKeyed.wrapWidth = 8
    hopKeyed.type("j")
    precondition(hopKeyed.caret == 26 && hopKeyed.settleFailures == 0)
    var rowFallback = keyedSim(wrappedProse, caret: 3, profile: removing([.lineEndKey], from: nativeRead))
    rowFallback.wrapWidth = 8
    rowFallback.type("j")
    precondition(rowFallback.caret == 11 && rowFallback.settleFailures == 0)

    for (doc, caret, keys, ignored, atom) in [
        (nativeThreeParagraphs, 10, "w", Chord.wordRight, Capability.wordKeys), (prose, 4, "ciw", .selectWordLeft, .wordKeys),
        (nativeThreeParagraphs, 10, "}", .paragraphForward, .paragraphKeys),
    ] {
        var ignoring = keyedSim(doc, caret: caret)
        ignoring.ignoredChords = [ignored]
        ignoring.type(keys)
        precondition(ignoring.blamed == [atom] && ignoring.text == doc, "\(keys) ignoring \(ignored)")
    }
    var rebound = keyedSim(nativeThreeParagraphs, caret: 10)
    rebound.reboundChords = [.wordRight: .selectAll]
    rebound.type("w")
    precondition(rebound.blamed == [.wordKeys] && rebound.text == nativeThreeParagraphs)
    for (keys, caret) in [("ciw", 0), ("diw", 10), ("yiw", 14), ("dw", 0), ("db", 13)] {
        var grabbing = keyedSim(nativeThreeParagraphs, caret: caret)
        grabbing.reboundChords = [.selectWordRight: .selectAll, .selectWordLeft: .selectAll]
        grabbing.type(keys)
        precondition(grabbing.text == nativeThreeParagraphs && grabbing.pasteboard == nil && grabbing.selection.isEmpty
                     && (grabbing.blamed == [.wordKeys] || !keys.hasSuffix("iw")), keys)
    }
    // ← collapses a failed check's selection before typing.
    var strandedKeyed = keyedSim(prose, caret: 4)
    strandedKeyed.reboundChords = [.selectWordLeft: .selectAll]
    strandedKeyed.type("ciwX")
    precondition(strandedKeyed.text == "X" + prose && strandedKeyed.pasteboard == nil, strandedKeyed.text)
    var strandedIgnored = keyedSim(prose, caret: 4)
    strandedIgnored.reboundChords = [.selectWordLeft: .selectAll]
    strandedIgnored.ignoredChords = [.left]
    strandedIgnored.type("ciw")
    precondition(strandedIgnored.state.field.mode == .normal && strandedIgnored.selection == 0..<15)
    precondition(strandedIgnored.settleFailures == 2, "the repair's own settle fails where the field ignores ←")
    var strandedPlain = Sim(text: prose, caret: 4, profile: readProfile)
    strandedPlain.reboundChords = [.selectRight: .selectAll]
    strandedPlain.type("x")
    precondition(strandedPlain.selection == 0..<0 && strandedPlain.settleFailures == 1)
    strandedPlain.reboundChords = [:]
    strandedPlain.type("iX")
    precondition(strandedPlain.text == "X" + prose, "i types beside a stranded selection, not over it")
    // Mid-word in a joined run a span rings; from a word's end it is proven.
    precondition(physical("dw", text: "foo,bar", caret: 1, profile: nativeRead).steps == [.bell])
    precondition(physical("db", text: "foo,bar", caret: 6, profile: nativeRead).steps == [.bell])
    precondition(physical("dw", text: "foo,bar", caret: 3, profile: nativeRead).steps.prefix(6) == [
        .press(.wordRight, count: 1), .settle(kept(Expectation(landing: .caretAfter(3, strict: true), length: 7), 1)),
        .press(.wordLeft, count: 2), .press(.wordRight, count: 1),
        .settle(kept(Expectation(landing: .exact(3..<3), length: 7), 0)),
        .press(.selectWordRight, count: 1),
    ])
    for (keys, caret) in [("dw", 3), ("dw", 4), ("db", 3), ("db", 4), ("ciw", 1), ("dw", 1)] {
        var reaching = keyedSim("foo,bar baz", caret: caret)
        reaching.reboundChords = [.selectWordRight: .selectLineEnd, .selectWordLeft: .selectAll]
        reaching.type(keys)
        precondition(reaching.text == "foo,bar baz" && reaching.pasteboard == nil && reaching.selection.isEmpty, "\(keys) at \(caret)")
    }
    var honestSpan = keyedSim("foo,bar", caret: 3)
    honestSpan.type("dw")
    precondition(honestSpan.text == "foo" && honestSpan.pasteboard == ",bar" && honestSpan.settleFailures == 0, honestSpan.text)
    for (keys, caret) in [("ciw", 0), ("diw", 5), ("ciw", 7), ("dw", 0), ("db", 7)] {
        var grabbing = keyedSim("foo.bar", caret: caret)
        grabbing.reboundChords = [.selectWordRight: .selectAll, .selectWordLeft: .selectAll]
        grabbing.type(keys)
        precondition(grabbing.text == "foo.bar" && grabbing.pasteboard == nil && grabbing.selection.isEmpty, "\(keys) at \(caret) in one run")
    }
    // Raw reads may show a move into an empty paragraph as unmoved: it rings, unblamed.
    for (keys, caret) in [("}", 2), ("gj", 2), ("gj", 3), ("{", 4), ("gk", 4)] {
        var empty = keyedSim("ab\n\ncd", caret: caret, chromium: true)
        empty.type(keys)
        precondition(empty.blamed.isEmpty, "\(keys) from \(caret) across an empty paragraph")
    }
    var gjIgnored = keyedSim(nativeThreeParagraphs, caret: 10)
    gjIgnored.ignoredChords = [.down]
    gjIgnored.type("gj")
    precondition(gjIgnored.blamed.isEmpty && gjIgnored.settleFailures == 1)

    // App `w` stops at a word's end, hence `ww` before `.`.
    var dotKeyed = keyedSim("ab cd ef", caret: 0)
    dotKeyed.type("ciwX")
    dotKeyed.feed("<Esc>")
    dotKeyed.type("ww.")
    precondition(dotKeyed.text == "X X ef" && dotKeyed.settleFailures == 0, dotKeyed.text)
}

// MARK: - Native keys in lane B

let keyProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .wholeDocument,
    .lineStartKey, .lineEndKey, .documentStartKey, .documentEndKey,
])

func webBlame(_ keys: String, caret: Int, breaks: ParagraphBreaks) -> Expectation.Blame? {
    webPhysical(keys, text: "ab\ncdef", caret: caret, profile: keyProfile, breaks: breaks).steps.lazy.compactMap {
        guard case .settle(let expectation) = $0 else { return nil }
        return expectation.blame
    }.first
}

func testNativeKeysInLaneB() {
    precondition(Capability.nativeKeys.allSatisfy { $0.species == .mechanism && $0.parent == nil })
    precondition(Capability.lineStartKey.rawValue == "lineStartKey")

    let keyedDD = physical("dd", text: "one\ntwo\nthree", caret: 5, profile: keyProfile)
    precondition(keyedDD.traceShape == "P!P!P!!P?CC")
    precondition(Array(keyedDD.steps[0...6]) == [
        .press(.paragraphStart, count: 1),
        .settle(Expectation(
            landing: .exact(4..<4), length: 13,
            blame: .init(capability: .lineStartKey, unmoved: [5..<5], leavesCaret: true, offTarget: true)
        )),
        .press(Chord.paragraphEnd.shifted, count: 1),
        .settle(Expectation(
            landing: .exact(4..<7), length: 13,
            blame: .init(capability: .lineEndKey, unmoved: [4..<4], selects: true, offTarget: true)
        )),
        .press(.selectRight, count: 1),
        .settle(Expectation(selection: 4..<8, length: 13)),
        .settle(Expectation(selection: 4..<8, length: 13, selectedText: "two\n")),
    ])
    // A delete checks the text the field selected; a yank within a line takes it, since Chromium's leaves out breaks.
    precondition(keyedDD.steps.contains(.commit(.deleted(into: nil, content: .literal("two\n"), wise: .line))))
    precondition(physical("y$", text: "one\ntwo", caret: 5, profile: keyProfile).steps
                 .contains(.commit(.yanked(into: nil, content: .captured(CaptureSlot(id: 0)), wise: .character))))
    precondition(physical("yy", text: "one\ntwo\nthree", caret: 5, profile: keyProfile).steps
                 .contains(.commit(.yanked(into: nil, content: .literal("two\n"), wise: .line))))

    let oneLine = "one two"
    precondition(chords(physical("0", text: oneLine, caret: 5, profile: keyProfile)) == [.paragraphStart])
    precondition(chords(physical("$", text: oneLine, caret: 1, profile: keyProfile)) == [.paragraphEnd])
    precondition(chords(physical("D", text: oneLine, caret: 2, profile: keyProfile)) == [Chord.paragraphEnd.shifted, .deleteBack])
    precondition(chords(physical("d0", text: oneLine, caret: 4, profile: keyProfile)) == [Chord.paragraphStart.shifted, .deleteBack])
    precondition(chords(physical("cc", text: oneLine, caret: 2, profile: keyProfile))
                 == [.paragraphStart, Chord.paragraphEnd.shifted, .deleteBack])
    precondition(chords(physical("yy", text: oneLine, caret: 2, profile: keyProfile))
                 == [.paragraphStart, Chord.paragraphEnd.shifted, .selectRight, .left])
    precondition(chords(physical("gg", text: "one\ntwo", caret: 5, profile: keyProfile)) == [.documentStart])
    precondition(chords(physical("G", text: "one\ntwo", caret: 1, profile: keyProfile)) == [.documentEnd, .paragraphStart])
    precondition(chords(physical("j", text: "one\ntwo", caret: 1, profile: keyProfile)) == [.paragraphEnd, .right, .right])
    precondition(chords(physical("dG", text: "one\ntwo", caret: 1, profile: keyProfile))
                 == [.paragraphStart, Chord.documentEnd.shifted, .deleteBack])
    let keyedO = physical("o", text: oneLine, caret: 2, profile: keyProfile)
    precondition(chords(keyedO) == [.paragraphEnd] && keyedO.steps.contains(.typeText("\n")))
    precondition(chords(physical("O", text: oneLine, caret: 2, profile: keyProfile)) == [.paragraphStart, .paragraphStart, .left])
    let webO = webPhysical("o", text: oneLine, caret: 2, profile: keyProfile)
    precondition(chords(webO) == [.paragraphEnd] && webO.steps.contains(.clipboardInsert("\n"))
                 && !webO.steps.contains(.typeText("\n")))
    let webAbove = webPhysical("O", text: "ab\ncd", caret: 4, profile: keyProfile, breaks: ParagraphBreaks(offsets: [2])).steps
    let pasted = webAbove.firstIndex(of: .clipboardInsert("\n"))!
    precondition(chords(PhysicalPlan(steps: webAbove)) == [.paragraphStart, .paragraphStart, .left])
    precondition(webAbove[pasted + 1] == .softSettle(Expectation(selection: nil, length: 6)))
    precondition(webAbove[(pasted + 2)...].allSatisfy {
        guard case .settle(let expectation) = $0 else { return true }
        return expectation.length == nil && expectation.selection == nil
    })
    let rowKeys = adding([.nativeMotions], to: removing([.lineStartKey], from: keyProfile))
    let rowAbove = webPhysical("O", text: "ab\ncd", caret: 4, profile: rowKeys, breaks: ParagraphBreaks(offsets: [2])).steps
    precondition(chords(PhysicalPlan(steps: rowAbove)) == [.selectLeft, .left, .up])
    precondition(rowAbove[rowAbove.firstIndex(of: .press(.up, count: 1))! + 1] == .settle(Expectation(landing: nil)),
                 "↑ past a pasted newline settles as blind as ⌃A does")
    for (keys, text) in [("oZ", "ab\nZ\ncd"), ("OZ", "Z\nab\ncd")] {
        var sim = Sim(text: "ab\ncd", caret: 1, profile: keyProfile)
        sim.webContent = true
        sim.emulatesKeys = true
        sim.type(keys)
        precondition(sim.text == text && sim.state.session.register("\"") == nil, "\(keys) in web content")
    }
    precondition(webPhysical("g~j", text: "ab\ncd", caret: 0, profile: readProfile).steps.contains {
        guard case .clipboardInsert(let text?) = $0 else { return false }
        return text.contains("\n")
    })
    // `x` and `X` keep their checked select-then-delete: ⌦ or ⌫ would delete before any check, and join lines at an end.
    precondition(chords(physical("x", text: oneLine, caret: 2, profile: keyProfile)) == [.selectRight, .deleteBack])
    let longLine = "a\n" + String(repeating: "word ", count: 16) + "\ne"
    precondition(chords(physical("dd", text: longLine, caret: 42, profile: keyProfile)).count == 4)
    precondition(chords(physical("dd", text: longLine, caret: 42, profile: readProfile)).count == 122)

    // A key the field lacks falls back to counting, exactly as before.
    for keys in ["dd", "0", "$", "gg", "G", "j", "k", "D", "o", "O"] {
        for (missing, text) in [(Capability.lineStartKey, "one\ntwo"), (.lineEndKey, "one\ntwo"), (.documentEndKey, "one\ntwo")] {
            var profile = keyProfile
            profile.statuses[missing] = .unavailable
            let plan = physical(keys, text: text, caret: 5, profile: profile)
            let needs: [Capability: [Chord]] = [
                .lineStartKey: [.paragraphStart, Chord.paragraphStart.shifted],
                .lineEndKey: [.paragraphEnd, Chord.paragraphEnd.shifted],
                .documentEndKey: [.documentEnd, Chord.documentEnd.shifted],
            ]
            precondition(!chords(plan).contains { needs[missing]!.contains($0) }, "\(keys) pressed an unavailable key")
        }
    }
    // Counting presses what it always did; only the register now comes from the field.
    precondition(chords(physical("dd", text: "one\ntwo", caret: 5, profile: readProfile))
                 == chords(physical("dd", text: "one\ntwo", caret: 5, profile: CapabilityProfile(available: [
                     .readText, .readLength, .readCaret, .readSelectedText, .wholeDocument, .documentStartKey,
                 ]))))

    // Lane A keeps its exact writes.
    for keys in ["dd", "yy", "cc", "D", "0", "$", "gg", "G", "o", "O", "x", "j", "k", "dj", "J", "p"] {
        var full = axProfile
        for key in Capability.nativeKeys { full.statuses[key] = .available }
        let plan = physical(keys, text: "one\ntwo\nthree", caret: 5, profile: full, state: putState)
        precondition(plan == physical(keys, text: "one\ntwo\nthree", caret: 5, profile: axProfile, state: putState), keys)
    }

    // The logical fixes the keys rely on, in every lane.
    sim = Sim(text: "a\nb", caret: 2, profile: axProfile)
    sim.type("O")
    precondition(sim.text == "a\n\nb" && sim.caret == 2 && sim.state.field.mode == .insert)
    sim = Sim(text: "abc\ndef", caret: 1, profile: axProfile)
    sim.type("d$")
    precondition(sim.text == "a\ndef")
    precondition(sim.state.session.register("-") == .content(RegisterContent(text: "bc", wise: .character)))

    // End to end against lane A: reading exact offsets, every run does what lane A did; reading Chromium's, which
    // lane B cannot correct yet (LIN-1564), a run either does too, stops, or changes no text, and writes nothing else.
    let keyedCommands: [[String]] = ["dd", "yy", "cc", "S", "D", "C", "d$", "c$", "y$", "d0", "c0", "0", "^", "$", "A",
        "I", "gg", "G", "o", "O", "j", "k", "+", "-", "2dd", "3dd", "2yy", "dj", "dk", "yk", "cj", "ck", "dG", "dgg", "J",
        "3J", "2j", "3k", "2$", "d2$", "x", "X", "3x"].map { [$0] } + [["yy", "p"], ["yy", "P"], ["dd", "p"], ["dd", "P"]]
    for doc in ["alpha one\nbeta two\ngamma three\n\ndelta four\nepsilon", "  indented\n\tx y\nlast", "single line", "a\n",
                "  indented\nx\n\n\nlast", "\nb\n\nc"] {
        for caret in 0...doc.utf16.count {
            for commands in keyedCommands {
                var reference = Sim(text: doc, caret: caret, profile: axProfile)
                var passedThrough = [doc]
                for command in commands {
                    reference.type(command)
                    passedThrough.append(reference.text)
                }
                for chromium in [false, true] {
                    var keyed = Sim(text: doc, caret: caret, profile: keyProfile)
                    keyed.emulatesKeys = true
                    keyed.reads = chromium ? omitsBreaks : nil
                    commands.forEach { keyed.type($0) }
                    let keys = commands.joined()
                    let context = "\(keys) at \(caret) in \(doc.debugDescription), chromium=\(chromium)"
                    precondition(keyed.unsupportedSteps == 0, context)
                    let register = keyed.state.session.register("\"")
                    let same = keyed.text == reference.text && keyed.caret == reference.caret
                        && keyed.state.field.mode == reference.state.field.mode
                        && register == reference.state.session.register("\"") && keyed.bells == reference.bells
                    precondition(same || chromium, context)
                    // Counted edits plan from lane B's own reading of the caret, as on `main`; where the characters
                    // happen to agree, the text check passes them too.
                    if same || ["x", "X", "3x"].contains(keys) { continue }
                    precondition(passedThrough.contains(keyed.text), context)
                    precondition([nil, reference.state.session.register("\"")].contains(register), context)
                    precondition(keyed.settleFailures > 0 || keyed.text == doc && register == nil, context)
                }
            }
        }
    }

    // Where a misread passes every offset settle, the selected text stops the edit: Chromium reads 4 as 1 (`b`), and
    // 10 as 8 (`g`).
    for (text, caret, keys, planned) in [("\nb\n\nc", 4, "cc", "b"), ("ab\ncdef\nghij", 10, "x", "g")] {
        sim = Sim(text: text, caret: caret, profile: keyProfile)
        sim.emulatesKeys = true
        sim.reads = omitsBreaks
        sim.type(keys)
        precondition(sim.text == text && sim.state.field.mode == .normal && checkedText(sim.abortedStep) == planned, keys)
    }
    // A register without its newline (the last line, `cc`) still puts whole lines, in every lane.
    for profile in [axProfile, keyProfile] {
        sim = Sim(text: "alpha\nbeta", caret: 7, profile: profile)
        sim.emulatesKeys = true
        sim.type("yy")
        sim.type("2p")
        precondition(sim.text == "alpha\nbeta\nbeta\nbeta")
    }

    // Past paragraph 1 Chromium's raw reads are one low per break, and the first key's settle stops `j`.
    sim = Sim(text: "ab\ncdef\nghij", caret: 5, profile: keyProfile)
    sim.emulatesKeys = true
    sim.reads = omitsBreaks
    sim.type("j")
    precondition(sim.settleFailures == 1 && sim.text == "ab\ncdef\nghij")

    // Wrapped paragraphs: ↓ and ⌘← move by visual row; ⌃E→ by logical line.
    let wrapped = "alpha beta gamma delta\nnext line"
    sim = Sim(text: wrapped, caret: 3, profile: keyProfile)
    sim.emulatesKeys = true
    sim.wrapWidth = 8
    sim.type("j")
    precondition(sim.caret == 26 && sim.settleFailures == 0)
    sim = Sim(text: wrapped, caret: 3, profile: readProfile)
    sim.emulatesKeys = true
    sim.wrapWidth = 8
    sim.type("j")
    precondition(sim.settleFailures == 1 && TextModel(wrapped).lineStart(of: sim.caret) == 0)

    // A key that does nothing is blamed, and so is one that lands elsewhere.
    for (ignored, blamed) in [(Chord.paragraphStart, Capability.lineStartKey), (Chord.paragraphEnd.shifted, .lineEndKey)] {
        sim = Sim(text: "one\ntwo", caret: 5, profile: keyProfile)
        sim.emulatesKeys = true
        sim.ignoredChords = [ignored]
        sim.type("dd")
        precondition(sim.blamed == [blamed] && sim.text == "one\ntwo")
    }
    sim = Sim(text: "one\ntwo", caret: 5, profile: keyProfile)
    sim.emulatesKeys = true
    sim.reboundChords = [.paragraphStart: .selectAll]
    sim.type("dd")
    precondition(sim.blamed == [.lineStartKey] && sim.text == "one\ntwo")
    for web in [false, true] {
        sim = Sim(text: "the cat", caret: 4, profile: keyProfile)
        sim.emulatesKeys = true
        sim.webContent = web
        sim.reboundChords = [.paragraphStart: .paragraphEnd]
        sim.type("0")
        precondition(sim.blamed == [.lineStartKey] && sim.caret == 7, "a ⌃A that acts as ⌃E, web \(web)")
    }
    // In web content a key that did nothing is blamed where the reads are exact, as in a textarea.
    sim = Sim(text: "the cat", caret: 4, profile: keyProfile)
    sim.emulatesKeys = true
    sim.webContent = true
    sim.ignoredChords = [.paragraphStart]
    sim.type("0")
    precondition(sim.settleFailures == 1 && sim.blamed == [.lineStartKey] && sim.text == "the cat")

    // With paragraph reads too, beside a `<br>` as well, except from a caret in an empty paragraph, which `AXValue` can
    // leave out and read beside.
    precondition(webBlame("0", caret: 5, breaks: ParagraphBreaks(offsets: [2]))?.unmoved == [4..<4])
    precondition(webBlame("0", caret: 5, breaks: ParagraphBreaks(offsets: []))?.unmoved == [5..<5])
    precondition(webBlame("0", caret: 2, breaks: ParagraphBreaks(offsets: []))?.unmoved == [2..<2])
    precondition(webBlame("$", caret: 3, breaks: ParagraphBreaks(offsets: []))?.unmoved == [3..<3])
    let fromEmptyParagraph = PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("0"), state: .initial), snapshot: FieldSnapshot(
        capabilities: keyProfile, text: "ab\ncdef", selection: 2..<2, webContent: true, breaks: ParagraphBreaks(offsets: []),
        caretInEmptyParagraph: true
    ))
    precondition(fromEmptyParagraph.steps.contains {
        guard case .settle(let expectation) = $0 else { return false }
        return expectation.blame?.unmoved == [] && expectation.blame?.leavesCaret == true
    })
    // A landing that is right with a length that is not blames nothing: the key did its part.
    precondition(Expectation(landing: .exact(0..<0), length: 7, blame: .init(capability: .lineStartKey, unmoved: [4..<4],
        leavesCaret: true, offTarget: true)).blamed(observed: 0..<0) == nil)
    // Rich text is where a working key lands off the model's line, so only there a landing elsewhere teaches nothing.
    precondition(webBlame("0", caret: 5, breaks: ParagraphBreaks(offsets: [2]))?.offTarget == false)
    precondition(webPhysical("0", text: "the cat", caret: 4, profile: keyProfile).steps.contains {
        guard case .settle(let expectation) = $0 else { return false }
        return expectation.blame?.offTarget == true
    })
    sim = Sim(text: "one\ntwo", caret: 5, profile: keyProfile)
    sim.emulatesKeys = true
    sim.webContent = true
    sim.reboundChords = [.paragraphStart: .selectAll]
    sim.type("dd")
    precondition(sim.blamed == [.lineStartKey] && sim.text == "one\ntwo")
    // Elsewhere reads are exact: a key that did nothing is blamed wherever it had somewhere to go.
    for (text, caret, keys, ignored, blamed) in [
        ("one\ntwo", 5, "$", Chord.paragraphEnd, Capability.lineEndKey), ("one\ntwo", 4, "$", .paragraphEnd, .lineEndKey),
        ("the cat", 4, "0", .paragraphStart, .lineStartKey), ("ab\ncdef\nghij", 6, "0", .paragraphStart, .lineStartKey),
    ] {
        sim = Sim(text: text, caret: caret, profile: keyProfile)
        sim.emulatesKeys = true
        sim.ignoredChords = [ignored]
        sim.type(keys)
        precondition(sim.blamed == [blamed], "\(keys) at \(caret) in \(text.debugDescription)")
    }
    sim = Sim(text: "one\ntwo", caret: 4, profile: keyProfile)
    sim.emulatesKeys = true
    sim.ignoredChords = [.paragraphStart]
    sim.type("0")
    precondition(sim.blamed.isEmpty && sim.settleFailures == 0, "⌃A at a line start has nowhere to go")

    // Relational landings, for keys whose landing the app decides.
    precondition(Landing.caretAfter(4, strict: true).matches(5..<5) && !Landing.caretAfter(4, strict: true).matches(4..<4))
    precondition(Landing.caretBefore(4, strict: false).matches(4..<4) && !Landing.caretBefore(4, strict: false).matches(2..<3))
    precondition(Expectation(landing: .caretAfter(2, strict: true)).traceFields == "sel=>2 len=nil")
}
