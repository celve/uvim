// MARK: - Clipboard routing (fork)

func testClipboardRoute() {
    let slot = CaptureSlot(id: 0)
    let captures: [CaptureSlot: String] = [slot: "captured line\n"]
    func text(_ effect: VimEffect, _ mode: ClipboardMode) -> String? {
        ClipboardRoute.text(for: effect, captures: captures, mode: mode)
    }
    let yank = VimEffect.yanked(into: nil, content: .literal("word"), wise: .character)
    let delete = VimEffect.deleted(into: nil, content: .captured(slot), wise: .line)

    precondition(text(yank, .off) == nil, "off: an unnamed yank stays in uvim")
    precondition(text(delete, .off) == nil)
    precondition(text(yank, .yank) == "word", "yank: an unnamed yank reaches the clipboard")
    precondition(text(delete, .yank) == nil, "yank: a delete stays in uvim")
    precondition(text(yank, .unnamed) == "word")
    precondition(text(delete, .unnamed) == "captured line\n", "unnamed: a delete reaches it, newline and all")

    for name: Character in ["+", "*"] {
        let named = VimEffect.yanked(into: Register(name), content: .literal("plus"), wise: .character)
        precondition(text(named, .off) == "plus", "\"\(name)y writes the clipboard whatever the mode")
        let cut = VimEffect.deleted(into: Register(name), content: .literal("cut"), wise: .character)
        precondition(text(cut, .off) == "cut")
    }
    for name: Character in ["a", "A", "0", "_"] {
        let named = VimEffect.yanked(into: Register(name), content: .literal("x"), wise: .character)
        precondition(text(named, .unnamed) == nil, "\"\(name) never reaches the clipboard")
    }

    let blind = VimEffect.yanked(into: nil, content: .pasteboard, wise: .character)
    precondition(text(blind, .unnamed) == nil, "a blind ⌘C already put it there")
    let missing = VimEffect.deleted(into: nil, content: .captured(CaptureSlot(id: 9)), wise: .character)
    precondition(text(missing, .unnamed) == nil, "an empty capture writes nothing")
    precondition(text(.setCursor(nil), .unnamed) == nil)

    let held = RegisterSlot.content(RegisterContent(text: "mine", wise: .character))
    precondition(ClipboardRoute.adoptsExternal(mode: .yank, unnamed: held))
    precondition(ClipboardRoute.adoptsExternal(mode: .unnamed, unnamed: nil))
    precondition(!ClipboardRoute.adoptsExternal(mode: .off, unnamed: held), "off: p keeps uvim's register")
    precondition(!ClipboardRoute.adoptsExternal(mode: .yank, unnamed: .pasteboard(wise: .line)),
                 "a marker already puts the clipboard, with the wise its cut gave it")
    precondition(ClipboardRoute.wise(ofExternal: "a line\n") == .line)
    precondition(ClipboardRoute.wise(ofExternal: "words") == .character)

    // The adopted copy flows through the reducer as a marker, so `p` pastes the clipboard.
    var state = VimState.initial
    state = VimReducer.reduce(state, yank)
    state = VimReducer.reduce(state, .yanked(into: nil, content: .pasteboard, wise: .line))
    precondition(state.session.registers.unnamed == .pasteboard(wise: .line))
    precondition(state.session.registers.numbered[0] == RegisterContent(text: "word", wise: .character),
                 "adopting a copy leaves \"0 alone")
    let put = plan("p", state: state)
    guard case .put(.pasteboard(let wise), _, _)? = put.steps.first, wise == .line else {
        preconditionFailure("p puts the clipboard linewise: \(put)")
    }
}
