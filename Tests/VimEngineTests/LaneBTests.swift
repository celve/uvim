// MARK: - Lane B from a selection

// Keys settle before an AX write, never before ⌘V.
let insertOnlyProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .insertText, .wholeDocument,
])

func testLaneBFromSelection() {
    // Dia kept `0..8` here (`e14287.c993`): lane B must collapse a selection before counting.
    precondition(physical("<Esc>", text: "abcdefgh", selection: 0..<8, profile: readProfile, state: inserting).steps == [
        .press(.left, count: 1),
        .settle(Expectation(selection: 0..<0, length: 8)),
        .commit(.setMode(.normal)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("<Esc>", text: "abcdefgh", selection: 3..<8, profile: readProfile, state: inserting).steps == [
        .press(.left, count: 1),
        .press(.left, count: 1),
        .settle(Expectation(selection: 2..<2, length: 8)),
        .commit(.setMode(.normal)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("<Esc>", text: "ab\ncdefgh", selection: 3..<6, profile: readProfile, state: inserting).steps == [
        .press(.left, count: 1),
        .settle(Expectation(selection: 3..<3, length: 9)),
        .commit(.setMode(.normal)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("<Esc>", text: "abcdefgh", caret: 0, profile: readProfile, state: inserting).steps == [
        .settle(Expectation(selection: 0..<0, length: 8)),
        .commit(.setMode(.normal)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("<Esc>", text: "abcdefgh", caret: 8, profile: readProfile, state: inserting).steps == [
        .press(.left, count: 1),
        .settle(Expectation(selection: 7..<7, length: 8)),
        .commit(.setMode(.normal)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("<Esc>", text: "abcdefgh", selection: 0..<8, profile: axProfile, state: inserting).steps == [
        .setSelection(0..<0),
        .settle(Expectation(selection: 0..<0, length: 8)),
        .commit(.setMode(.normal)),
        .setSelection(0..<1),
        .commit(.setCursor(0..<1)),
    ])

    for (anchor, head, key) in [(0, 8, Chord.right), (8, 0, Chord.left)] {
        var selecting = VimState.initial
        selecting.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: anchor))
        precondition(PhysicalPlanner.plan(
            LogicalPlanner.plan(RawCommand("<Esc>"), state: selecting),
            snapshot: FieldSnapshot(capabilities: readProfile, text: "abcdefgh", selection: 0..<8, anchor: anchor)
        ).steps == [
            .press(key, count: 1),
            .settle(Expectation(selection: head..<head, length: 8)),
            .commit(.setMode(.normal)),
            .commit(.setCursor(nil)),
        ])
    }

    var stranded = VimState.initial
    stranded.session.registers.unnamed = .content(RegisterContent(text: "XY", wise: .character))
    for keys in ["h", "l", "a", "x", "ciw", "p", "J"] {
        let steps = physical(keys, text: "say hello\nworld", selection: 5..<9, profile: readProfile, state: stranded).steps
        precondition(steps.first == .press(.left, count: 1), "\(keys) must collapse the selection before counting")
    }
    precondition(physical("ciw", text: "say hello world", selection: 5..<15, profile: readProfile).steps == [
        .press(.left, count: 1),
        .press(.left, count: 1),
        .press(.selectRight, count: 5),
        .settle(Expectation(selection: 4..<9, length: 15)),
        .settle(Expectation(selection: 4..<9, length: 15, selectedText: "hello")),
        .press(.deleteBack, count: 1),
        .softSettle(deleting(Expectation(selection: 4..<4, length: 10), 4..<9, before: 15)),
        .commit(.deleted(into: nil, content: .literal("hello"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(4)),
    ])

    precondition(physical("p", text: "say hello\nworld", selection: 5..<9, profile: insertOnlyProfile, state: stranded).steps == [
        .press(.left, count: 1),
        .press(.right, count: 1),
        .settle(Expectation(selection: 6..<6, length: 15)),
        .replaceSelection("XY"),
        .settle(Expectation(selection: 8..<8, length: 17)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("\"+p", text: "say hello\nworld", selection: 5..<9, profile: insertOnlyProfile).steps == [
        .press(.left, count: 1),
        .press(.right, count: 1),
        .clipboardInsert(nil),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("J", text: "say hello\nworld", selection: 5..<9, profile: insertOnlyProfile).steps == [
        .press(.left, count: 1),
        .press(.left, count: 5),
        .press(.selectRight, count: 15),
        .settle(Expectation(selection: 0..<15, length: 15, selectedText: "say hello\nworld")),
        .replaceSelection("say hello world"),
        .settle(Expectation(selection: 15..<15, length: 15)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("p", text: "say hello\nworld", selection: 5..<9, profile: readProfile, state: stranded).steps == [
        .press(.left, count: 1),
        .press(.right, count: 1),
        .clipboardInsert("XY"),
        .softSettle(Expectation(selection: 8..<8, length: 17)),
        .commit(.setCursor(nil)),
    ])

    // A re-resolve can drop `writeSelection` while the cursor stays drawn.
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("P"), state: stranded),
        snapshot: FieldSnapshot(capabilities: insertOnlyProfile, text: "abc", selection: 1..<2, cursor: 1..<2)
    ).steps == [
        .press(.left, count: 1),
        .settle(Expectation(selection: 1..<1, length: 3)),
        .replaceSelection("XY"),
        .settle(Expectation(selection: 3..<3, length: 5)),
        .commit(.setCursor(nil)),
    ])
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("x"), state: .initial),
        snapshot: FieldSnapshot(capabilities: readProfile, text: "abc", selection: 1..<2, cursor: 1..<2)
    ).steps == [
        .press(.left, count: 1),
        .settle(Expectation(selection: 1..<1, length: 3)),
        .press(.selectRight, count: 1),
        .settle(Expectation(selection: 1..<2, length: 3)),
        .settle(Expectation(selection: 1..<2, length: 3, selectedText: "b")),
        .press(.deleteBack, count: 1),
        .softSettle(deleting(Expectation(selection: 1..<1, length: 2), 1..<2, before: 3)),
        .commit(.deleted(into: nil, content: .literal("b"), wise: .character)),
        .commit(.setCursor(nil)),
    ])

    precondition(PhysicalPlanner.collapse(4..<9, profile: axProfile) == PhysicalPlan(.setSelection(4..<4)))
    for profile in [nativeRead, readProfile] {
        precondition(PhysicalPlanner.collapse(4..<9, profile: profile)
                     == PhysicalPlan(.press(.left, count: 1), .settle(Expectation(selection: 4..<4))))
    }
    precondition(PhysicalPlanner.collapse(4..<9, profile: blindProfile) == PhysicalPlan(.press(.left, count: 1)))
    for profile in [axProfile, nativeRead, readProfile, blindProfile] {
        precondition(PhysicalPlanner.collapse(4..<9, misread: true, profile: profile) == PhysicalPlan(.press(.left, count: 1)))
    }
    precondition(PhysicalPlanner.releaseCursor(6..<7, breaks: ParagraphBreaks(offsets: [3]), profile: axProfile)
                 == PhysicalPlan(.setSelection(5..<5)))
    precondition(PhysicalPlanner.releaseCursor(2..<3, breaks: ParagraphBreaks(offsets: [2]), profile: axProfile)
                 == PhysicalPlan(.setSelection(2..<2)), "no key steps back to a paragraph's end once focus has left")
    precondition(PhysicalPlanner.releaseCursor(6..<7, breaks: nil, profile: readProfile) == nil)
}

// MARK: - Lane B end to end, and hosts that misread the caret

let paragraphs = "alpha beta gamma\ndelta epsilon zeta\neta theta iota"

func testLaneBEndToEnd() {
    for edit in laneBEdits {
        let laneB = typed(edit.keys, text: twoLines, caret: edit.caret, profile: readProfile)
        precondition(laneB.text == typed(edit.keys, text: twoLines, caret: edit.caret, profile: axProfile).text,
                     "lane B must edit what lane A edits: \(edit.keys)")
        precondition(laneB.settleFailures == 0 && laneB.unsupportedSteps == 0, edit.keys)
    }
    sim = Sim(text: "say hello world", caret: 6, profile: readProfile)
    sim.type("ciwbye")
    sim.feed("<Esc>")
    precondition(sim.text == "say bye world")
    precondition(sim.caret == 6)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "bye"))
    precondition(sim.settleFailures == 0 && sim.unsupportedSteps == 0)
    sim = typed("viwd", text: "say hello world", caret: 6, profile: readProfile)
    precondition(sim.text == "say  world" && sim.settleFailures == 0)

    var misread = Sim(text: paragraphs, caret: 7, profile: readProfile)
    misread.reads = omitsBreaks
    misread.type("ciwX")
    misread.feed("<C-[>")
    precondition(misread.text == "alpha X gamma\ndelta epsilon zeta\neta theta iota")
    precondition(misread.state.field.mode == .normal && misread.settleFailures == 0)

    // Paragraph 2: the keys select "psilon " while every offset reads as "epsilon".
    misread = Sim(text: paragraphs, caret: 24, profile: readProfile)
    misread.reads = omitsBreaks
    misread.type("ciw")
    precondition(misread.text == paragraphs && misread.settleFailures == 1)
    precondition(checkedText(misread.abortedStep) == "epsilon", "the offsets settle passes and the text check rings")
    precondition(misread.selection == 24..<24, "a failed check collapses what the keys selected")
    precondition(misread.state.field.mode == .normal, "the operand's offsets must not keep Insert over other text")
    precondition(misread.state.session.register("-") == nil && misread.state.session.lastChange == nil)
    var misreadIgnoresLeft = Sim(text: paragraphs, caret: 24, profile: readProfile)
    misreadIgnoresLeft.reads = omitsBreaks
    misreadIgnoresLeft.ignoredChords = [.left]
    misreadIgnoresLeft.type("ciw")
    precondition(checkedText(misreadIgnoresLeft.abortedStep) == "epsilon" && misreadIgnoresLeft.selection == 24..<31)
    precondition(misreadIgnoresLeft.state.field.mode == .normal)

    var unchecked = Sim(text: paragraphs, caret: 24, profile: readNothingSelected)
    unchecked.reads = omitsBreaks
    unchecked.type("ciwX")
    unchecked.feed("<C-[>")
    precondition(unchecked.text == "alpha beta gamma\ndelta eXzeta\neta theta iota")
    precondition(unchecked.settleFailures == 0)

    for keys in ["x", "3x", "X", "dw", "de", "diw", "D", "C", "s", "S", "cc", "dd", "rZ", "~", "g~iw", "J", "viwd", "viwc"] {
        misread = Sim(text: paragraphs, caret: 24, profile: readProfile)
        misread.reads = omitsBreaks
        misread.type(keys)
        precondition(misread.text == paragraphs && misread.settleFailures == 1, "\(keys) must ring, not edit, in paragraph 2")
        precondition(misread.selection.isEmpty, "\(keys) leaves no selection to type over")
        precondition(checkedText(misread.abortedStep) == nil || !misread.state.field.mode.isInserting, keys)
    }

    // Rule 2: a caret at an element boundary reads as its paragraph's start, in read offsets (as measured).
    let fromBlockStart: [(keys: String, check: String?)] = [("ciw", "\n"), ("dw", "\n"), ("x", nil), ("dd", nil), ("~", nil)]
    for edit in fromBlockStart {
        misread = Sim(text: paragraphs, caret: 24, profile: readProfile)
        misread.reads = { offset, text in offset == 24 ? 16 : omitsBreaks(offset, text) }
        misread.type(edit.keys)
        precondition(misread.text == paragraphs, "\(edit.keys) must not edit from a caret read as its block's start")
        precondition(checkedText(misread.abortedStep) == edit.check, edit.keys)
    }

    // Chromium's AXSelectedText leaves paragraph breaks out, so no edit across one passes, in paragraph 1 too.
    misread = Sim(text: paragraphs, caret: 7, profile: readProfile)
    misread.reads = omitsBreaks
    misread.type("J")
    precondition(misread.text == paragraphs && checkedText(misread.abortedStep) != nil)
    var acrossBreak = VimState.initial
    acrossBreak.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: 10))
    misread = Sim(text: paragraphs, caret: 10, state: acrossBreak, profile: readProfile)
    misread.reads = omitsBreaks
    misread.perform([.setSelection(10..<20)])
    misread.type("d")
    precondition(misread.text == paragraphs && checkedText(misread.abortedStep) == " gamma\nde")
}
