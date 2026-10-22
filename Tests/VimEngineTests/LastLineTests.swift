// MARK: - Deleting the text's last lines

func testDeletingLastLines() {
    let lastThree = "one\ntwo\nthree"
    let lastModel = TextModel(lastThree)
    precondition(lastModel.lines(from: 10, count: 1, extent: .removed) == 7..<13 && lastModel.lines(from: 5, count: 1, extent: .removed) == 4..<8)
    precondition(lastModel.lines(from: 5, count: 9, extent: .removed) == 3..<13 && lastModel.lines(from: 1, count: 3, extent: .removed) == 0..<13)
    precondition(lastModel.lines(from: 10, count: 1, extent: .whole) == 8..<13 && lastModel.lines(from: 10, count: 1, extent: .interior) == 8..<13)
    precondition(TextModel("one\ntwo\n").lines(from: 8, count: 1, extent: .removed) == 7..<8)
    precondition(TextModel("one\ntwo\n").lines(from: 4, count: 1, extent: .removed) == 4..<8)
    precondition(TextModel("one\ntwo\n").lineSpan(from: 4, to: 8, extent: .removed) == 3..<8)
    precondition(plan("yy").steps.first == .select(.lines(count: 1, extent: .whole)))
    precondition(plan("dk").steps.first == .select(.lineSpan(to: .motion(.line(.up, firstNonBlank: false), count: 1), extent: .removed)))
    precondition(plan("cj").steps.first == .select(.lineSpan(to: .motion(.line(.down, firstNonBlank: false), count: 1), extent: .interior)))

    precondition(physical("dd", text: "one\ntwo", caret: 5, profile: axProfile).steps == [
        .setSelection(4..<7),
        .settle(Expectation(selection: 4..<7, length: 7)),
        .settle(Expectation(selection: 4..<7, length: 7, selectedText: "two")),
        .press(.deleteBack, count: 1),
        .softSettle(deleting(Expectation(selection: 4..<4, length: 4), 4..<7, before: 7)),
        .press(.deleteBack, count: 1),
        .settle(Expectation(selection: 3..<3, length: 3)),
        .commit(.deleted(into: nil, content: .literal("two\n"), wise: .line)),
        .setSelection(0..<0),
        .settle(Expectation(selection: 0..<0, length: 3)),
        .setSelection(0..<1),
        .commit(.setCursor(0..<1)),
    ])
    let down = [Chord.paragraphStart, Chord.paragraphEnd.shifted, .selectRight]
    for (keys, caret, expected) in [
        ("dd", 10, down), ("2dd", 5, down + [Chord.paragraphEnd.shifted, .selectRight]), ("dG", 5, [.paragraphStart, Chord.documentEnd.shifted]),
        ("dk", 10, [.paragraphEnd, .right, .selectLeft, Chord.paragraphStart.shifted, .selectLeft, Chord.paragraphStart.shifted]),
    ] {
        precondition(chords(physical(keys, text: lastThree, caret: caret, profile: keyProfile)) == expected + [.deleteBack, .deleteBack, .paragraphStart], keys)
    }
    let longAbove = String(repeating: "word ", count: 40) + "\nlast"
    precondition(chords(physical("dd", text: longAbove, caret: 202, profile: readProfile))
                 == [.right, .right, .right] + Array(repeating: .selectLeft, count: 4) + [.deleteBack, .deleteBack] + Array(repeating: .left, count: 200))

    for profile in [axProfile, keyProfile, readProfile, noInsertProfile] {
        for (text, caret, keys, after, cursor, register) in [
            ("one\ntwo", 5, "dd", "one", 0, "two\n"), ("one\ntwo\n", 8, "dd", "one\ntwo", 4, "\n"),
            ("one\n  two\nthree", 13, "dd", "one\n  two", 6, "three\n"), (lastThree, 5, "2dd", "one", 0, "two\nthree\n"),
            (lastThree, 5, "dj", "one", 0, "two\nthree\n"), (lastThree, 10, "dk", "one", 0, "two\nthree\n"),
            (lastThree, 5, "dG", "one", 0, "two\nthree\n"), ("one\ntwo\n", 4, "dG", "one", 0, "two\n\n"),
            ("one\n\n", 5, "dd", "one\n", 4, "\n"), ("one", 1, "dd", "", 0, "one"), (lastThree, 10, "dd.", "one", 0, "two\n"),
            (lastThree, 10, "ddp", lastThree, 13, "three\n"), (lastThree, 10, "ddP", "one\nthree\ntwo", 10, "three\n"),
            ("one\ntwo", 5, "yy", "one\ntwo", 4, "two"),
        ] {
            var sim = Sim(text: text, caret: caret, profile: profile)
            sim.emulatesKeys = true
            sim.type(keys)
            let context = "\(keys) in \(text.debugDescription)"
            precondition(sim.text == after && sim.caret == cursor && sim.settleFailures == 0 && sim.softMisses == 0, context)
            precondition(sim.state.session.register("\"") == .content(RegisterContent(text: register, wise: .line)), context)
        }
        var blackHole = Sim(text: lastThree, caret: 10, profile: profile)
        blackHole.emulatesKeys = true
        blackHole.type("\"_dd")
        precondition(blackHole.text == "one\ntwo" && blackHole.state.session.register("\"") == nil)
        var changed = Sim(text: "one\ntwo", caret: 5, profile: profile)
        changed.emulatesKeys = true
        changed.type("ccX")
        changed.feed("<Esc>")
        precondition(changed.text == "one\nX")
    }

    // The delete writes no text, so a field that ignores text writes deletes the last line at once.
    for mode in ["plain", "markers", "emptyParagraphs"] {
        let profile = adding([.lineStartKey, .lineEndKey, .documentStartKey, .documentEndKey], to: axProfile)
        var refused = Sim(text: lastThree, caret: 10, profile: profile)
        refused.swallowsReplace = true
        refused.emulatesKeys = true
        if mode == "markers" {
            refused.reads = omitsBreaks
            refused.writesInReadOffsets = true
            refused.markers = true
        } else if mode == "emptyParagraphs" {
            refused.emptyParagraphs = true
            refused.readModel = .textContent
        }
        refused.learn(with: Sim.Learner(chromium: mode != "plain", probed: profile))
        refused.type("dd")
        precondition(refused.text == "one\ntwo" && refused.caret == 4 && refused.settleFailures == 0, mode)
    }
    var refusedEmpty = Sim(text: "one\ntwo\n", caret: 8, profile: adding([.lineStartKey, .lineEndKey], to: axProfile))
    refusedEmpty.swallowsReplace = true
    refusedEmpty.emulatesKeys = true
    refusedEmpty.emptyParagraphs = true
    refusedEmpty.readModel = .textContent
    refusedEmpty.type("dd")
    precondition(refusedEmpty.text == "one\ntwo" && refusedEmpty.caret == 4 && refusedEmpty.settleFailures == 0)

    let chipEnds = ParagraphBreaks(hidden: [.init(at: 7, text: " LIN-1 chip", kind: .atom), .init(at: 7, text: "\n", kind: .trailingBreak)])
    precondition(chipEnds.replacing(7..<17, with: "", endsLine: true) == chipEnds)
    precondition(chipEnds.replacing(7..<8, with: "").hidden == [.init(at: 7, text: " LIN-1 chip", kind: .atom)])
    for profile in [writeKeys, keyProfile] {
        var chipAbove = Sim(text: "Intro \u{2060}\nlast line", caret: 12, profile: profile)
        chipAbove.emptyParagraphs = true
        chipAbove.listLines = [Sim.ListLine(), Sim.ListLine()]
        chipAbove.emulatesKeys = true
        chipAbove.readModel = .textContent
        chipAbove.type("dd")
        precondition(chipAbove.text == "Intro \u{2060}" && chipAbove.caret == 0 && chipAbove.settleFailures == 0 && chipAbove.softMisses == 0)
    }

    // A removal that fails leaves the caret on the lines it was to delete.
    let backspaceLane = CapabilityProfile(available: [
        .readText, .readLength, .readCaret, .readSelectedText, .wholeDocument, .writeSelection, .drawCursor,
        .lineStartKey, .lineEndKey, .documentStartKey, .documentEndKey,
    ])
    var ignoredBackspace = Sim(text: "one\ntwo", caret: 7, profile: backspaceLane)
    ignoredBackspace.emulatesKeys = true
    ignoredBackspace.ignoredChords = [.deleteBack]
    ignoredBackspace.type("dd")
    precondition(ignoredBackspace.text == "one\ntwo" && ignoredBackspace.caret == 7 && ignoredBackspace.settleFailures == 1)
    ignoredBackspace.ignoredChords = []
    ignoredBackspace.type("dd")
    precondition(ignoredBackspace.text == "one" && ignoredBackspace.caret == 0)
    var ignoredInBreaks = Sim(text: "one\ntwo\n", caret: 8, profile: adding([.drawCursor], to: writeKeys))
    ignoredInBreaks.emptyParagraphs = true
    ignoredInBreaks.readModel = .textContent
    ignoredInBreaks.webContent = true
    ignoredInBreaks.emulatesKeys = true
    ignoredInBreaks.ignoredChords = [.deleteBack]
    ignoredInBreaks.type("dd")
    precondition(ignoredInBreaks.text == "one\ntwo\n" && ignoredInBreaks.caret == 8 && ignoredInBreaks.settleFailures == 1)
    ignoredInBreaks.ignoredChords = []
    ignoredInBreaks.type("dd")
    precondition(ignoredInBreaks.text == "one\ntwo" && ignoredInBreaks.caret == 4)
    var partly = Sim(text: "one\n\u{2060}last", caret: 9, profile: adding([.drawCursor], to: writeKeys))
    partly.emptyParagraphs = true
    partly.listLines = [Sim.ListLine(), Sim.ListLine()]
    partly.readModel = .textContent
    partly.emulatesKeys = true
    partly.swallowsReplace = true
    partly.ignoredChords = [.right]
    partly.type("dd")
    precondition(partly.text == "one" && partly.caret == 0 && partly.settleFailures == 0)
    for ignored in [Chord.paragraphStart, Chord.paragraphEnd.shifted, .deleteBack] {
        var stuck = Sim(text: lastThree, caret: 10, profile: keyProfile)
        stuck.emulatesKeys = true
        stuck.ignoredChords = [ignored]
        stuck.type("dd")
        precondition(stuck.text == lastThree && stuck.caret >= 8 && stuck.settleFailures == 1, "\(ignored)")
        stuck.ignoredChords = []
        stuck.type("dd")
        precondition(stuck.text == "one\ntwo", "\(ignored)")
    }
    var upward = Sim(text: lastThree, caret: 10, profile: adding([.drawCursor], to: writeKeys))
    upward.emptyParagraphs = true
    upward.readModel = .textContent
    upward.webContent = true
    upward.emulatesKeys = true
    upward.ignoredChords = [.deleteBack]
    upward.type("dk")
    precondition(upward.text == lastThree && upward.caret >= 8)
    upward.ignoredChords = []
    upward.type("dk")
    precondition(upward.text == "one")
    var emptyUpward = Sim(text: "one\n\n", caret: 5, profile: axProfile)
    emptyUpward.emptyParagraphs = true
    emptyUpward.readModel = .textContent
    emptyUpward.webContent = true
    emptyUpward.emulatesKeys = true
    emptyUpward.ignoredChords = [.deleteBack]
    emptyUpward.type("dk")
    precondition(emptyUpward.text == "one\n\n" && emptyUpward.caret == 5)
    emptyUpward.ignoredChords = []
    emptyUpward.type("dk")
    precondition(emptyUpward.text == "one")
    var belowEmpty = Sim(text: "one\n\nthree", caret: 5, profile: readProfile)
    belowEmpty.emptyParagraphs = true
    belowEmpty.readModel = .textContent
    belowEmpty.webContent = true
    belowEmpty.emulatesKeys = true
    belowEmpty.ignoredChords = [.right]
    belowEmpty.type("dd")
    precondition(belowEmpty.text == "one\n\nthree" && belowEmpty.caret >= 5)
    belowEmpty.ignoredChords = []
    belowEmpty.type("dd")
    precondition(belowEmpty.text == "one\n")
    precondition(PhysicalPlanner.collapse(3..<6, toEnd: true, profile: writeKeys) == PhysicalPlan(.press(.right, count: 1), .settle(Expectation(selection: 6..<6))))
    precondition(PhysicalPlanner.collapse(3..<6, misread: true, toEnd: true, profile: writeKeys) == PhysicalPlan(.press(.right, count: 1)))
    for (text, caret, keys) in [("one\ntwo", 7, "dd"), ("one\ntwo\n", 4, "2dd"), (lastThree, 5, "dG")] {
        var unread = Sim(text: text, caret: caret, profile: axProfile)
        unread.emulatesKeys = true
        unread.unreadableSelection = true
        unread.type(keys)
        unread.unreadableSelection = false
        unread.type(keys)
        precondition(unread.text == "one", keys)
    }
    for profile in [adding([.drawCursor], to: writeKeys), backspaceLane, keyProfile] {
        var deaf = Sim(text: "one\ntwo\n", caret: 8, profile: profile)
        deaf.emptyParagraphs = true
        deaf.readModel = .textContent
        deaf.webContent = true
        deaf.emulatesKeys = true
        deaf.ignoredChords = [.deleteBack, .right]
        deaf.type("dd")
        precondition(deaf.text == "one\ntwo\n" && deaf.caret == 8)
        deaf.ignoredChords = []
        deaf.type("dd")
        precondition(deaf.text == "one\ntwo")
    }

    // Undoing a linewise delete puts the cursor on the first restored line's first non-blank, as Vim does, whatever the host selects.
    let restored = TextModel("one\ntwo\nthree")
    precondition(restored.restoredLines(from: "one\ntwo", selection: 7..<7)?.lines == 8..<13 && restored.restoredLines(from: "one\nthree", selection: 4..<4)?.lines == 4..<8)
    precondition(restored.restoredLines(from: "two\nthree", selection: 0..<0)?.lines == 0..<4 && restored.restoredLines(from: "", selection: 0..<0)?.lines == 0..<13)
    precondition(restored.restoredLines(from: "one\ntwo", selection: 7..<7)?.ending == true && restored.restoredLines(from: "one\nthree", selection: 4..<4)?.ending == false)
    precondition(restored.restoredLines(from: "one\ntwo three", selection: 7..<7) == nil, "J's undo")
    precondition(restored.restoredLines(from: "one\nwo\nthree", selection: 4..<4) == nil && restored.restoredLines(from: "one\ntwo\nthree", selection: 0..<0) == nil)
    precondition(TextModel("one\nnew\ntwo").restoredLines(from: "one\nTWO", selection: 4..<4) == nil, "lines back, and a line changed")
    precondition(TextModel("one\ntwo\ntwo\nthree").restoredLines(from: "one\ntwo\nthree", selection: 4..<4)?.lines == 4..<8)
    precondition(TextModel("one\ntwo\ntwo\nthree").restoredLines(from: "one\ntwo\nthree", selection: 8..<8)?.lines == 8..<12)
    precondition(TextModel("\n\n").restoredLines(from: "\n", selection: 0..<0)?.lines == 0..<1 && TextModel("\n\n").restoredLines(from: "", selection: 0..<0)?.lines == 1..<2)
    precondition(TextModel("one\ntwo\n\n\n").restoredLines(from: "one\ntwo\n\n", selection: 9..<9)?.lines == 10..<10, "the break above an empty last line")
    precondition(TextModel("one\u{200B}\ntwo\u{200B}\nthree\u{200B}").restoredLines(from: "one\u{200B}\ntwo\u{200B}\u{200B}", selection: 9..<9)?.lines == 10..<15)
    precondition(TextModel("one\n\ntwo").restoredLines(from: "one\ntwo", selection: 0..<4) == nil, "gJ's undo")
    precondition(TextModel("one \n\ntwo").restoredLines(from: "one \ntwo", selection: 0..<5) == nil, "J's undo after a trailing space")
    precondition(TextModel("one\n\n").restoredLines(from: "one\n", selection: 0..<4) == nil, "gJ's undo before an empty last line")
    precondition(TextModel("one\n\n").restoredLines(from: "one\n", selection: 4..<5)?.lines == 5..<5)
    precondition(TextModel("a\n").restoredLines(from: "a", selection: 0..<2) == nil && TextModel(" \n").restoredLines(from: " ", selection: 0..<2) == nil,
                 "joins of a one-character line")
    precondition(TextModel("a\n").restoredLines(from: "a", selection: 1..<2)?.lines == 2..<2)
    precondition(TextModel("one\u{200B}\ntwo\u{200B}").restoredLines(from: "one\u{200B}", selection: 3..<4)?.lines == 5..<9,
                 "a selection pulled back before the line's U+200B")
    precondition(restored.restoredLines(from: "one\ntwo", selection: 4..<4)?.lines == 8..<13, "a caret left on the line above")
    precondition(TextModel("one\n\ntwo").restoredLines(from: "one\ntwo", selection: 4..<4)?.lines == 4..<5)
    precondition(restored.restoredLines(from: "one\nthree", selection: 3..<3)?.lines == 4..<8, "a caret read on the paragraph above's side")
    let landing = PhysicalPlanner.undoLanding(
        before: "one\ntwo", snapshot: FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", selection: 7..<13, length: 13)
    )
    precondition(landing?.ending == 8..<13 && landing?.plan.steps == [
        .setSelection(8..<8),
        .settle(Expectation(selection: 8..<8, length: 13)),
        .setSelection(8..<9),
        .commit(.setCursor(8..<9)),
    ])
    precondition(PhysicalPlanner.undoLanding(
        before: "one\nthree", snapshot: FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", selection: 4..<8, length: 13)
    )?.ending == nil, "a middle line restored")
    let onLines = PhysicalStep.softSettle(Expectation(landing: .caretWithin(8...13), length: 13))
    let atEnd = PhysicalStep.softSettle(Expectation(selection: 13..<13, length: 13))
    let fallen = FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", selection: 7..<13, length: 13)
    precondition(PhysicalPlanner.undoFallback(onto: 8..<13, snapshot: fallen)?.steps == [
        .press(.down, count: 1), .press(.right, count: 1), .press(.documentEnd, count: 1), atEnd,
    ])
    let twoAbove = FieldSnapshot(capabilities: keyProfile, text: "one\ntwo\nthree", selection: 3..<3, length: 13)
    precondition(PhysicalPlanner.undoFallback(onto: 8..<13, snapshot: twoAbove)?.steps == [
        .press(.down, count: 2), .press(.right, count: 5), .press(.documentEnd, count: 1), atEnd,
    ])
    precondition(PhysicalPlanner.undoFallback(onto: 8..<13, snapshot: twoAbove, selecting: true)?.steps == [
        .press(.selectDown, count: 2), .press(.right, count: 1), onLines,
    ])
    precondition(PhysicalPlanner.undoFallback(
        onto: 8..<13, snapshot: FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", selection: 9..<9, length: 13)
    ) == nil)
    let selectionUnread = FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", length: 13)
    precondition(PhysicalPlanner.undoFallback(onto: 8..<13, snapshot: selectionUnread)?.steps == [
        .press(.down, count: 1), .press(.right, count: 1), .press(.documentEnd, count: 1),
    ])
    precondition(PhysicalPlanner.undoFallback(onto: 8..<13, snapshot: selectionUnread, selecting: true) == nil)
    precondition(PhysicalPlanner.undoLanding(
        before: "one\ntwo\nthree", snapshot: FieldSnapshot(capabilities: axProfile, text: "one\ntwo\nthree", selection: 7..<8)
    ) == nil)
    precondition(physical("u", text: "one\ntwo", caret: 4, profile: axProfile).steps == [.press(.undo, count: 1), .commit(.setCursor(nil))])
    for (rich, shape, late) in [(false, Sim.UndoSelection.restored, false), (false, .throughBreak, true), (true, .toBreak, true),
                                (true, .restored, false)] {
        for profile in [axProfile, writeKeys, keyProfile, readProfile] {
            func host(_ text: String, _ caret: Int) -> Sim {
                var sim = Sim(text: text, caret: caret, profile: profile)
                sim.emulatesKeys = true
                sim.undoSelection = shape
                sim.undoesLate = late
                if rich {
                    sim.emptyParagraphs = true
                    sim.readModel = .textContent
                    sim.webContent = true
                }
                return sim
            }
            let context = "\(shape) rich=\(rich) \(profile.has(.writeSelection) ? "writes" : "keys")"
            for (text, caret, keys, restoredLine, after) in [
                (lastThree, 10, "ddu", 8, "one\ntwo"), ("one\ntwo\n  three", 15, "ddu", 10, "one\ntwo"),
                (lastThree, 5, "dGu", 4, "one\nthree"), (lastThree, 1, "jddu", 4, "one\nthree"),
                ("one\ntwo\n", 8, "ddu", 8, "one\ntwo"), ("one\n\nthree", 4, "ddu", 4, "one\nthree"),
                ("one\n  two\nthree", 6, "ddu", 6, "one\nthree"),
            ] {
                var sim = host(text, caret)
                sim.type(keys)
                precondition(sim.text == text && sim.settleFailures == 0, "\(keys) in \(text.debugDescription), \(context)")
                precondition(sim.caret == restoredLine, "\(keys) in \(text.debugDescription), \(context): \(sim.caret)")
                if keys.hasPrefix("dd") || keys.hasPrefix("j"), profile.has(.writeSelection) || profile.has(.lineStartKey) {
                    sim.type("dd")
                    precondition(sim.text == after, "\(keys)dd in \(text.debugDescription), \(context): \(sim.text.debugDescription)")
                }
            }
            let faults: [(inout Sim) -> Void] = [
                { $0.swallowsSelect = true }, { $0.ignoredChords = [.documentEnd] }, { $0.ignoredChords = [.down] },
                { $0.swallowsSelect = true; $0.ignoredChords = [.right] }, { $0.ignoredChords = [.documentEnd, .right] },
                { $0.ignoredChords = [.down, .right] }, { $0.ignoredChords = [.down, .documentEnd] },
            ]
            for fault in faults {
                for (caret, keys, after) in [(10, "dd", "one\ntwo"), (10, "dk", "one\nthree"), (0, "jdd", "one\nthree")] {
                    var failing = host(lastThree, caret)
                    failing.type(keys)
                    fault(&failing)
                    failing.type("u")
                    (failing.swallowsSelect, failing.ignoredChords) = (false, [])
                    failing.type("dd")
                    precondition(failing.text == after || keys == "dk" && failing.text == "one\ntwo",
                                 "\(keys)udd with a failed landing, \(context): \(failing.text.debugDescription)")
                }
            }
            for (text, keys, after) in [("one\n\ntwo", "gJudd", "\ntwo"), ("one \n\ntwo", "Judd", "\ntwo"), ("one\n\n", "gJudd", "\n"),
                                        ("one \n\n", "Judd", "\n"), ("a\n", "gJudd", ""), (" \n", "Judd", "")] {
                var join = host(text, 0)
                join.type(keys)
                precondition(join.text == after, "\(keys) in \(text.debugDescription), \(context): \(join.text.debugDescription)")
            }
            var upward = host(lastThree, 10)
            upward.type("dku")
            upward.type("dd")
            precondition(["one\nthree", "one\ntwo"].contains(upward.text), "dkudd, \(context): \(upward.text.debugDescription)")
            var twice = host("one\ntwo\nthree\nfour", 14)
            twice.type("dddduu")
            precondition(twice.text == "one\ntwo\nthree\nfour" && TextModel(twice.text).lineStart(of: twice.caret) == 14, "dddduu, \(context)")
            twice.type("dd")
            precondition(twice.text == "one\ntwo\nthree", "dddduudd, \(context): \(twice.text.debugDescription)")
            // An app that groups the second delete's lone ⌫ with the first's undoes both at once, which still end the text.
            var grouped = host("one\ntwo\n", 4)
            grouped.type("ddddudd")
            precondition(grouped.text.hasPrefix("one"), "ddddudd, \(context): \(grouped.text.debugDescription)")
            var redone = host(lastThree, 10)
            redone.type("ddu")
            redone.feed("<C-r>")
            precondition(redone.text == "one\ntwo", "ddu⌃R, \(context): \(redone.text.debugDescription)")
            redone.type("udd")
            precondition(redone.text == "one\ntwo", "ddu⌃Rudd, \(context): \(redone.text.debugDescription)")
            let zw = "\u{200B}"
            var invisible = host("one\(zw)\ntwo\(zw)", 6)
            invisible.type("ddu")
            precondition(invisible.text == "one\(zw)\ntwo\(zw)" && invisible.caret >= 5, "ddu with line-end runs, \(context): \(invisible.caret)")
            invisible.type("dd")
            precondition(invisible.text == "one\(zw)\(zw)" && invisible.settleFailures == 0,
                         "dduddd with line-end runs, \(context): \(invisible.text.debugDescription)")
            var stale = host(lastThree, 10)
            stale.type("dd0x")
            stale.type("u")
            precondition(stale.text == "one\ntwo", "\(context): \(stale.text.debugDescription)")
            stale.type("u")
            stale.type("dd")
            precondition(stale.text == "one\ntwo" && stale.settleFailures == 0, "dd0xuudd, \(context): \(stale.text.debugDescription)")
            var obsolete = host("one\ntwo\nthree\nfour", 14)
            obsolete.type("ddddux")
            obsolete.feed("<C-r>")
            obsolete.type("uudd")
            precondition(obsolete.text == "one\ntwo\nthree", "ddddux⌃Ruudd, \(context): \(obsolete.text.debugDescription)")
            var ignored = host(lastThree, 10)
            ignored.type("dd")
            ignored.ignoredChords = [.undo]
            ignored.type("u")
            ignored.ignoredChords = []
            ignored.type("udd")
            precondition(ignored.text == "one\ntwo", "dd, u ignored, udd, \(context): \(ignored.text.debugDescription)")
            // Hosts that group the last two Backspaces restore both empty lines at the first `u`, so the second restores the last.
            var coalesced = host("one\ntwo\n\n\n", 10)
            coalesced.type("ddkjdddduu")
            let undone = coalesced.text
            coalesced.type("iX")
            coalesced.feed("<Esc>")
            precondition(coalesced.text == undone + "X", "ddkjdddduuiX, \(context): \(coalesced.text.debugDescription)")
        }
    }
    let hundred = (0...101).map { "line-\($0)" }
    for profile in [axProfile, keyProfile] {
        var deep = Sim(text: hundred.joined(separator: "\n"), caret: 0, profile: profile)
        deep.emulatesKeys = true
        deep.type("G")
        for _ in 0...100 { deep.type("dd") }
        for _ in 0...100 { deep.type("u") }
        deep.type("dd")
        precondition(deep.text == hundred.dropLast().joined(separator: "\n"), deep.text.suffix(30).debugDescription)
    }
    for (rich, profile) in [(true, adding([.lineStartKey, .lineEndKey, .documentStartKey, .documentEndKey], to: readProfile)),
                            (false, adding([.writeSelection, .insertText, .drawCursor], to: readProfile))] {
        var unmeasured = Sim(text: "one\ntwo\nthree\nfour", caret: 14, profile: removing([.readLength], from: profile))
        unmeasured.emulatesKeys = true
        unmeasured.undoesLate = true
        unmeasured.undoSelection = rich ? .toBreak : .restored
        if rich {
            unmeasured.emptyParagraphs = true
            unmeasured.readModel = .textContent
            unmeasured.webContent = true
        }
        unmeasured.type("ddudd")
        precondition(unmeasured.text == "one\ntwo\nthree", "without readLength, rich=\(rich): \(unmeasured.text.debugDescription)")
    }
    // An undo shown only after the wait lands at the next command, before it plans (LIN-2104).
    for (rich, shape) in [(false, Sim.UndoSelection.restored), (false, .throughBreak), (true, .toBreak), (true, .restored)] {
        for (profile, nextWait) in [axProfile, writeKeys, keyProfile, readProfile].flatMap({ p in [(p, false), (p, true)] }) {
            func late(_ text: String, _ caret: Int) -> Sim {
                var sim = Sim(text: text, caret: caret, profile: profile)
                sim.emulatesKeys = true
                sim.undoSelection = shape
                sim.undoesAfterWait = true
                sim.undoesInNextWait = nextWait
                if rich {
                    sim.emptyParagraphs = true
                    sim.readModel = .textContent
                    sim.webContent = true
                }
                return sim
            }
            let context = "\(shape) rich=\(rich) \(profile.has(.writeSelection) ? "writes" : "keys") nextWait=\(nextWait)"
            let edits = profile.has(.writeSelection) || profile.has(.lineStartKey)
            for (text, caret, keys, restoredLine, after) in [
                (lastThree, 10, "ddu", 8, "one\ntwo"), ("one\ntwo\n  three", 15, "ddu", 10, "one\ntwo"),
                (lastThree, 1, "jddu", 4, "one\nthree"), ("one\ntwo\n", 8, "ddu", 8, "one\ntwo"), ("one\n\nthree", 4, "ddu", 4, "one\nthree"),
                ("one\n  two\nthree", 6, "ddu", 6, "one\nthree"), ("one\ntwo\nthree\nfour", 14, "dddduu", 14, "one\ntwo\nthree"),
            ] {
                var sim = late(text, caret)
                sim.type(keys)
                sim.type("^")
                precondition(sim.caret == restoredLine, "\(keys)^ shown late in \(text.debugDescription), \(context): \(sim.caret)")
                guard edits else { continue }
                sim.type("dd")
                precondition(sim.text == after, "\(keys)^dd shown late in \(text.debugDescription), \(context): \(sim.text.debugDescription)")
            }
            guard edits else { continue }
            var clicked = late(lastThree, 10)
            clicked.type("ddu")
            clicked.click(at: 0)
            clicked.type("dd")
            precondition(clicked.text == "two\nthree", "ddu shown late, a click, dd, \(context): \(clicked.text.debugDescription)")
            var nothing = late(lastThree, 4)
            nothing.type("udd")
            precondition(nothing.text == "one\nthree", "u with nothing to undo, dd, \(context): \(nothing.text.debugDescription)")
        }
    }
    let restoredTail = (1...60).map { "l\($0)" }.joined(separator: "\n")
    for profile in [keyProfile, readProfile] {
        // The fallback reaches lines that end the text from a caret far above them in a few keys, ⌘↓ among them.
        let far = FieldSnapshot(capabilities: profile, text: restoredTail, selection: 0..<0, length: restoredTail.utf16.count)
        for selecting in [false, true] {
            let steps = PhysicalPlanner.undoFallback(onto: 119..<restoredTail.utf16.count, snapshot: far, selecting: selecting)?.steps ?? []
            let pressed = steps.reduce(0) { if case .press(_, let count) = $1 { return $0 + count }; return $0 }
            precondition(pressed > 0 && pressed <= 21 && (selecting || steps.contains(.press(.documentEnd, count: 1))), "\(steps)")
            // Each stage's settle waits for its last key: ⌘↓'s text end, or a caret only → leaves.
            guard case .softSettle(let last)? = steps.last else { preconditionFailure("\(steps)") }
            let end = restoredTail.utf16.count
            precondition(last.landing == (selecting ? .caretWithin(119...end) : .exact(end..<end)), "\(String(describing: last.landing))")
        }
        var tail = Sim(text: restoredTail, caret: 3, profile: profile)
        tail.emulatesKeys = true
        tail.type("dG")
        let beforeU = tail.presses
        tail.type("u")
        precondition(tail.text == restoredTail && tail.caret >= 3 && tail.presses - beforeU <= PhysicalPlanner.undoKeys + 1,
                     "dGu over 59 lines: \(tail.caret), \(tail.presses - beforeU) keys")
        guard profile.has(.lineStartKey) else { continue }
        tail.type("dd")
        precondition(tail.text.hasPrefix("l1\n") && tail.text.split(separator: "\n").count == 59, "dGudd over 59 lines: \(tail.text.suffix(20))")
    }
    // A caret left far above the restored lines with ⌘↓ ignored: the fallbacks' ten ↓ at a time go on at the next command.
    for nextWait in [false, true] {
        var far = Sim(text: restoredTail, caret: 147, profile: keyProfile)
        far.emulatesKeys = true
        far.undoSelection = .start
        far.type("dG")
        far.ignoredChords = [.documentEnd]
        far.undoesAfterWait = nextWait
        far.type("u")
        far.ignoredChords = []
        far.type("dd")
        let gone = (1...60).filter { !far.text.split(separator: "\n").contains("l\($0)"[...]) }
        precondition(gone.count == 1 && gone[0] >= 40, "dG, u from a caret far above, dd removed \(gone)")
    }
    // A walk to a deep indent's first non-blank runs out of keys on the restored line, which the next command then acts on.
    let indented = "a\n" + String(repeating: " ", count: 70) + "b\nc"
    var indent = Sim(text: indented, caret: 2, profile: readProfile)
    indent.emulatesKeys = true
    indent.type("ddu")
    precondition(indent.text == indented && (2..<72).contains(indent.caret), "dd u under a deep indent: \(indent.caret)")
    indent.type("dd")
    precondition(indent.text == "a\nc", "dd u dd under a deep indent: \(indent.text.debugDescription)")
    // A `G` walked down from far above runs out of keys short of the restored last lines, and the fallback steps onto them.
    var short = Sim(text: restoredTail, caret: 207, profile: readProfile)
    short.emulatesKeys = true
    short.undoSelection = .start
    short.type("dGu")
    short.type("dd")
    let shortGone = (1...60).filter { !short.text.split(separator: "\n").contains("l\($0)"[...]) }
    precondition(shortGone.count == 1 && shortGone[0] >= 55, "dG u from far above, dd removed \(shortGone)")
    // A walk cut short with ↓ ignored leaves the fallbacks their own keys, and their → and ⌘↓ reach the restored lines.
    var cutWalk = Sim(text: restoredTail, caret: 3, profile: readProfile)
    cutWalk.emulatesKeys = true
    cutWalk.undoSelection = .start
    cutWalk.type("dG")
    cutWalk.ignoredChords = [.down]
    let beforeCut = cutWalk.presses
    cutWalk.type("u")
    cutWalk.ignoredChords = []
    precondition(cutWalk.presses - beforeCut <= PhysicalPlanner.undoKeys + 33, "u pressed \(cutWalk.presses - beforeCut) keys")
    cutWalk.type("dd")
    let cutRows = cutWalk.text.split(separator: "\n")
    precondition(cutRows.count == 59 && cutRows.first == "l1", "dG u dd, ↓ ignored during u: \(cutWalk.text.prefix(12).debugDescription)")
    // The deadline cutting `u`'s landing before its second fallback stage, every key ignored meanwhile: the next command still lands.
    var cutShort = Sim(text: "one\ntwo\nthree", caret: 8, profile: keyProfile)
    cutShort.emulatesKeys = true
    cutShort.type("dd")
    (cutShort.ignoredChords, cutShort.plansBeforeDeadline) = ([.documentEnd, .down, .right], 2)
    cutShort.type("u")
    (cutShort.ignoredChords, cutShort.plansBeforeDeadline) = ([], nil)
    cutShort.type("dd")
    precondition(cutShort.text == "one\ntwo", "dd u dd, the deadline cutting u's fallbacks: \(cutShort.text.debugDescription)")
    // Faults kept and the deadline cutting every attempt after two plans: the next attempt resumes at the second fallback, which lands.
    for profile in [keyProfile, readProfile] {
        var kept = Sim(text: "one\ntwo\nthree", caret: 8, profile: profile)
        kept.emulatesKeys = true
        kept.type("dd")
        (kept.ignoredChords, kept.holdsRightAtLineEnds, kept.plansBeforeDeadline) = ([.down, .documentEnd], true, 2)
        kept.type("u")
        let keptBells = kept.bells
        kept.type("dd")
        precondition(kept.text == "one\ntwo" && kept.bells == keptBells, "dd u dd, faults kept: \(kept.text.debugDescription)")
    }
    // After a pending miss, a read without the caret decides nothing: that command is refused, and the next one lands.
    var noCaretRead = Sim(text: restoredTail, caret: 147, profile: keyProfile)
    noCaretRead.emulatesKeys = true
    noCaretRead.undoSelection = .start
    noCaretRead.type("dG")
    noCaretRead.ignoredChords = [.documentEnd]
    noCaretRead.type("u")
    (noCaretRead.ignoredChords, noCaretRead.unansweredSelectionsAside) = ([], 1)
    let noCaretReadBells = noCaretRead.bells
    noCaretRead.type("dd")
    precondition(noCaretRead.text == restoredTail && noCaretRead.bells == noCaretReadBells + 1, "dd after an unread caret: \(noCaretRead.text.count)")
    noCaretRead.type("dd")
    let noCaretReadGone = (1...60).filter { !noCaretRead.text.split(separator: "\n").contains("l\($0)"[...]) }
    precondition(noCaretReadGone.count == 1 && noCaretReadGone[0] >= 40, "dd after the unread one removed \(noCaretReadGone)")
    // A restored last line equal to the one above stays the target after the walk's keys moved the caret onto that one.
    for keep in [true, false] {
        var twin = Sim(text: "a\na", caret: 2, profile: readProfile)
        (twin.emulatesKeys, twin.undoSelection) = (true, .toBreak)
        twin.type("dd")
        (twin.ignoredChords, twin.holdsRightAtLineEnds, twin.plansBeforeDeadline) = ([.down, .documentEnd], true, 1)
        twin.type("u")
        if !keep { (twin.ignoredChords, twin.holdsRightAtLineEnds, twin.plansBeforeDeadline) = ([], false, nil) }
        twin.type("iX")
        twin.feed("<Esc>")
        let twinRows = twin.text.split(separator: "\n", omittingEmptySubsequences: false)
        precondition(twinRows.first == "a" && (keep || twinRows.last?.contains("X") == true), "dd u iX on twin lines: \(twin.text.debugDescription)")
    }
    // A field that ignores every landing key keeps the caret where `u` left it, and the next command runs there, as in #64.
    var ignoring = Sim(text: restoredTail, caret: 147, profile: keyProfile)
    ignoring.emulatesKeys = true
    ignoring.undoSelection = .start
    ignoring.type("dG")
    ignoring.ignoredChords = [.up, .down, .left, .right, .lineStart, .lineEnd, .documentEnd, .selectDown, .paragraphStart, .paragraphEnd]
    ignoring.type("u")
    let rang = ignoring.bells
    ignoring.type("iX")
    precondition(ignoring.text == "X" + restoredTail && ignoring.bells == rang,
                 "\(ignoring.bells - rang) refused after a landing the field ignored: \(ignoring.text.prefix(20).debugDescription)")
    // Lark's field with ↓ and ⌘↓ ignored during `u`: the walk's check fails, and the fallbacks' ⇧↓ and → reach the restored lines.
    let larkLines = (1...30).map { "l\($0)\(zw)" }
    var larkTail = blankSim(larkLines, caret: 4, profile: keyProfile)
    (larkTail.webContent, larkTail.pullsBackFromLineEnds, larkTail.runsAreNewlines) = (true, true, true)
    larkTail.undoSelection = .toBreak
    larkTail.type("dG")
    larkTail.ignoredChords = [.down, .documentEnd]
    larkTail.type("u")
    larkTail.ignoredChords = []
    larkTail.type("iX")
    larkTail.feed("<Esc>")
    let larkRows = larkTail.text.split(separator: "\n", omittingEmptySubsequences: false)
    precondition(larkRows.count == 30 && larkRows[0] == "l1\(zw)" && larkRows.dropFirst().contains { $0.contains("X") },
                 "dG u iX over 29 Lark lines, ↓ and ⌘↓ ignored: \(larkTail.text.prefix(40).debugDescription)")
    var appKey = Sim(text: lastThree, caret: 10, profile: axProfile)
    appKey.undoesAfterWait = true
    appKey.type("ddu")
    appKey.feed("<Esc>")
    appKey.type("dd")
    precondition(appKey.text == "one\nthree", "a key the app gets drops the landing: \(appKey.text.debugDescription)")
    // The focus leaving stops a landing's keys, `u`'s or the next command's, and drops it; the command it held posts nothing.
    for by in [KeyDestination.Departure.app, .click] {
        func row(_ sim: Sim) -> String { "l\(sim.text.prefix(sim.caret).filter { $0 == "\n" }.count + 1)" }
        var leftU = Sim(text: restoredTail, caret: 147, profile: readProfile)
        (leftU.emulatesKeys, leftU.undoSelection) = (true, .start)
        leftU.type("dG")
        let beforeLeftU = (leftU.presses, leftU.bells)
        leftU.focusLeaves = (6, 0, by)
        leftU.type("u")
        precondition(leftU.presses - beforeLeftU.0 == 6 && leftU.departure == by && leftU.bells == beforeLeftU.1, "\(by) during u's landing")
        let leftURow = row(leftU)
        leftU.type("dd")
        precondition(leftU.text.split(separator: "\n").count == 59 && !leftU.text.split(separator: "\n").contains(leftURow[...]),
                     "dd after \(by) during u's landing on \(leftURow): \(leftU.text.suffix(12).debugDescription)")
        var leftNext = Sim(text: restoredTail, caret: 147, profile: keyProfile)
        (leftNext.emulatesKeys, leftNext.undoSelection, leftNext.undoesAfterWait) = (true, .start, true)
        leftNext.type("dGu")
        let beforeLeftNext = (leftNext.presses, leftNext.bells)
        leftNext.focusLeaves = (3, 0, by)
        leftNext.type("dd")
        precondition(leftNext.presses - beforeLeftNext.0 == 3 && leftNext.departure == by && leftNext.text == restoredTail
                     && leftNext.bells == beforeLeftNext.1, "\(by) during the next command's landing")
        let leftNextRow = row(leftNext)
        leftNext.type("dd")
        precondition(!leftNext.text.split(separator: "\n").contains(leftNextRow[...]), "the dd after, on \(leftNextRow)")
        var leftWrites = Sim(text: lastThree, caret: 10, profile: axProfile)
        leftWrites.undoesAfterWait = true
        leftWrites.type("ddu")
        (leftWrites.swallowsLandingSelect, leftWrites.focusLeaves) = (true, (0, 0, by))
        leftWrites.type("dd")
        precondition(leftWrites.text == lastThree && leftWrites.departure == by && leftWrites.bells == 0,
                     "\(by) during the landing before a dd that writes: \(leftWrites.text.debugDescription)")
    }
}
