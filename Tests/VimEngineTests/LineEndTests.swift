// MARK: - Invisible line ends (LIN-1978)

let larkProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .drawCursor, .wholeDocument,
])
/// Lark's composer as LIN-1975 read it: Chromium paragraphs each closed by a U+200B, and AX text writes ignored.
func larkSim(_ text: String, caret: Int) -> Sim {
    var host = blankSim([text], caret: caret, profile: larkProfile)
    host.swallowsReplace = true
    host.pullsBackFromLineEnds = true
    host.runsAreNewlines = true
    return host
}
let zw = "\u{200B}"

func testInvisibleLineEnds() {
    let closedLines = TextModel("hello\u{200B}\nworld\u{200B}")
    precondition(closedLines.lineEnd(of: 2) == 5 && closedLines.lineBreak(of: 2) == 6)
    precondition(closedLines.lineEnd(of: 6) == 6 && closedLines.visibleOffset(6) == 5 && closedLines.visibleOffset(4) == 4)
    precondition(closedLines.lines(from: 2, count: 1, extent: .whole) == 0..<7)
    precondition(closedLines.lines(from: 8, count: 1, extent: .whole) == 7..<12)
    precondition(closedLines.lines(from: 8, count: 1, extent: .removed) == 6..<12)
    precondition(TextModel("hello\u{200B}\nworld\u{200B}", paragraphBreaks: [6]).lines(from: 8, count: 1, extent: .removed) == 5..<12)
    precondition(closedLines.lines(from: 2, count: 2, extent: .interior) == 0..<12)
    precondition(closedLines.lineSpan(from: 8, to: 1, extent: .interior) == 0..<12)
    precondition(closedLines.destination(of: .lineEnd, from: 9, count: 1) == 12)
    precondition(closedLines.destination(of: .lastNonBlank, from: 6, count: 1) == 4)
    precondition(closedLines.verticalMove(from: 5, by: 1, firstNonBlank: false) == 12)
    precondition(closedLines.wordForward(from: 0, big: false) == 7 && closedLines.wordBackward(from: 7, big: false) == 0)
    precondition(closedLines.wordEnd(from: 2, big: false) == 4 && closedLines.wordEnd(from: 4, big: false) == 11)
    precondition(closedLines.wordEnd(from: 11, big: false) == 11)
    precondition(TextModel("a\u{200B}\u{2060}\u{FEFF}").lineEnd(of: 0) == 1)
    precondition(TextModel("e\u{301}\u{200B}").lineEnd(of: 0) == 2)
    precondition(TextModel("o\u{200D}").lineEnd(of: 0) == 2 && TextModel("\u{2764}\u{FE0F}").lineEnd(of: 0) == 2)
    precondition(TextModel("ab\u{2060}", atoms: [2]).lineEnd(of: 0) == 3, "a chip is drawn")
    // Linear draws the line after a `<br>` with a U+200B, and keeps the caret after it; a paragraph's is empty.
    precondition(TextModel("ab\n\u{200B}\ncd", paragraphBreaks: [4]).lineEnd(of: 3) == 4)
    precondition(TextModel("ab\n\u{200B}\ncd", paragraphBreaks: [2, 4]).lineEnd(of: 3) == 3)
    precondition(TextModel("ab\n\u{200B}\ncd").lineEnd(of: 3) == 3 && TextModel("\u{200B}", paragraphBreaks: []).lineEnd(of: 0) == 0)
    precondition(TextModel("a\u{200B}\nb\u{2060}\u{FEFF}\nc\u{200B}").visibleText(in: 0..<9) == "a\nb\nc")
    precondition(TextModel("ab\n\u{200B}\ncd", paragraphBreaks: [4]).visibleText(in: 3..<5) == "\u{200B}\n")
    precondition(TextModel("ab\n\u{200B}\ncd", paragraphBreaks: [2, 4]).visibleText(in: 3..<5) == "\n")
    precondition(TextModel("ab\u{200B}\ncd").endsLinesInvisibly && !TextModel("ab\n\u{200B}cd").endsLinesInvisibly)
    precondition(!TextModel("ab\n\u{200B}\ncd", paragraphBreaks: [4]).endsLinesInvisibly && !TextModel("ab\u{2060}", atoms: [2]).endsLinesInvisibly)
    var zwKeys = KeyModel(text: "ab\u{200B}\ncd", anchor: 0, focus: 0)
    precondition(zwKeys.press(.paragraphEnd) && zwKeys.selection == 3..<3, "⌃E lands after it in AppKit and WebKit")
    precondition(zwKeys.press(.right) && zwKeys.selection == 4..<4 && zwKeys.press(.left) && zwKeys.selection == 3..<3)

    var nativePut = Sim(text: "one\u{200B}\ntwo\u{200B}", caret: 1, profile: axProfile)
    nativePut.type("yyjp")
    precondition(nativePut.text == "one\u{200B}\ntwo\none\u{200B}" && nativePut.settleFailures == 0, "a put below the last line goes before its run")
    var pasteboardPut = VimState.initial
    pasteboardPut.session.registers.unnamed = .pasteboard(wise: .line)
    precondition(physical("p", text: "one\u{200B}\ntwo\u{200B}", caret: 6, profile: axProfile, state: pasteboardPut).steps.first
                 == .setSelection(8..<8))
    for profile in [readProfile, keyProfile, axProfile] {
        var visualEnd = Sim(text: "hello\u{200B}", caret: 1, profile: profile)
        visualEnd.emulatesKeys = true
        visualEnd.type("v$d")
        precondition(visualEnd.text == "h\u{200B}" && visualEnd.settleFailures == 0, "v$d under \(profile): \(visualEnd.text.debugDescription)")
        precondition(visualEnd.state.session.register("\"") == .content(RegisterContent(text: "ello", wise: .character)))
    }
    var remembered = VimState.initial
    remembered.field.lastVisual = VisualMemory(kind: .character, range: 1..<6)
    precondition(physical("gv", text: "hello\u{200B}", caret: 0, profile: axProfile, state: remembered).steps.first == .setSelection(1..<5))
    var nativeWords = Sim(text: "hello\u{200B}", caret: 5, profile: nativeRead)
    nativeWords.emulatesKeys = true
    nativeWords.type("w")
    precondition(nativeWords.caret == 5 && nativeWords.settleFailures == 0, "the app's ⌥→ would land past the run")
    nativeWords.type("dw")
    precondition(nativeWords.text == "hello\u{200B}" && nativeWords.settleFailures == 0, "an app's word keys land past the run")
    nativeWords = Sim(text: "hello\u{200B}", caret: 0, profile: nativeRead)
    nativeWords.emulatesKeys = true
    nativeWords.type("2dw")
    precondition(nativeWords.text == "\u{200B}" && nativeWords.settleFailures == 0)
    var bang = VimState.initial
    bang.session.registers.unnamed = .content(RegisterContent(text: "!", wise: .character))
    for (text, keys, after) in [
        ("hello\u{200B}", "vhd", "hell\u{200B}"), ("hello\u{200B}", "v$d", "hello\u{200B}"), ("hello\u{200B}", "ma0ld`a", "h\u{200B}"),
        ("hello\u{200B}", "p", "hello!\u{200B}"), ("hello\u{200B}", "P", "hello!\u{200B}"), ("hello\u{200B}\u{2060}", "p", "hello!\u{200B}\u{2060}"),
    ] {
        var hostCaret = Sim(text: text, caret: 6, state: bang, profile: axProfile)
        hostCaret.type(keys)
        precondition(hostCaret.text == after && hostCaret.settleFailures == 0, "\(keys) from after the run: \(hostCaret.text.debugDescription)")
    }
    for profile in [axProfile, readProfile, keyProfile, nativeRead] {
        for (caret, keys, after, landing) in [(6, "vjhd", "hellod\u{200B}\nthird", 5), (5, "vjhd", "hellod\u{200B}\nthird", 5),
                                              (6, "vj", "hello\u{200B}\nworld\u{200B}\nthird", 12)] {
            var visualAnchor = Sim(text: "hello\u{200B}\nworld\u{200B}\nthird", caret: caret, profile: profile)
            visualAnchor.emulatesKeys = true
            visualAnchor.type(keys)
            visualAnchor.feed("<Esc>")
            precondition(visualAnchor.text == after && visualAnchor.caret == landing && visualAnchor.settleFailures == 0,
                         "\(keys) from \(caret) under \(profile): \(visualAnchor.text.debugDescription) at \(visualAnchor.caret)")
        }
    }
    for (keys, after, landing) in [("j", "abcdefghijk\u{200B}\nshort\u{200B}", 15),
                                   ("yyjp", "abcdefghijk\u{200B}\nshort\nabcdefghijk\u{200B}", 30)] {
        var wrapped = Sim(text: "abcdefghijk\u{200B}\nshort\u{200B}", caret: 2, profile: keyProfile)
        wrapped.emulatesKeys = true
        wrapped.wrapWidth = 4
        wrapped.type(keys)
        precondition(wrapped.text == after && wrapped.caret == landing && wrapped.settleFailures == 0 && wrapped.softMisses == 0,
                     "\(keys) by paragraph keys in a wrapped field: \(wrapped.text.debugDescription) at \(wrapped.caret)")
    }
    for (text, caret, keys, ignored, blamed) in [
        ("abcdefghijk\u{200B}\nlonger line here\u{200B}", 2, "j", Chord.paragraphEnd, Capability.lineEndKey),
        ("abcdefghijk\u{200B}\nlonger line here\u{200B}", 10, "j", .paragraphEnd, .lineEndKey),
        ("aa\u{200B}\nbb\u{200B}\ncc\u{200B}", 1, "G", .paragraphStart, .lineStartKey),
        ("aa\u{200B}\nbb\u{200B}\ncc\u{200B}", 5, "dk", Chord.paragraphStart.shifted, .lineStartKey),
        ("aa\u{200B}\nbb\u{200B}\ncc\u{200B}", 5, "dk", .paragraphEnd, .lineEndKey),
        ("one\u{200B}\ntwo", 1, "dd", Chord.paragraphEnd.shifted, .lineEndKey),
    ] {
        var unmoved = Sim(text: text, caret: caret, profile: keyProfile)
        unmoved.emulatesKeys = true
        unmoved.ignoredChords = [ignored]
        unmoved.type(keys)
        precondition(unmoved.blamed == [blamed] && unmoved.settleFailures == 1, "\(keys) from \(caret) ignoring \(ignored): \(unmoved.blamed)")
    }
    for (caret, keys) in [(1, "j"), (6, "dk")] {
        var overshoot = Sim(text: "one\u{200B}\ntwo\u{200B}\nthree\u{200B}", caret: caret, profile: keyProfile)
        overshoot.emulatesKeys = true
        overshoot.reboundChords = [.paragraphEnd: .documentEnd]
        overshoot.type(keys)
        precondition(overshoot.blamed == [.lineEndKey] && overshoot.settleFailures == 1, "\(keys) from \(caret): \(overshoot.blamed)")
    }
    var routeMiss = Sim(text: "abcdefghijk\u{200B}\nlonger line here\u{200B}", caret: 10, profile: keyProfile)
    routeMiss.emulatesKeys = true
    routeMiss.ignoredChords = [.right]
    routeMiss.type("j")
    precondition(routeMiss.blamed.isEmpty && routeMiss.attribution.missedRoute == .lineEnd, "\(routeMiss.blamed)")
    var pulledBack = Sim(text: "aa\u{200B}\nbb\u{200B}\ncc\u{200B}", caret: 1, profile: keyProfile)
    pulledBack.emulatesKeys = true
    pulledBack.pullsBackFromLineEnds = true
    pulledBack.type("G")
    precondition(pulledBack.caret == 8 && pulledBack.settleFailures == 0, "⌘↓ may land on either side of the run")
    var displayRows = Sim(text: "alpha beta gamma\u{200B}\nnext", caret: 0, profile: nativeRead)
    displayRows.emulatesKeys = true
    displayRows.wrapWidth = 6
    displayRows.type("gj")
    precondition(displayRows.caret == 6 && displayRows.bells == 0 && displayRows.settleFailures == 0, "the model has no display rows, so the app's keep them")
    var insertedAfterRun = Sim(text: "hello\u{200B}\nworld", caret: 6, profile: axProfile)
    insertedAfterRun.type("i")
    insertedAfterRun.feed("<Esc>")
    insertedAfterRun.type("0gi")
    precondition(insertedAfterRun.caret == 5 && insertedAfterRun.settleFailures == 0, "gi returns before the run")
    let placeholderLine = FieldSnapshot(
        capabilities: axProfile, text: "ab\n\u{200B}\ncd", selection: 3..<3, breaks: ParagraphBreaks(offsets: [4])
    )
    for (keys, kept) in [("yy", "\u{200B}\n"), ("dd", "\u{200B}\n")] {
        let planned = PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: .initial), snapshot: placeholderLine).steps
        precondition(planned.contains { step in
            if case .commit(.yanked(_, .literal(kept), _)) = step { return true }
            if case .commit(.deleted(_, .literal(kept), _)) = step { return true }
            return false
        }, "\(keys) keeps Linear's placeholder")
    }
    precondition(PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("J"), state: .initial), snapshot: placeholderLine).steps
                 .contains(.replaceSelection("\u{200B} cd")))
    // No write or check uvim plans lands among the invisible characters ending a line, from any caret, in any lane.
    var visualAt = VimState.initial
    for text in ["hello\u{200B}", "hi there\u{200B}\nworld\u{200B}", "a\u{200B}\u{2060}\nb c", "\u{200B}", "x\n\u{200B}\ny z\u{FEFF}"] {
        let model = TextModel(text)
        for profile in [axProfile, readProfile, keyProfile, nativeRead, noInsertProfile] {
            for caret in text.indices.map({ $0.utf16Offset(in: text) }) + [model.length] {
                visualAt.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: caret))
                let commands = ["$", "A", "a", "x", "X", "D", "C", "dd", "cc", "yy", "p", "P", "o", "J", "w", "e", "b", "W", "E", "dw", "de",
                                "db", "cw", "diw", "daw", "yiw", "l", "h", "j", "k", "0", "^", "g_", "G", "gg", "d$", "y$", "3l", "2w", "2dw", "~"]
                let runs = commands.map { ($0, bang) } + ["$", "l", "h", "w", "e", "b", "j", "k", "g_", "G"].map { ($0, visualAt) }
                for (keys, state) in runs {
                    for step in physical(keys, text: text, caret: caret, profile: profile, state: state).steps {
                        var ends: [Int] = []
                        switch step {
                        case .setSelection(let range): ends = [range.lowerBound, range.upperBound]
                        case .settle(let expectation), .softSettle(let expectation):
                            if case .exact(let range)? = expectation.landing { ends = [range.lowerBound, range.upperBound] }
                        default: break
                        }
                        if case .replaceSelection = step { break }
                        if case .typeText = step { break }
                        if case .clipboardInsert = step { break }
                        if case .clipboardCut = step { break }
                        if case .press(.deleteBack, _) = step { break }
                        precondition(ends.allSatisfy { model.visibleOffset($0) == $0 },
                                     "\(keys) from \(caret) in \(text.debugDescription) under \(profile): \(step)")
                    }
                }
            }
        }
    }
    // Visual from a host's caret among a line's end run runs as from the line's visible end, and never selects into the run.
    for text in ["hello\u{200B}\nworld\u{200B}\nthird", "a\u{200B}\u{2060}\nb c", "one two\u{200B}\n\u{200B}\nthree\u{200B}"] {
        let model = TextModel(text)
        for profile in [axProfile, readProfile, keyProfile, nativeRead] {
            for caret in 0...model.length where model.visibleOffset(caret) < caret {
                for motions in ["h", "l", "j", "k", "$", "0", "w", "b", "e", "G"].flatMap({ m in ["", "h", "l", "j", "k", "$"].map { m + $0 } }) {
                    for op in ["d", "y", "<Esc>"] {
                        var results: [String] = []
                        for start in [caret, model.visibleOffset(caret)] {
                            var sim = Sim(text: text, caret: start, profile: profile)
                            sim.emulatesKeys = true
                            sim.type("v" + motions)
                            let shown = TextModel(sim.text)
                            precondition([sim.selection.lowerBound, sim.selection.upperBound].allSatisfy { shown.visibleOffset($0) == $0 },
                                         "v\(motions) from \(start) in \(text.debugDescription) under \(profile): \(sim.selection)")
                            if op == "<Esc>" { sim.feed(op) } else { sim.type(op) }
                            results.append("\(sim.text.debugDescription) \(sim.caret) \(String(describing: sim.state.session.register("\""))) \(sim.bells)")
                            precondition(sim.settleFailures == 0 && sim.softMisses == 0, "v\(motions)\(op) from \(start) in \(text.debugDescription)")
                        }
                        precondition(results[0] == results[1], "v\(motions)\(op) from \(caret) in \(text.debugDescription) under \(profile): \(results)")
                    }
                }
            }
        }
    }
    let afterHardBreak = FieldSnapshot(
        capabilities: axProfile, text: "ab\n\u{200B}\ncd", selection: 3..<3, breaks: ParagraphBreaks(offsets: [4])
    )
    precondition(PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("A"), state: .initial), snapshot: afterHardBreak).steps.first
                 == .setSelection(4..<4))

    for (text, caret, keys, typed, after) in [
        ("hello world\(zw)", 6, "D", nil, "hello \(zw)"), ("hello\(zw)", 2, "dd", nil, zw),
        ("one\(zw)\ntwo\(zw)", 5, "dd", nil, "one\(zw)"), ("one\(zw)\ntwo\(zw)", 1, "dd", nil, "two\(zw)"),
        ("hello\(zw)", 4, "x", nil, "hell\(zw)"), ("hello\(zw)", 2, "C", "!", "he!\(zw)"), ("hello\(zw)", 2, "A", "!", "hello!\(zw)"),
        ("hello\(zw)", 2, "o", "new", "hello\nnew\(zw)"), ("one\(zw)\ntwo\(zw)", 1, "J", nil, "one two\(zw)"),
        ("hello\(zw)", 2, "cc", "X", "X\(zw)"), (zw, 0, "A", "hi", "hi\(zw)"), (zw, 0, "a", "hi", "hi\(zw)"),
        ("one\(zw)\ntwo\(zw)", 1, "yyjp", nil, "one\(zw)\ntwo\none\(zw)"), ("one\(zw)\n\(zw)", 5, "dd", nil, "one\(zw)"),
        ("hello\(zw)", 1, "v$d", nil, "h\(zw)"),
    ] as [(String, Int, String, String?, String)] {
        var lark = larkSim(text, caret: caret)
        lark.type(keys)
        if let typed {
            lark.type(typed)
            lark.feed("<Esc>")
        }
        precondition(lark.text == after, "\(keys) in \(text.debugDescription): \(lark.text.debugDescription)")
        precondition(lark.settleFailures == 0 && lark.softMisses == 0 && lark.bells == 0 && lark.unsupportedSteps == 0, keys)
    }
    // The same in Chromium's paragraphs, where a field offset past a run is the next line's start, so only the text's end and a run's inside are off limits.
    for text in ["hello\(zw)", "hi there\(zw)\nworld\(zw)", "a\(zw)\u{2060}\nb c", zw, "x\n\(zw)\ny z\u{FEFF}", "one\(zw)\n\(zw)\nthree\(zw)"] {
        let breaks = ParagraphBreaks(value: text, fieldText: String(text.filter { $0 != "\n" }))!
        let model = TextModel(text, paragraphBreaks: Set(breaks.offsets))
        var offLimits = Set<Int>()
        for o in 1...model.length where model.visibleOffset(o) < o && (o < model.lineBreak(of: o) || o == model.length) {
            offLimits.insert(breaks.fieldOffset(o))
        }
        for profile in [axProfile, larkProfile, readProfile, keyProfile] {
            for caret in text.indices.map({ $0.utf16Offset(in: text) }) + [model.length] {
                visualAt.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: caret))
                let commands = ["$", "A", "a", "x", "D", "C", "dd", "cc", "yy", "p", "P", "o", "J", "w", "e", "b", "dw", "de", "db",
                                "diw", "l", "h", "j", "k", "0", "g_", "G", "d$", "2dw"]
                for (keys, state) in commands.map({ ($0, bang) }) + ["$", "l", "h", "w", "e", "b", "j", "k", "G"].map({ ($0, visualAt) }) {
                    let snapshot = FieldSnapshot(capabilities: profile, text: text, selection: caret..<caret, webContent: true, breaks: breaks)
                    for step in PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: state), snapshot: snapshot).steps {
                        var ends: [Int] = []
                        switch step {
                        case .setSelection(let range): ends = [range.lowerBound, range.upperBound]
                        case .settle(let expectation), .softSettle(let expectation):
                            if case .exact(let range)? = expectation.landing { ends = [range.lowerBound, range.upperBound] }
                        default: break
                        }
                        if case .replaceSelection = step { break }
                        if case .typeText = step { break }
                        if case .clipboardInsert = step { break }
                        if case .press(.deleteBack, _) = step { break }
                        precondition(!ends.contains(where: offLimits.contains), "\(keys) from \(caret) in \(text.debugDescription): \(step)")
                    }
                }
            }
        }
    }
    var larkUndo = larkSim("one\(zw)\ntwo\(zw)", caret: 6)
    larkUndo.type("ddu")
    precondition(larkUndo.text == "one\(zw)\ntwo\(zw)" && larkUndo.caret >= 5, "\(larkUndo.caret)")
    larkUndo.type("dd")
    precondition(larkUndo.text == "one\(zw)" && larkUndo.settleFailures == 0, larkUndo.text.debugDescription)
    // With keys alone, → cannot cross Lark's newline from the line above, so `u` lands from the text's end.
    var larkKeys = blankSim(["one\(zw)", "two\(zw)", "three\(zw)"], caret: 12, profile: keyProfile)
    larkKeys.webContent = true
    larkKeys.pullsBackFromLineEnds = true
    larkKeys.runsAreNewlines = true
    larkKeys.type("ddu")
    precondition(larkKeys.text == "one\(zw)\ntwo\(zw)\nthree\(zw)" && larkKeys.caret == 10, "\(larkKeys.caret)")
    // A landing that fails in Lark's field still ends on the restored line, since ↓ crosses the break → cannot.
    // With keys alone the fallback's ⌘↓, or its ⇧↓ and →, reach the restored line where ↓ (or ↓ and ⌘↓) were ignored.
    let larkFaults: [(UndoSelection: Sim.UndoSelection, late: Bool, profile: CapabilityProfile?, ignored: Set<Chord>)] = [
        (.toBreak, true, nil, []), (.toBreak, false, nil, []), (.restored, true, nil, []), (.toBreak, true, keyProfile, [.documentEnd]),
        (.toBreak, true, readProfile, [.down]), (.restored, false, readProfile, [.down, .selectDown]),
        (.toBreak, true, keyProfile, [.down, .documentEnd]),
    ]
    for (shape, late, profile, ignored) in larkFaults {
        for probe in ["dd", "iX"] where !(profile != nil && probe == "dd") {
            var lark = profile.map { blankSim(["one\(zw)", "two\(zw)", "three\(zw)"], caret: 12, profile: $0) }
                ?? larkSim("one\(zw)\ntwo\(zw)\nthree\(zw)", caret: 12)
            (lark.webContent, lark.pullsBackFromLineEnds, lark.runsAreNewlines) = (true, true, true)
            (lark.undoSelection, lark.undoesLate) = (shape, late)
            lark.type("dd")
            if profile != nil { lark.ignoredChords = ignored } else { lark.swallowsSelect = true }
            lark.type("u")
            (lark.swallowsSelect, lark.ignoredChords) = (false, [])
            lark.type(probe)
            lark.feed("<Esc>")
            let rows = lark.text.split(separator: "\n", omittingEmptySubsequences: false)
            let landed = probe == "dd" ? lark.text == "one\(zw)\ntwo\(zw)" : rows.count == 3 && rows[0] == "one\(zw)" && rows[1] == "two\(zw)" && rows[2].contains("X")
            precondition(landed, "\(shape) late=\(late) ignored=\(ignored) u, then \(probe): \(lark.text.debugDescription)")
        }
    }
    var larkYank = larkSim("one\(zw)\ntwo\(zw)", caret: 1)
    larkYank.type("yy")
    precondition(larkYank.state.session.register("\"") == .content(RegisterContent(text: "one\n", wise: .line)))
    for (text, caret, keys, landing) in [
        ("hello\(zw)", 0, "$", 5), ("hi there\(zw)", 3, "w", 8), ("one\(zw)\ntwo\(zw)", 0, "w", 5), ("one\(zw)\ntwo\(zw)", 2, "e", 7),
        ("one\(zw)\ntwo\(zw)", 2, "j", 7), ("one\(zw)\ntwo\(zw)", 2, "ll", 3),
    ] {
        var lark = larkSim(text, caret: caret)
        lark.type(keys)
        precondition(lark.caret == landing && lark.settleFailures == 0 && lark.bells == 0, "\(keys) from \(caret) in \(text.debugDescription)")
    }

    // Outside paragraphs the line break above a last line goes alone, so the line above keeps its own run.
    for profile in [axProfile, readProfile, keyProfile] {
        for (caret, keys, after) in [
            (2, "D", "he\(zw)\nworld\(zw)"), (8, "dd", "hello\(zw)\(zw)"), (2, "dd", "world\(zw)"), (2, "J", "hello world\(zw)"),
        ] {
            var native = Sim(text: "hello\(zw)\nworld\(zw)", caret: caret, profile: profile)
            native.emulatesKeys = true
            native.type(keys)
            precondition(native.text == after && native.settleFailures == 0 && native.softMisses == 0 && native.bells == 0,
                         "\(keys) from \(caret) under \(profile): \(native.text.debugDescription)")
        }
    }
}
