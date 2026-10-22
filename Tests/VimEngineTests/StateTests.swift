// MARK: - VimState

func testVimState() {
    var state = VimState.initial
    precondition(state.field.mode == .normal)
    precondition(state.session.register("\"") == nil)
    precondition(state.session.register("a") == nil)

    state.session.registers.named["a"] = RegisterContent(text: "hello", wise: .character)
    precondition(state.session.register("a") == .content(RegisterContent(text: "hello", wise: .character)))
    precondition(state.session.register("A") == .content(RegisterContent(text: "hello", wise: .character)))

    state.session.registers.numbered[1] = RegisterContent(text: "line\n", wise: .line)
    precondition(state.session.register("1") == .content(RegisterContent(text: "line\n", wise: .line)))
    precondition(state.session.register("2") == nil)

    state.session.lastSearch = VimState.SearchMemory(pattern: "needle", direction: .forward)
    precondition(state.session.register("/") == .content(RegisterContent(text: "needle", wise: .character)))

    state.session.lastInsert = "typed"
    precondition(state.session.register(".") == .content(RegisterContent(text: "typed", wise: .character)))
    precondition(state.session.register("_") == nil)
    precondition(state.session.register("+") == nil)

    state.field.mode = .visual(VimState.VisualContext(kind: .line, anchor: 4))
    if case .visual(let context) = state.field.mode {
        precondition(context.kind == .line)
        precondition(context.anchor == 4)
    } else {
        preconditionFailure("expected visual mode")
    }

    // Focus moved: field state resets, session memory survives.
    state.field = VimState.Field()
    precondition(state.field.mode == .normal)
    precondition(state.session.register("a") != nil)
}

// MARK: - VimEffect

func testVimEffect() {
    // Residency is the user's; every other effect claims something about the field.
    precondition(VimEffect.setMode(.normal).survivesAbort)
    precondition(VimEffect.setMode(.insert).survivesAbort)
    precondition(VimEffect.setMode(.replace).survivesAbort)
    precondition(!VimEffect.setMode(.visual(VimState.VisualContext(kind: .character, anchor: 0))).survivesAbort)
    precondition(!VimEffect.setInsertStart(4).survivesAbort)
    precondition(!VimEffect.setCursor(3..<4).survivesAbort)
    precondition(!VimEffect.setMark("a", MarkPoint(offset: 1, textLength: 5, context: "abc")).survivesAbort)
    precondition(!VimEffect.deleted(into: nil, content: .literal("x"), wise: .character).survivesAbort)
    precondition(!VimEffect.yanked(into: nil, content: .literal("x"), wise: .character).survivesAbort)
    precondition(!VimEffect.searched(VimState.SearchMemory(pattern: "x", direction: .right)).survivesAbort)
    precondition(!VimEffect.found(VimState.FindMemory(character: "x", direction: .right, beforeCharacter: false)).survivesAbort)
    precondition(!VimEffect.setLastInsert("x").survivesAbort)
    precondition(!VimEffect.setLastChange(VimState.ChangeMemory(body: "x")).survivesAbort)
    precondition(!VimEffect.setLastVisual(VisualMemory(kind: .character, range: 0..<1)).survivesAbort)
}

// MARK: - VimReducer

