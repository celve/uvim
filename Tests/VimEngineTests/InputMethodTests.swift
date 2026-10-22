// MARK: - Input methods (LIN-2053)

var listReads = 0
func answered(_ marked: Composition.Marked, _ method: String = "com.apple.inputmethod.SCIM.Shuangpin", list: Bool?) -> Composition {
    Composition.answer(marked: marked, method: method) { listReads += 1; return list }
}

/// A key's fate as `Controller.handle` decides it: "app" when the app gets it; nil `answer` is no input method selected.
func imeOutcome(
    _ keyCode: Int, _ chord: KeyNotation.Chord, _ characters: String, escapeEngages: Bool, mode: RawMonitor.Mode,
    answer: Composition?, afterCommit: Composition, commits: inout Int
) -> String {
    guard let token = KeyNotation.token(keyCode: keyCode, chord: chord, characters: characters, escapeEngages: escapeEngages)
    else { return "app" }
    if mode == .insert {
        guard let answer else { return "normal" }
        switch Composition.engage(token, read: { answer }, commit: { commits += 1; return afterCommit }) {
        case .normal: return "normal"
        case .passThrough: return "app"
        case .refuse: return "beep"
        }
    }
    var keys = RawMonitor()
    guard case .command(let completed) = keys.feed(token, mode: mode) else { return "app" }
    guard let answer else { return "runs" }
    return Composition.runs(completed.command, read: { answer }) ? "runs" : "beep"
}

func composer(_ text: String, caret: Int) -> Sim {
    var sim = Sim(text: text, caret: caret, profile: axProfile)
    sim.inputMethod = true
    sim.type("i")
    return sim
}

func testInputMethods() {
    precondition(answered(.length(9), list: false) == .pending && answered(.length(0), list: true) == .clear)
    precondition(answered(.failed, list: false) == .unknown && listReads == 0, "a failed read proves nothing either way")
    precondition(answered(.absent, list: true) == .pending && answered(.absent, list: false) == .clear)
    precondition(answered(.absent, list: nil) == .unknown)
    precondition(answered(.absent, "com.sogou.inputmethod.sogou.pinyin", list: true) == .pending)
    precondition(answered(.absent, "com.sogou.inputmethod.sogou.pinyin", list: false) == .unknown)

    for escapeEngages in [true, false] {
        for answer in [Composition.pending, .clear, .unknown, nil] {
            for afterCommit in [Composition.pending, .clear, .unknown] {
                let pending = answer == .pending
                func outcome(_ keyCode: Int, _ chord: KeyNotation.Chord, _ characters: String, _ mode: RawMonitor.Mode) -> String {
                    var commits = 0
                    let outcome = imeOutcome(keyCode, chord, characters, escapeEngages: escapeEngages, mode: mode, answer: answer,
                                             afterCommit: afterCommit, commits: &commits)
                    precondition(commits == (pending && mode == .insert && keyCode == 33 ? 1 : 0), "F13 only for ⌃[ on a sure pending")
                    return outcome
                }
                let context = "escapeEngages=\(escapeEngages) answer=\(String(describing: answer)) afterCommit=\(afterCommit)"
                precondition(outcome(53, [], "\u{1B}", .insert) == (escapeEngages && !pending ? "normal" : "app"), context)
                precondition(outcome(33, [.control], "\u{1B}", .insert) == (pending && afterCommit != .clear ? "beep" : "normal"),
                             context)
                precondition(outcome(53, [], "\u{1B}", .normal) == "app", context)
                precondition(outcome(33, [.control], "\u{1B}", .normal) == (pending ? "beep" : "runs"), context)
                precondition(outcome(7, [], "x", .normal) == (pending ? "beep" : "runs"), context)
                precondition(outcome(34, [], "i", .normal) == "runs", context)
                precondition(outcome(53, [], "\u{1B}", .visual) == (escapeEngages ? (pending ? "beep" : "runs") : "app"), context)
                precondition(outcome(33, [.control], "\u{1B}", .visual) == (pending ? "beep" : "runs"), context)
            }
        }
    }

    var cancels = composer("say  world", caret: 4)
    cancels.compose("nihao")
    precondition(cancels.text == "say nihao world" && cancels.composition == .pending)
    cancels.feed("<Esc>")
    precondition(cancels.text == "say  world" && cancels.caret == 4 && cancels.state.field.mode == .insert)
    cancels.feed("<Esc>")
    precondition(cancels.state.field.mode == .normal && cancels.bells == 0)

    var keeps = composer("one\n", caret: 4)
    keeps.compose("nihao")
    keeps.feed("<C-[>")
    precondition(keeps.text == "one\nnihao" && keeps.composing == nil && keeps.state.field.mode == .normal)
    precondition(keeps.selection == 8..<9)
    keeps.type("dd")
    precondition(keeps.text == "one" && keeps.bells == 0 && keeps.settleFailures == 0)

    var unmoved = composer("say  world", caret: 4)
    unmoved.ignoresCommit = true
    unmoved.compose("ni")
    unmoved.feed("<C-[>")
    precondition(unmoved.bells == 1 && unmoved.state.field.mode == .insert && unmoved.text == "say ni world")
    precondition(unmoved.composing == 4..<6)
    unmoved.feed("<Esc>")
    unmoved.feed("<Esc>")
    precondition(unmoved.text == "say  world" && unmoved.state.field.mode == .normal)

    var unconfirmed = composer("say  world", caret: 4)
    unconfirmed.failsReadAfterCommit = true
    unconfirmed.compose("ni")
    unconfirmed.feed("<C-[>")
    precondition(unconfirmed.bells == 1 && unconfirmed.state.field.mode == .insert, "only a clear read after F13 enters Normal")

    for key in ["<Esc>", "<C-[>"] {
        var unread = composer("say  world", caret: 4)
        unread.readsComposition = false
        unread.compose("ni")
        unread.feed(key)
        precondition(unread.state.field.mode == .normal && unread.text == "say ni world" && unread.bells == 0, key)
    }

    var behind = composer("say  world", caret: 4)
    behind.learn(with: Sim.Learner(probed: axProfile))
    behind.compose("ni")
    behind.readsComposition = false
    behind.feed("<Esc>")
    behind.readsComposition = true
    let lessonsBefore = behind.learner!.lessons.count
    for keys in ["x", "dd", "A", "v"] {
        behind.type(keys)
        precondition(behind.text == "say ni world" && behind.state.field.mode == .normal, keys)
    }
    precondition(behind.bells == 4 && behind.learner!.lessons.count == lessonsBefore)
    behind.feed("<Esc>")
    precondition(behind.text == "say  world" && behind.composing == nil)
    behind.type("x")
    precondition(behind.text == "say world")
    var back = composer("say  world", caret: 4)
    back.compose("ni")
    back.readsComposition = false
    back.feed("<Esc>")
    back.readsComposition = true
    back.type("i")
    precondition(back.state.field.mode == .insert && back.bells == 0)

    var pinyin = Sim(text: "say hello world", caret: 6, profile: axProfile)
    pinyin.inputMethod = true
    pinyin.type("ciwnihao ")
    pinyin.feed("<C-[>")
    precondition(pinyin.state.session.lastChange == .unreplayable)
    let typedPinyin = pinyin.text
    pinyin.type("w.")
    precondition(pinyin.text == typedPinyin && pinyin.bells == 1, "`.` must not type the pinyin")
    var switched = Sim(text: "say hello world", caret: 6, profile: axProfile)
    switched.type("ciwbye")
    switched.inputMethod = true
    switched.feed("<C-[>")
    precondition(switched.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "bye"))
}
