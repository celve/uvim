// MARK: - Sim goldens: (text, caret, keys) → (text′, caret′, state′)

var sim = Sim(text: "say hello world", caret: 6, profile: axProfile)

/// Types `change`, ends it with ⌃[, then types `then`.
func replayed(_ text: String, caret: Int = 0, _ change: String, then keys: String) -> Sim {
    var replay = Sim(text: text, caret: caret, profile: axProfile)
    replay.type(change)
    replay.feed("<C-[>")
    replay.type(keys)
    precondition(replay.settleFailures == 0 && replay.bells == 0 && replay.unsupportedSteps == 0)
    return replay
}

func testSimGoldens() {
    sim.type("x")
    precondition(sim.text == "say helo world")
    precondition(sim.caret == 6)
    precondition(sim.selection == 6..<7)                       // the block cursor, on 'o'
    precondition(sim.state.field.cursor == 6..<7)
    precondition(sim.state.session.register("-") == .content(RegisterContent(text: "l", wise: .character)))

    sim = Sim(text: "abcdef", caret: 0, profile: axProfile)
    sim.type("3x")
    precondition(sim.text == "def")
    precondition(sim.state.session.register("\"") == .content(RegisterContent(text: "abc", wise: .character)))

    sim = Sim(text: "say hello", caret: 0, profile: axProfile)
    sim.type("dw")
    precondition(sim.text == "hello")
    precondition(sim.state.session.register("-") == .content(RegisterContent(text: "say ", wise: .character)))

    sim = Sim(text: "a\nb\nc", caret: 0, profile: axProfile)
    sim.type("dddd")
    precondition(sim.text == "c")
    precondition(sim.state.session.register("1") == .content(RegisterContent(text: "b\n", wise: .line)))
    precondition(sim.state.session.register("2") == .content(RegisterContent(text: "a\n", wise: .line)))

    sim = Sim(text: "one\ntwo", caret: 0, profile: axProfile)
    sim.type("yyp")
    precondition(sim.text == "one\none\ntwo")
    precondition(sim.state.session.register("0") == .content(RegisterContent(text: "one\n", wise: .line)))

    // The flagship: change-inner-word, type, escape — full loop.
    sim = Sim(text: "say hello world", caret: 6, profile: axProfile)
    sim.type("ciwbye")
    sim.feed("<Esc>")
    precondition(sim.text == "say bye world")
    precondition(sim.caret == 6)
    precondition(sim.state.field.cursor == 6..<7)              // redrawn on insert exit
    precondition(sim.state.field.mode == .normal)
    precondition(sim.state.session.lastInsert == "bye")
    precondition(sim.state.session.register(".") == .content(RegisterContent(text: "bye", wise: .character)))
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "bye"))
    precondition(sim.settleFailures == 0 && sim.bells == 0 && sim.unsupportedSteps == 0)

    // Insert entry via A opens a dot body even though entry itself mutated nothing.
    sim = Sim(text: "hi", caret: 0, profile: axProfile)
    sim.type("A!")
    sim.feed("<Esc>")
    precondition(sim.text == "hi!")
    precondition(sim.caret == 2)
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "A", insert: "!"))

    // Dot replays the last change and must not overwrite it.
    sim = Sim(text: "aabb", caret: 0, profile: axProfile)
    sim.type("x.")
    precondition(sim.text == "bb")
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "x"))

    sim = Sim(text: "say hello world", caret: 6, profile: axProfile)
    sim.type("ciwbye")
    sim.feed("<Esc>")
    sim.type("w.")
    precondition(sim.text == "say bye bye")
    precondition(sim.selection == 10..<11)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "bye"))
    precondition(sim.settleFailures == 0 && sim.bells == 0 && sim.unsupportedSteps == 0)

    var esc = Sim(text: "say hello world", caret: 4, profile: axProfile)
    esc.type("vl")
    esc.feed("<Esc>")
    precondition(esc.state.field.mode == .normal && esc.selection == 5..<6)
    esc.type("d")
    esc.feed("<Esc>")
    esc.type("x")
    precondition(esc.text == "say hllo world")
    esc.feed("<Esc>")
    precondition(esc.text == "say hllo world" && esc.selection == 5..<6 && esc.state.field.mode == .normal)
    precondition(esc.settleFailures == 0 && esc.bells == 0 && esc.unsupportedSteps == 0)

    precondition(replayed("one two three", "cwX", then: "w.").text == "X X three")
    precondition(replayed("a\nb", "ccX", then: "j.").text == "X\nX")
    precondition(replayed("abc", "sX", then: "l.").text == "XXc")
    precondition(replayed("one\ntwo", "A!", then: "j.").text == "one!\ntwo!")
    let reopened = replayed("a", "ofoo", then: ".")
    precondition(reopened.text == "a\nfoo\nfoo")
    precondition(reopened.selection == 8..<9)

    var typo = Sim(text: "say hello world", caret: 6, profile: axProfile)
    typo.type("ciwhelo")
    typo.feed("<BS>")
    typo.type("lo")
    typo.feed("<C-[>")
    precondition(typo.text == "say hello world")
    precondition(typo.state.session.lastInsert == "hello")
    typo.type("w.")
    precondition(typo.text == "say hello hello")
    var lines = Sim(text: "a", profile: axProfile)
    lines.type("otwo")
    lines.feed("<CR>")
    lines.type("three")
    lines.feed("<C-[>")
    lines.type(".")
    precondition(lines.text == "a\ntwo\nthree\ntwo\nthree")
    precondition(lines.state.session.lastChange == VimState.ChangeMemory(body: "o", insert: "two\nthree"))

    var lost = Sim(text: "say hello world", caret: 6, profile: axProfile)
    lost.type("ciwfoo")
    lost.feed("<Left>")
    lost.type("bar")
    lost.feed("<C-[>")
    precondition(lost.state.session.lastChange == .unreplayable)
    let beforeDot = lost.text
    lost.type("w.")
    precondition(lost.text == beforeDot)
    precondition(lost.bells == 1)

    // An empty session closes its body: `ciw` records, `i` does not, nothing strands.
    var empty = Sim(text: "say hello world", caret: 6, profile: axProfile)
    empty.type("ciw")
    empty.feed("<C-[>")
    precondition(empty.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: ""))
    empty.type("w.")
    precondition(empty.text == "say  ")
    empty.type("A!")
    empty.feed("<C-[>")
    precondition(empty.state.session.lastChange == VimState.ChangeMemory(body: "A", insert: "!"))
    empty.type("i")
    empty.feed("<C-[>")
    precondition(empty.state.session.lastChange == VimState.ChangeMemory(body: "A", insert: "!"))
    precondition(empty.state.session.lastInsert == "!")
    precondition(replayed("a", "o", then: ".").text == "a\n\n")

    // Visual changes ring on `.` instead of replaying as Normal `s`, or `u` (undo).
    var visualChange = Sim(text: "say hello world", caret: 4, profile: axProfile)
    visualChange.type("viwsbye")
    visualChange.feed("<C-[>")
    precondition(visualChange.text == "say bye world")
    precondition(visualChange.state.session.lastChange == .unreplayable)
    visualChange.type("w.")
    precondition(visualChange.text == "say bye world")
    precondition(visualChange.bells == 1)
    var visualCase = Sim(text: "AAA BBB", caret: 0, profile: axProfile)
    visualCase.type("viwu")
    precondition(visualCase.text == "aaa BBB")
    visualCase.type("w.")
    precondition(visualCase.text == "aaa BBB")
    precondition(visualCase.bells == 1 && visualCase.unsupportedSteps == 0)

    var refused = replayed("say hello world", caret: 6, "ciwbye", then: "w")
    refused.swallowsReplace = true
    refused.type(".")
    precondition(refused.settleFailures == 1)
    precondition(refused.text == "say bye world")
    precondition(refused.state.field.mode == .normal)
    precondition(refused.selection.isEmpty)

    var dotState = VimState.initial
    dotState.session.lastChange = VimState.ChangeMemory(body: "ciw", insert: "bye")
    let dotB = physical(".", text: "say hello world", caret: 6, profile: readProfile, state: dotState)
    precondition(dotB.traceShape == "P2P5!!P?CCCT?P!CC")
    precondition(dotB.steps.contains(.typeText("bye")))
    let dotC = physical(".", profile: blindProfile, state: dotState)
    precondition(dotC.traceShape == "PPXCCCTPCC")
    precondition(dotC.steps.contains(.typeText("bye")))

    // Find commits its memory; `;` repeats from it.
    sim = Sim(text: "abcabc", caret: 0, profile: axProfile)
    sim.type("fc;")
    precondition(sim.caret == 5)
    precondition(sim.state.session.lastFind ==
        VimState.FindMemory(character: "c", direction: .forward, beforeCharacter: false))
    precondition(sim.settleFailures == 0 && sim.bells == 0)

    // Block cursor: drawn after commands, walks with the caret, and collapses
    // on insert entry so typing inserts instead of overwriting.
    sim = Sim(text: "abc", caret: 0, profile: axProfile)
    sim.type("l")
    precondition(sim.selection == 1..<2)                       // block on 'b'
    precondition(sim.state.field.cursor == 1..<2)
    sim.type("iZ")
    sim.feed("<Esc>")
    precondition(sim.text == "aZbc")                           // inserted, not overwritten
    precondition(sim.state.field.cursor == 1..<2)              // redrawn after Esc
    precondition(sim.settleFailures == 0 && sim.bells == 0)

    // At end of line the cursor has nothing to cover: bare caret.
    sim = Sim(text: "hi", caret: 0, profile: axProfile)
    sim.type("$")
    precondition(sim.selection == 2..<2)
    precondition(sim.state.field.cursor == nil)

    // drawCursor suppressed (the Notion shape): identical edits and exact
    // offsets, but no standing selection — the caret stays bare after every
    // command.
    sim = Sim(text: "say hello world", caret: 6, profile: noCursorProfile)
    sim.type("ciwbye")
    sim.feed("<Esc>")
    precondition(sim.text == "say bye world")
    precondition(sim.caret == 6)
    precondition(sim.selection == 6..<6)                       // bare caret, no block
    precondition(sim.state.field.cursor == nil)
    precondition(sim.settleFailures == 0 && sim.bells == 0 && sim.unsupportedSteps == 0)

    // A field that accepts the AX write and does nothing — measured in Linear.
    sim = Sim(text: "say hello world", caret: 6, profile: axProfile)
    sim.swallowsReplace = true
    sim.type("ciw")
    precondition(sim.text == "say hello world")            // nothing was deleted
    precondition(sim.settleFailures == 1)
    precondition(sim.state.field.mode == .insert)
    precondition(sim.state.field.insertStart == nil)       // the paired commit died with the plan
    precondition(sim.state.session.register("-") == nil)   // and no register claims the delete
    precondition(sim.selection == 4..<9)                   // the word is still the operand
    sim.type("bye")
    sim.feed("<Esc>")
    precondition(sim.text == "say bye world")              // the app's own editor finished it
    precondition(sim.caret == 6)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.state.session.lastInsert == "bye")
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "bye"))

    // An aborted plan that stayed in Normal mutated nothing, so `.` must not learn it.
    sim = Sim(text: "say hello", caret: 0, profile: axProfile)
    sim.swallowsReplace = true
    sim.type("dw")
    precondition(sim.text == "say hello")
    precondition(sim.state.session.lastChange == nil)

    // Esc's nudge can fail too, and the drained payload has no second chance.
    sim = Sim(text: "hi", caret: 0, profile: axProfile)
    sim.type("iZ")
    precondition(sim.state.field.mode == .insert)
    sim.swallowsSelect = true
    sim.feed("<Esc>")
    precondition(sim.settleFailures == 1)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.state.session.lastInsert == "Z")
    precondition(sim.state.session.lastChange == VimState.ChangeMemory(body: "i", insert: "Z"))

    // Visual `c` has no settle to verify its selection; the planner names it.
    sim = Sim(text: "say hello world", caret: 4, profile: axProfile)
    sim.swallowsReplace = true
    sim.type("viw")
    precondition(sim.selection == 4..<9)
    sim.type("c")
    precondition(sim.state.field.mode == .insert)
    precondition(sim.selection == 4..<9)                   // kept, not collapsed
    sim.type("bye")
    sim.feed("<Esc>")
    precondition(sim.text == "say bye world")

    // The other half: Visual `d` ends in Normal, so nobody types over it.
    sim = Sim(text: "say hello world", caret: 4, profile: axProfile)
    sim.swallowsReplace = true
    sim.type("viwd")
    precondition(sim.text == "say hello world")            // nothing deleted
    precondition(sim.state.field.mode == .normal)          // and Visual is left regardless
    precondition(sim.selection.isEmpty)                    // the stranded selection is collapsed
    precondition(sim.state.session.register("\"") == nil)

    // A swallowed *replace* leaves a bare caret, so entering Insert is safe.
    sim = Sim(text: "say hello world", caret: 4, profile: axProfile)
    sim.swallowsReplace = true
    sim.type("o")
    precondition(sim.state.field.mode == .insert)
    precondition(sim.selection.isEmpty)

    // A swallowed *select* strands a range no write of ours can collapse.
    sim = Sim(text: "say hello world", caret: 4, profile: axProfile)
    sim.perform([.setSelection(4..<9)])
    sim.swallowsSelect = true
    sim.type("o")
    precondition(sim.settleFailures == 1)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.selection == 4..<9)
    precondition(sim.text == "say hello world")
    sim = Sim(text: "say hello world", caret: 4, profile: nativeAX)
    sim.perform([.setSelection(4..<9)])
    sim.swallowsSelect = true
    sim.type("o")
    precondition(sim.state.field.mode == .normal && sim.selection == 4..<9, "a field that takes writes is not repaired by ←")

    // Answering no selection at all: residency must not ride on a failed read.
    sim = Sim(text: "say hello world", caret: 6, profile: axProfile)
    sim.unreadableSelection = true
    sim.type("ciw")
    precondition(sim.settleFailures == 1)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.text == "say hello world")

    // Standing down never revives Visual, whose anchor names an unreadable selection.
    sim = Sim(text: "say hello world", caret: 4, profile: axProfile)
    sim.type("viw")
    precondition(sim.selection == 4..<9)
    sim.swallowsReplace = true
    sim.unreadableSelection = true
    sim.type("c")
    precondition(sim.settleFailures == 1)
    precondition(sim.state.field.mode == .normal)
    precondition(sim.text == "say hello world")

    var unreadCaret = Sim(text: "say hello world", caret: 6, profile: CapabilityProfile(available: [
        .readText, .readLength, .readSelectedText, .writeSelection, .insertText, .wholeDocument,
    ]))
    unreadCaret.type("dd")
    precondition(unreadCaret.text == "say hello world" && unreadCaret.unsupportedSteps == 1, "a caret the field cannot read goes blind")

    // The pasteboard IS the register (clipboard=unnamed): cut writes it, a
    // marker commit remembers only the wise, and a nil insert pastes it back.
    // Step-level: blind plans carry .press moves the Sim can't emulate.
    sim = Sim(text: "one two", caret: 0, profile: blindProfile)
    precondition(sim.perform([
        .setSelection(0..<3),
        .clipboardCut,
        .commit(.deleted(into: nil, content: .pasteboard, wise: .character)),
        .clipboardInsert(nil),
    ]))
    precondition(sim.pasteboard == "one")
    precondition(sim.text == "one two")                        // cut, then pasted back
    precondition(sim.caret == 3)
    precondition(sim.state.session.register("\"") == .pasteboard(wise: .character))

    // A copy overwrites the modeled pasteboard without mutating the field.
    precondition(sim.perform([.setSelection(4..<7), .clipboardCopy]))
    precondition(sim.pasteboard == "two")
    precondition(sim.text == "one two")
}
