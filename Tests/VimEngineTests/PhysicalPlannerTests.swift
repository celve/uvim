// MARK: - PhysicalPlanner

let axProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .insertText,
    .drawCursor, .wholeDocument,
])
let readProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .wholeDocument,
])
let blindProfile = CapabilityProfile(available: [])
/// axProfile minus the standing cursor's permission: writes stay exact,
/// presentation is suppressed.
let noCursorProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .insertText, .wholeDocument,
])
/// The block-editor shape (Notion): the readable text is one block — exact
/// locally, a lie about the page. Also without drawCursor, as the page's read
/// turns both off.
let blockProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .insertText,
])
/// The reported ChatGPT config: the user turned OFF Replace text (insertText)
/// only. Selection is still exact (writeSelection), so the SELECT is an AX
/// write (hard settle) and only the DELETE rides the blind lane (soft settle).
let noInsertProfile = CapabilityProfile(available: [
    .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .wholeDocument,
])

// ciw in "say hello world" (caret inside "hello") under three profiles.
let ciwA = physical("ciw", text: "say hello world", caret: 6, profile: axProfile)

// p resolves register content at logical time and places it physically.
var putState = VimState.initial

func testPhysicalPlanner() {
    precondition(ciwA.steps == [
        .setSelection(4..<9),
        .settle(Expectation(selection: 4..<9, length: 15)),
        .settle(Expectation(selection: 4..<9, length: 15, selectedText: "hello")),
        .replaceSelection(""),
        .settle(Expectation(selection: 4..<4, length: 10)),
        .commit(.deleted(into: nil, content: .literal("hello"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(4)),
    ])
    precondition(ciwA.mutatesText)

    let ciwB = physical("ciw", text: "say hello world", caret: 6, profile: readProfile)
    precondition(ciwB.steps == [
        .press(.left, count: 2),
        .press(.selectRight, count: 5),
        // Blind SELECT stays a hard settle: if the range mispredicts, aborting is
        // safer than letting the delete hit the wrong text.
        .settle(Expectation(selection: 4..<9, length: 15)),
        .settle(Expectation(selection: 4..<9, length: 15, selectedText: "hello")),
        .press(.deleteBack, count: 1),
        // Blind DELETE is soft: a mismatch here must NOT abort the setMode below —
        // this is the ChatGPT "ciw won't enter insert" bug.
        .softSettle(deleting(Expectation(selection: 4..<4, length: 10), 4..<9, before: 15)),
        .commit(.deleted(into: nil, content: .literal("hello"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(4)),
    ])

    let ciwC = physical("ciw", profile: blindProfile)
    precondition(ciwC.steps == [
        .press(.wordLeft, count: 1),
        .press(.selectWordRight, count: 1),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(nil)),
    ])
    precondition(ciwC.mutatesText)

    // The reported bug, pinned. Replace text off but selection still exact: the
    // SELECT is an AX write (hard settle — a wrong range must abort before the
    // delete), the DELETE is blind (soft settle — its mismatch must NOT abort the
    // insert). Before the fix the delete's hard settle failed in ChatGPT and took
    // setMode(.insert) down with it.
    let ciwNoInsert = physical("ciw", text: "say hello world", caret: 6, profile: noInsertProfile)
    precondition(ciwNoInsert.steps == [
        .setSelection(4..<9),
        .settle(Expectation(selection: 4..<9, length: 15)),
        .settle(Expectation(selection: 4..<9, length: 15, selectedText: "hello")),
        .press(.deleteBack, count: 1),
        .softSettle(deleting(Expectation(selection: 4..<4, length: 10), 4..<9, before: 15)),
        .commit(.deleted(into: nil, content: .literal("hello"), wise: .character)),
        .commit(.setMode(.insert)),
        .commit(.setInsertStart(4)),
    ])
    // The whole point: the plan still reaches insert mode on the blind lane, and
    // the only settle that can abort (the AX select) is the one that's safe to.
    precondition(ciwNoInsert.steps.last == .commit(.setInsertStart(4)))
    precondition(ciwNoInsert.steps.contains(.commit(.setMode(.insert))))
    precondition(!ciwNoInsert.steps.contains(.settle(Expectation(selection: 4..<4, length: 10))),
                 "the blind delete must be a soft settle, never a hard one")

    // `o` opens a line and enters insert on the blind lane too: the typed newline
    // is a soft settle, so a mismatch cannot swallow the mode change.
    let oNoInsert = physical("o", text: "hello", caret: 0, profile: noInsertProfile)
    precondition(oNoInsert.steps.contains(.softSettle(Expectation(selection: 6..<6, length: 6))),
                 "blind open-line must soft-settle the typed newline")
    precondition(oNoInsert.steps.contains(.commit(.setMode(.insert))))

    // Contrast: with insertText the delete is an exact AX write, so it stays a HARD
    // settle — the fix touches only the blind lane.
    let ciwAX = physical("ciw", text: "say hello world", caret: 6, profile: noCursorProfile)
    precondition(ciwAX.steps.contains(.replaceSelection("")))
    precondition(ciwAX.steps.contains(.settle(Expectation(selection: 4..<4, length: 10))))
    precondition(!ciwAX.steps.contains(.softSettle(Expectation(selection: 4..<4, length: 10))),
                 "the AX delete path must remain a hard settle")

    // Blind delete IS the cut: fire-and-forget, the register holds a marker.
    precondition(physical("dd", profile: blindProfile).steps == [
        .press(.lineStart, count: 1),
        .press(.selectDown, count: 1),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .line)),
        .commit(.setCursor(nil)),
    ])

    // Blind yank copies without mutating; an AX selected-text read is
    // preferred when available (real text beats a marker).
    let yyBlind = physical("yy", profile: blindProfile)
    precondition(yyBlind.steps == [
        .press(.lineStart, count: 1),
        .press(.selectDown, count: 1),
        .clipboardCopy,
        .commit(.yanked(into: nil, content: .pasteboard, wise: .line)),
        .press(.left, count: 1),
        .commit(.setCursor(nil)),
    ])
    precondition(!yyBlind.mutatesText)
    // `readSelectedText` must NOT change this lowering. An AX read here is
    // synchronous and would beat the still-queued presses that built the
    // selection, capturing it as it was before them — the register would come
    // back empty or stale. ⌘C rides the same queue as the presses and sees them.
    precondition(physical("yy", profile: CapabilityProfile(available: [.readSelectedText])).steps == [
        .press(.lineStart, count: 1),
        .press(.selectDown, count: 1),
        .clipboardCopy,
        .commit(.yanked(into: nil, content: .pasteboard, wise: .line)),
        .press(.left, count: 1),
        .commit(.setCursor(nil)),
    ])

    // fx moves and commits the find memory; `;` repeats without re-committing.
    precondition(physical("fl", text: "say hello", caret: 0, profile: axProfile).steps == [
        .setSelection(6..<6),
        .settle(Expectation(selection: 6..<6, length: 9)),
        .commit(.found(VimState.FindMemory(character: "l", direction: .forward, beforeCharacter: false))),
        .setSelection(6..<7),
        .commit(.setCursor(6..<7)),
    ])

    // drawCursor off (the Notion quirk): actuation identical, presentation
    // suppressed — the plan ends by clearing the cursor, never drawing it.
    precondition(physical("fl", text: "say hello", caret: 0, profile: noCursorProfile).steps == [
        .setSelection(6..<6),
        .settle(Expectation(selection: 6..<6, length: 9)),
        .commit(.found(VimState.FindMemory(character: "l", direction: .forward, beforeCharacter: false))),
        .commit(.setCursor(nil)),
    ])
    var found = VimState.initial
    found.session.lastFind = VimState.FindMemory(character: "l", direction: .forward, beforeCharacter: false)
    precondition(physical(";", text: "say hello", caret: 0, profile: axProfile, state: found).steps == [
        .setSelection(6..<6),
        .settle(Expectation(selection: 6..<6, length: 9)),
        .setSelection(6..<7),
        .commit(.setCursor(6..<7)),
    ])

    // dw mutates; w does not; undo is a shortcut, not a change.
    precondition(physical("dw", text: "say hello", caret: 0, profile: axProfile).steps == [
        .setSelection(0..<4),
        .settle(Expectation(selection: 0..<4, length: 9)),
        .settle(Expectation(selection: 0..<4, length: 9, selectedText: "say ")),
        .replaceSelection(""),
        .settle(Expectation(selection: 0..<0, length: 5)),
        .commit(.deleted(into: nil, content: .literal("say "), wise: .character)),
        .setSelection(0..<1),
        .commit(.setCursor(0..<1)),
    ])
    precondition(!physical("w", text: "say hello", caret: 0, profile: axProfile).mutatesText)
    precondition(physical("u", text: "say hello", caret: 0, profile: axProfile).steps == [
        .press(.undo, count: 1),
        .commit(.setCursor(nil)),
    ])
    precondition(!physical("u", text: "say hello", caret: 0, profile: axProfile).mutatesText)

    // dd takes the terminator and commits linewise.
    precondition(physical("dd", text: "one\ntwo", caret: 1, profile: axProfile).steps == [
        .setSelection(0..<4),
        .settle(Expectation(selection: 0..<4, length: 7)),
        .settle(Expectation(selection: 0..<4, length: 7, selectedText: "one\n")),
        .replaceSelection(""),
        .settle(Expectation(selection: 0..<0, length: 3)),
        .commit(.deleted(into: nil, content: .literal("one\n"), wise: .line)),
        .setSelection(0..<1),
        .commit(.setCursor(0..<1)),
    ])

    putState.session.registers.unnamed = .content(RegisterContent(text: "XY", wise: .character))
    precondition(physical("p", text: "abc", caret: 1, profile: axProfile, state: putState).steps == [
        .setSelection(2..<2),
        .replaceSelection("XY"),
        .settle(Expectation(selection: 4..<4, length: 5)),
        .setSelection(4..<5),
        .commit(.setCursor(4..<5)),
    ])

    // Pasteboard-marker puts: ⌘V in every lane; the wise picks the chords.
    var markedPut = VimState.initial
    markedPut.session.registers.unnamed = .pasteboard(wise: .line)
    precondition(physical("p", profile: blindProfile, state: markedPut).steps == [
        .press(.down, count: 1),
        .press(.lineStart, count: 1),
        .clipboardInsert(nil),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("P", profile: blindProfile, state: markedPut).steps == [
        .press(.lineStart, count: 1),
        .clipboardInsert(nil),
        .commit(.setCursor(nil)),
    ])
    var markedChar = VimState.initial
    markedChar.session.registers.unnamed = .pasteboard(wise: .character)
    precondition(physical("2p", profile: blindProfile, state: markedChar).steps == [
        .press(.right, count: 1),
        .clipboardInsert(nil),
        .clipboardInsert(nil),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("p", text: "abc", caret: 1, profile: axProfile, state: markedChar).steps == [
        .setSelection(2..<2),
        .clipboardInsert(nil),
        .commit(.setCursor(nil)),
    ])

    // Capability changes feasibility: search and marks reject blind.
    precondition(physical("/lo<CR>", profile: blindProfile).steps == [.bell])
    precondition(physical("ma", profile: blindProfile).steps == [.bell])
    precondition(physical("/lo<CR>", text: "say hello", caret: 0, profile: axProfile).steps == [
        .setSelection(7..<7),
        .settle(Expectation(selection: 7..<7, length: 9)),
        .commit(.searched(VimState.SearchMemory(pattern: "lo", direction: .forward))),
        .setSelection(7..<8),
        .commit(.setCursor(7..<8)),
    ])
}

// MARK: - Block-scoped fields (wholeDocument denied)

let shippedSeeds: [Capability: ConfigChoice] = [.nativeMotions: ConfigChoice(seededOff: true)]
let enclosedField = CapabilityResolver.resolve(probed: axProfile, enclosed: true, config: shippedSeeds, learned: [])

func testBlockScopedFields() {
    // A cross-module string contract: `CapabilityConfig` seeds and stored beliefs name the raw value.
    precondition(Capability.wholeDocument.rawValue == "wholeDocument")
    precondition(Capability.drawCursor.rawValue == "drawCursor")
    // Policy atoms are decided, against a parent mechanism.
    precondition(Capability.wholeDocument.species == .policy)
    precondition(Capability.wholeDocument.parent == .readText)
    precondition(Capability.drawCursor.species == .policy)
    precondition(Capability.drawCursor.parent == .writeSelection)
    precondition(Capability.allCases.filter { $0.species == .mechanism }.allSatisfy { $0.parent == nil })
    // The ungated policy: no mechanism can moot whether a focus change ends a
    // session.
    precondition(Capability.fieldIsSession.rawValue == "fieldIsSession")
    precondition(Capability.fieldIsSession.species == .policy)
    precondition(Capability.fieldIsSession.parent == nil)

    // A field that names a bigger editable field around itself is one block of it, with no seed (LIN-1855).
    precondition(Capability.blockScoped == [.drawCursor, .wholeDocument, .fieldIsSession])

    for capability in Capability.blockScoped {
        precondition(enclosedField.report.entries[capability] == .init(status: .unavailable, source: .probed))
    }
    precondition(enclosedField.report.traceGrid.contains("WS+p IT+p DC-p WD-p FS-p"))
    precondition(physical("j", text: "one", caret: 0, profile: enclosedField.profile).steps == [
        .press(.down, count: 1),
        .commit(.setCursor(nil)),
    ])
    for keys in ["j", "k", "3j", "gg", "G", "l", "w", "x", "ciw", "dd", "dj", "yj", "J"] {
        precondition(physical(keys, text: "say hello world", caret: 6, profile: enclosedField.profile).steps
            == physical(keys, text: "say hello world", caret: 6, profile: blockProfile).steps, "\(keys) plans as blockProfile does")
    }
    precondition(physical("j", text: "one", caret: 0, profile: CapabilityResolver.resolve(probed: axProfile, config: shippedSeeds, learned: []).profile)
        .steps.contains(.setSelection(0..<0)), "without the read the caret is written where it is")
    let enclosedChoices = Dictionary(uniqueKeysWithValues: Capability.blockScoped.map { ($0, ConfigChoice(override: .on)) })
    let userOverPage = CapabilityResolver.resolve(probed: axProfile, enclosed: true, config: enclosedChoices, learned: []).report
    for capability in Capability.blockScoped {
        precondition(userOverPage.entries[capability] == .init(status: .available, source: .user))
    }
    let seededEnclosed = CapabilityResolver.resolve(
        probed: axProfile, enclosed: true, config: [.fieldIsSession: ConfigChoice(seededOff: true)], learned: []
    ).report
    precondition(seededEnclosed.entries[.fieldIsSession] == .init(status: .unavailable, source: .seeded), "a seeded surface reports as it did")
    let parentsOff = CapabilityResolver.resolve(
        probed: axProfile, enclosed: true,
        config: [.readText: ConfigChoice(override: .off), .writeSelection: ConfigChoice(override: .off)], learned: []
    ).report
    precondition(parentsOff.entries[.wholeDocument] == .init(status: .unavailable, source: .user)
        && parentsOff.entries[.drawCursor] == .init(status: .unavailable, source: .user), "a missing parent still answers first")

    // The bug this atom exists for: the model says there is no line below, so
    // the exact lane resolves `j` to the offset it started at and executes a
    // flawless no-op. Denied document scope, `j` reaches the blind chord that
    // crosses blocks natively.
    precondition(physical("j", text: "one", caret: 0, profile: blockProfile).steps == [
        .press(.down, count: 1),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("3j", text: "one", caret: 0, profile: blockProfile).steps == [
        .press(.down, count: 3),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("gg", text: "one", caret: 0, profile: blockProfile).steps == [
        .press(.documentStart, count: 1),
        .commit(.setCursor(nil)),
    ])

    // A blind vertical move must never write a selection. The app's own column
    // memory is the ONLY thing keeping `j` in the same column across blocks, and
    // any AX write between presses would reset it. This has to hold even where
    // the block cursor is permitted: after a blind press the predicted caret is
    // unknown, so `renderCursor` must decline to draw rather than guess.
    let blockDrawProfile = CapabilityProfile(available: [
        .readText, .readLength, .readCaret, .readSelectedText, .writeSelection, .insertText, .drawCursor,
    ])
    for keys in ["j", "k", "3j", "gg", "G"] {
        precondition(!physical(keys, text: "one", caret: 0, profile: blockDrawProfile).steps.contains {
            if case .setSelection = $0 { return true }
            return false
        }, "blind vertical move \(keys) must not write a selection — it would clobber the app's column")
    }
    // …but ONLY while no cursor is drawn. A drawn cursor must still be collapsed
    // before the press — it is a real one-character selection, and ↓ with a
    // selection active moves from its far end, one column off from where the user
    // sees the caret. So correctness wins and the write goes in.
    //
    // That makes `drawCursor` and column stability mutually exclusive in a block
    // editor: permit the cursor and every `j` re-seeds the app's sticky column
    // from the current caret, losing it across a short block. So the page's read
    // turns `drawCursor` off with the other two (LIN-1855), and this pins why.
    let drawnCursorSnapshot = FieldSnapshot(
        capabilities: blockDrawProfile, text: "one", selection: 1..<2, cursor: 1..<2
    )
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("j"), state: .initial),
        snapshot: drawnCursorSnapshot
    ).steps == [
        .setSelection(1..<1),   // the collapse — and the column cost of drawing a cursor
        .press(.down, count: 1),
        .commit(.setCursor(nil)),
    ])

    // The gate is profile-driven, not text-driven: the same single-line text
    // under a whole-document profile keeps the exact lane.
    precondition(physical("j", text: "one\ntwo", caret: 0, profile: axProfile).steps == [
        .setSelection(4..<4),
        .settle(Expectation(selection: 4..<4, length: 7)),
        .setSelection(4..<5),
        .commit(.setCursor(4..<5)),
    ])

    // THE regression guard. `TextModel` classes `\n` as whitespace, so `w`/`b`/`e`
    // technically walk lines — but inside a block they are exact and must keep
    // the exact lane. A predicate keyed on "crosses a line" instead of on intent
    // would demote these and destroy the word motions that work today.
    // noCursorProfile is blockProfile + wholeDocument, so this isolates exactly
    // the one variable.
    for keys in ["w", "b", "e", "ciw", "daw", "fl", "x", "$", "dd", "cc"] {
        precondition(
            physical(keys, text: "say hello world", caret: 6, profile: blockProfile).steps ==
            physical(keys, text: "say hello world", caret: 6, profile: noCursorProfile).steps,
            "block scope must not disturb line-local command \(keys)"
        )
    }

    // No blind spelling ⇒ ring, never a silent wrong jump. `J`'s whitespace rules
    // are the whole point of the function; `/` cannot search a page it cannot
    // read; `gi` carries an absolute offset with no staleness witness, and a
    // wrong-block jump followed by Insert is the worst failure available.
    precondition(physical("J", text: "one", caret: 0, profile: blockProfile).steps == [.bell])
    precondition(physical("/lo<CR>", text: "say hello", caret: 0, profile: blockProfile).steps == [.bell])
    var resumed = VimState.initial
    resumed.field.insertStart = 2
    precondition(physical("gi", text: "one", caret: 0, profile: blockProfile, state: resumed).steps == [.bell])

    // Cross-block operators blind-lower rather than silently acting on the wrong
    // span. The register degrades to a pasteboard marker — the lane-C bargain.
    precondition(physical("dj", text: "one", caret: 0, profile: blockProfile).steps == [
        .press(.lineStart, count: 1),
        .press(.selectDown, count: 2),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .line)),
        .commit(.setCursor(nil)),
    ])
    precondition(physical("3dd", text: "one", caret: 0, profile: blockProfile).steps == [
        .press(.lineStart, count: 1),
        .press(.selectDown, count: 3),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .line)),
        .commit(.setCursor(nil)),
    ])

    // Visual extend goes blind too: the app owns the anchor, so the engine's
    // stored one is deliberately ignored and the selection becomes opaque.
    var blockVisual = VimState.initial
    blockVisual.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: 0))
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("j"), state: blockVisual),
        snapshot: FieldSnapshot(capabilities: blockProfile, text: "one", selection: 0..<1, anchor: 0)
    ).steps == [.press(.selectDown, count: 1)])

    // A drawn cursor is collapsed before the next command acts.
    let cursored = FieldSnapshot(capabilities: axProfile, text: "abc", selection: 0..<1, cursor: 0..<1)
    precondition(PhysicalPlanner.plan(
        LogicalPlanner.plan(RawCommand("x"), state: .initial),
        snapshot: cursored
    ).steps.first == .setSelection(0..<0))
}