func testVimReducer() {
    var reduced = VimState.initial
    reduced = VimReducer.reduce(reduced, .yanked(into: nil, content: .literal("one\n"), wise: .line))
    precondition(reduced.session.register("\"") == .content(RegisterContent(text: "one\n", wise: .line)))
    precondition(reduced.session.register("0") == .content(RegisterContent(text: "one\n", wise: .line)))

    // Linewise deletes shift the ring; the yank slot is untouched.
    reduced = VimReducer.reduce(reduced, .deleted(into: nil, content: .literal("a\n"), wise: .line))
    reduced = VimReducer.reduce(reduced, .deleted(into: nil, content: .literal("b\n"), wise: .line))
    precondition(reduced.session.register("1") == .content(RegisterContent(text: "b\n", wise: .line)))
    precondition(reduced.session.register("2") == .content(RegisterContent(text: "a\n", wise: .line)))
    precondition(reduced.session.register("0") == .content(RegisterContent(text: "one\n", wise: .line)))

    // Sub-line deletes go to the small-delete register, not the ring.
    reduced = VimReducer.reduce(reduced, .deleted(into: nil, content: .literal("ch"), wise: .character))
    precondition(reduced.session.register("-") == .content(RegisterContent(text: "ch", wise: .character)))
    precondition(reduced.session.register("1") == .content(RegisterContent(text: "b\n", wise: .line)))

    // Named writes mirror to unnamed; uppercase appends; the black hole swallows.
    reduced = VimReducer.reduce(reduced, .yanked(into: Register("a"), content: .literal("hi"), wise: .character))
    reduced = VimReducer.reduce(reduced, .yanked(into: Register("A"), content: .literal("!"), wise: .character))
    precondition(reduced.session.register("a") == .content(RegisterContent(text: "hi!", wise: .character)))
    precondition(reduced.session.register("\"") == .content(RegisterContent(text: "hi!", wise: .character)))
    reduced = VimReducer.reduce(reduced, .deleted(into: Register("_"), content: .literal("gone"), wise: .character))
    precondition(reduced.session.register("\"") == .content(RegisterContent(text: "hi!", wise: .character)))

    // An unfilled capture skips the write rather than inventing content.
    reduced = VimReducer.reduce(reduced, .deleted(into: nil, content: .captured(CaptureSlot(id: 9)), wise: .character))
    precondition(reduced.session.register("\"") == .content(RegisterContent(text: "hi!", wise: .character)))

    // Pasteboard markers route to unnamed ONLY — ring, 0, -, named untouched;
    // the register name is ignored; uppercase append skips; real content
    // overwrites a marker (fresher).
    reduced = VimReducer.reduce(reduced, .deleted(into: nil, content: .pasteboard, wise: .line))
    precondition(reduced.session.register("\"") == .pasteboard(wise: .line))
    precondition(reduced.session.register("1") == .content(RegisterContent(text: "b\n", wise: .line)))
    precondition(reduced.session.register("0") == .content(RegisterContent(text: "one\n", wise: .line)))
    precondition(reduced.session.register("-") == .content(RegisterContent(text: "ch", wise: .character)))
    reduced = VimReducer.reduce(reduced, .deleted(into: Register("a"), content: .pasteboard, wise: .character))
    precondition(reduced.session.register("a") == .content(RegisterContent(text: "hi!", wise: .character)))
    precondition(reduced.session.register("\"") == .pasteboard(wise: .character))
    reduced = VimReducer.reduce(reduced, .yanked(into: Register("A"), content: .pasteboard, wise: .line))
    precondition(reduced.session.register("a") == .content(RegisterContent(text: "hi!", wise: .character)))
    reduced = VimReducer.reduce(reduced, .deleted(into: Register("_"), content: .pasteboard, wise: .character))
    precondition(reduced.session.register("\"") == .pasteboard(wise: .line))   // blackhole swallowed the marker too
    reduced = VimReducer.reduce(reduced, .yanked(into: nil, content: .literal("fresh"), wise: .character))
    precondition(reduced.session.register("\"") == .content(RegisterContent(text: "fresh", wise: .character)))

    // Cursor state: set by renderCursor's commit, cleared on leaving Normal.
    reduced = VimReducer.reduce(reduced, .setCursor(3..<4))
    precondition(reduced.field.cursor == 3..<4)
    reduced = VimReducer.reduce(reduced, .setMode(.insert))
    precondition(reduced.field.cursor == nil)

    // Only opening a session forgets where the last one began.
    reduced = VimReducer.reduce(reduced, .setInsertStart(7))
    precondition(reduced.field.insertStart == 7)
    reduced = VimReducer.reduce(reduced, .setMode(.normal))
    precondition(reduced.field.insertStart == 7)   // `gi` still needs it after Insert ends
    reduced = VimReducer.reduce(reduced, .setMode(.visual(VimState.VisualContext(kind: .character, anchor: 2))))
    precondition(reduced.field.insertStart == 7)   // and across a Visual excursion
    reduced = VimReducer.reduce(reduced, .setMode(.insert))
    precondition(reduced.field.insertStart == nil)
}
