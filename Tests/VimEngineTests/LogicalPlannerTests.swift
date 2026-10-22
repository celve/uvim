// MARK: - LogicalPlanner

// Insert mode: only Esc concerns the engine.
var inserting = VimState.initial

func testLogicalPlanner() {
    // ciw: select the word, delete it, enter Insert.
    precondition(plan("ciw").steps == [
        .select(.textObject(TextObject(scope: .inner, kind: .word(bigWord: false)), count: 1)),
        .deleteSelection(into: nil),
        .setMode(.insert)
    ])

    // dd takes whole lines; cc keeps the line it empties.
    precondition(plan("dd").steps == [
        .select(.lines(count: 1, extent: .removed)),
        .deleteSelection(into: nil),
        .renderCursor
    ])
    precondition(plan("cc").steps == [
        .select(.lines(count: 1, extent: .interior)),
        .deleteSelection(into: nil),
        .setMode(.insert)
    ])

    // Counts multiply across operator and target; registers ride through.
    precondition(plan("\"a2d3w").steps == [
        .select(.span(to: .motion(.word(.forward, end: false, bigWord: false), count: 6), inclusive: false)),
        .deleteSelection(into: Register("a")),
        .renderCursor
    ])

    // Motion lore: dw exclusive, de inclusive, dj linewise, cw rewrites to ce.
    precondition(plan("de").steps.first ==
        .select(.span(to: .motion(.word(.forward, end: true, bigWord: false), count: 1), inclusive: true)))
    precondition(plan("dj").steps.first ==
        .select(.lineSpan(to: .motion(.line(.down, firstNonBlank: false), count: 1), extent: .removed)))
    precondition(plan("cw").steps.first ==
        .select(.span(to: .motion(.word(.forward, end: true, bigWord: false), count: 1), inclusive: true)))

    // Edits and insert entries decompose into primitives.
    precondition(plan("3x").steps == [
        .select(.span(to: .motion(.character(.right), count: 3), inclusive: false)),
        .deleteSelection(into: nil),
        .renderCursor
    ])
    precondition(plan("A").steps == [.moveCaret(.motion(.lineEnd, count: 1)), .setMode(.insert)])
    precondition(plan("o").steps == [
        .moveCaret(.motion(.lineEnd, count: 1)),
        .insertText("\n"),
        .setMode(.insert)
    ])
    precondition(plan("d").steps.isEmpty)   // incomplete: interceptor keeps buffering

    // State resolution: memory-dependent commands resolve or ring.
    precondition(plan("n").steps == [.bell(.noPriorSearch)])
    var planning = VimState.initial
    planning.session.lastSearch = VimState.SearchMemory(pattern: "needle", direction: .backward)
    precondition(plan("n", state: planning).steps == [
        .moveCaret(.motion(.search(Search(direction: .backward, pattern: "needle", isSubmitted: true)), count: 1)),
        .renderCursor
    ])
    precondition(plan(";").steps == [.bell(.noPriorFind)])
    planning.session.lastFind = VimState.FindMemory(character: "x", direction: .forward, beforeCharacter: false)
    precondition(plan(",", state: planning).steps == [
        .moveCaret(.motion(.find(character: "x", direction: .backward, beforeCharacter: false), count: 1)),
        .renderCursor
    ])
    precondition(plan("'m").steps == [.bell(.unsetMark("m"))])

    // Put resolves register content at plan time.
    precondition(plan("p").steps == [.bell(.emptyRegister("\""))])
    planning.session.registers.unnamed = .content(RegisterContent(text: "howdy", wise: .character))
    precondition(plan("p", state: planning).steps == [
        .put(.content(RegisterContent(text: "howdy", wise: .character)), PutAction(position: .after), count: 1),
        .renderCursor
    ])

    // A pasteboard marker puts via ⌘V; its wise rides the logical step.
    var markedPlanning = VimState.initial
    markedPlanning.session.registers.unnamed = .pasteboard(wise: .line)
    precondition(plan("p", state: markedPlanning).steps == [
        .put(.pasteboard(wise: .line), PutAction(position: .after), count: 1),
        .renderCursor
    ])
    precondition(plan("\"+p", state: markedPlanning).steps == [
        .put(.pasteboard(wise: .character), PutAction(position: .after), count: 1),
        .renderCursor
    ])

    // Dot recompiles the stored change; its count overrides wholesale.
    precondition(plan(".").steps == [.bell(.noPriorChange)])
    planning.session.lastChange = VimState.ChangeMemory(body: "x", count: 2)
    precondition(plan(".", state: planning).steps == [
        .select(.span(to: .motion(.character(.right), count: 2), inclusive: false)),
        .deleteSelection(into: nil),
        .renderCursor
    ])
    precondition(plan("3.", state: planning).steps.first ==
        .select(.span(to: .motion(.character(.right), count: 3), inclusive: false)))

    var dotted = VimState.initial
    dotted.session.lastChange = VimState.ChangeMemory(body: "ciw", insert: "bye")
    precondition(plan(".", state: dotted).steps == [
        .select(.textObject(TextObject(scope: .inner, kind: .word(bigWord: false)), count: 1)),
        .deleteSelection(into: nil),
        .setMode(.insert),
        .insertText("bye"),
        .moveCaret(.motion(.character(.left), count: 1)),
        .setMode(.normal),
        .renderCursor
    ])
    precondition(plan("3.", state: dotted).steps.first ==
        .select(.textObject(TextObject(scope: .inner, kind: .word(bigWord: false)), count: 3)))
    precondition(plan(".", state: dotted).steps.filter { $0 == .insertText("bye") }.count == 1)

    dotted.session.lastChange = VimState.ChangeMemory(body: "o", insert: "")
    precondition(plan(".", state: dotted).steps == [
        .moveCaret(.motion(.lineEnd, count: 1)),
        .insertText("\n"),
        .setMode(.insert),
        .moveCaret(.motion(.character(.left), count: 1)),
        .setMode(.normal),
        .renderCursor
    ])

    // A replay that rings types nothing.
    dotted.session.lastChange = VimState.ChangeMemory(body: "c;", insert: "bye")
    precondition(plan(".", state: dotted).steps == [.bell(.noPriorFind)])

    dotted.session.lastChange = .unreplayable
    precondition(plan(".", state: dotted).steps == [.bell(.unsupported("."))])

    // Visual mode: motions extend, bare operators act on the selection,
    // text objects keep their spelling, Esc collapses to the head.
    var visual = VimState.initial
    visual.field.mode = .visual(VimState.VisualContext(kind: .character, anchor: 0))
    precondition(plan("w", state: visual).steps == [
        .extendSelection(.motion(.word(.forward, end: false, bigWord: false), count: 1))
    ])
    precondition(plan("d", state: visual).steps == [.deleteSelection(into: nil), .setMode(.normal), .renderCursor])
    precondition(plan("iw", state: visual).steps == [
        .select(.textObject(TextObject(scope: .inner, kind: .word(bigWord: false)), count: 1))
    ])
    precondition(plan("<Esc>", state: visual).steps == [.collapseSelection(.head), .setMode(.normal), .renderCursor])

    inserting.field.mode = .insert
    precondition(plan("<Esc>", state: inserting).steps == [
        .moveCaret(.motion(.character(.left), count: 1)),
        .setMode(.normal),
        .renderCursor
    ])
    precondition(plan("w", state: inserting).steps.isEmpty)

    // Unsupported commands ring with their keys.
    precondition(plan("zt").steps == [.bell(.unsupported("zt"))])

    // Typed find commands commit memory; repeats never do.
    precondition(plan("fx").steps == [
        .moveCaret(.motion(.find(character: "x", direction: .forward, beforeCharacter: false), count: 1)),
        .commit(.found(VimState.FindMemory(character: "x", direction: .forward, beforeCharacter: false))),
        .renderCursor
    ])
}

// MARK: - TextModel

func testTextModel() {
    let sample = TextModel("say hello world")
    precondition(sample.wordForward(from: 0, big: false) == 4)
    precondition(sample.wordEnd(from: 4, big: false) == 8)
    precondition(sample.wordObject(at: 6, around: false, big: false) == 4..<9)
    precondition(sample.wordObject(at: 6, around: true, big: false) == 4..<10)
    precondition(sample.findCharacter("w", from: 0, forward: true, before: false, count: 1) == 10)
    precondition(TextModel("one\ntwo").verticalMove(from: 1, by: 1, firstNonBlank: false) == 5)
    precondition(TextModel("one\ntwo").lines(from: 1, count: 1, extent: .whole) == 0..<4)
}