// MARK: - The selected-text check

let twoLines = "say hello world\nnext line"
let laneBEdits: [(keys: String, caret: Int, text: [String?])] = [
    ("ciw", 6, ["hello"]), ("diw", 6, ["hello"]), ("x", 6, ["l"]), ("3x", 6, ["llo"]), ("X", 6, ["e"]),
    ("dw", 4, ["hello "]), ("de", 4, ["hello"]), ("cw", 4, ["hello"]), ("D", 4, ["hello world"]),
    ("C", 4, ["hello world"]), ("s", 4, ["h"]), ("S", 4, ["say hello world"]), ("cc", 4, ["say hello world"]),
    ("dd", 4, ["say hello world\n"]), ("rZ", 4, ["h"]), ("3rZ", 4, ["hel"]), ("~", 4, ["h"]),
    ("g~iw", 4, ["hello"]), ("gUiw", 4, ["hello"]), (">>", 4, ["say hello world\n"]),
    ("J", 4, ["say hello world\nnext line"]),
]

func checksText(_ plan: PhysicalPlan) -> Bool {
    plan.steps.contains {
        if case .settle(let expectation) = $0 { return expectation.selectedText != nil }
        return false
    }
}

let readNothingSelected = CapabilityProfile(available: [.readText, .readLength, .readCaret, .wholeDocument])

func testSelectedTextCheck() {
    for edit in laneBEdits {
        for profile in [readProfile, insertOnlyProfile] {
            precondition(checkedTexts(physical(edit.keys, text: twoLines, caret: edit.caret, profile: profile)) == edit.text,
                         "lane B must check the text \(edit.keys) replaces")
        }
    }
    var visualWord = VimState.initial
    visualWord.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: 4))
    for keys in ["d", "x", "c", "s", "~", "u"] {
        let steps = PhysicalPlanner.plan(
            LogicalPlanner.plan(RawCommand(keys), state: visualWord),
            snapshot: FieldSnapshot(capabilities: readProfile, text: twoLines, selection: 4..<9, anchor: 4)
        )
        precondition(checkedTexts(steps) == ["hello"], "Visual \(keys) must check the selection it replaces")
    }

    for edit in laneBEdits {
        for profile in [axProfile, noCursorProfile, noInsertProfile, blockProfile] {
            let plan = physical(edit.keys, text: twoLines, caret: edit.caret, profile: profile)
            precondition(plan == .rejected || checkedTexts(plan) == edit.text, "lane A must check the text \(edit.keys) replaces")
        }
    }

    for edit in laneBEdits {
        precondition(!checksText(physical(edit.keys, text: twoLines, caret: edit.caret, profile: readNothingSelected)))
    }
    precondition(physical("ciw", text: "say hello world", caret: 6, profile: readNothingSelected).traceShape == "P2P5!P?CCC")
    var yankable = VimState.initial
    yankable.session.registers.unnamed = .content(RegisterContent(text: "XY", wise: .character))
    for keys in ["yiw", "yy", "w", "p", "P", "o", "O", "A", "i", "u"] {
        precondition(!checksText(physical(keys, text: twoLines, caret: 6, profile: readProfile, state: yankable)),
                     "\(keys) replaces no selection")
    }

    let checkedCiw = traced("ciw", text: "say hello world", caret: 6, profile: readProfile)
    precondition(checkedCiw.plan.traceShape == "P2P5!!P?CCC")
    precondition(!checkedCiw.abortedAtTextCheck(nil) && !checkedCiw.abortedAtTextCheck(2))
    precondition(checkedCiw.abortedAtTextCheck(3))
}
