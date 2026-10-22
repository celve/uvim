private func expect(
    _ source: String,
    _ expected: RawCommand.Intent,
    file: StaticString = #file,
    line: UInt = #line
) {
    let command = RawCommand(source)
    precondition(command.intent == expected, "Unexpected intent for \(source): \(command.intent)", file: file, line: line)
}

func testRawCommand() {
    expect("i", .modeChange(.insert(.beforeCursor)))
    expect("V", .modeChange(.visual(.line)))
    expect("w", .motion(.word(.forward, end: false, bigWord: false)))
    expect("<Left>", .motion(.character(.left)))
    expect("dd", .operatorCommand(.init(kind: .delete, target: .line)))
    expect("g~~", .operatorCommand(.init(kind: .swapCase, target: .line)))
    expect("g~g~", .operatorCommand(.init(kind: .swapCase, target: .line)))
    expect("gUgU", .operatorCommand(.init(kind: .uppercase, target: .line)))
    expect("guu", .operatorCommand(.init(kind: .lowercase, target: .line)))
    expect(
        "diw",
        .operatorCommand(.init(
            kind: .delete,
            target: .textObject(.init(scope: .inner, kind: .word(bigWord: false)))
        ))
    )
    expect(
        "zf}",
        .operatorCommand(.init(
            kind: .createFold,
            target: .motion(.paragraph(.forward))
        ))
    )
    expect("/needle<CR>", .search(.init(direction: .forward, pattern: "needle", isSubmitted: true)))
    expect(":write<CR>", .commandLine(.init(command: "write", isSubmitted: true)))
    expect("r", .incomplete(.characterArgument(prefix: "r")))
    expect("df", .incomplete(.operatorTarget(.delete)))
    expect("@:", .repeat(.lastExCommand))
    expect("z=", .custom(keys: "z="))
    expect("<Plug>(Surround)", .custom(keys: "<Plug>(Surround)"))

    let counted = RawCommand("\"a2d3w")
    precondition(counted.register == .init("a"))
    precondition(counted.count == 2)
    precondition(
        counted.intent == .operatorCommand(.init(
            kind: .delete,
            targetCount: 3,
            target: .motion(.word(.forward, end: false, bigWord: false))
        ))
    )

    let interleaved = RawCommand("2\"a3dd")
    precondition(interleaved.register == .init("a"))
    precondition(interleaved.count == 6)
    precondition(interleaved.intent == .operatorCommand(.init(kind: .delete, target: .line)))
}

// MARK: - RawMonitor

func testRawMonitor() {
    var monitor = RawMonitor()

    // Multi-key assembly; single keys dispatch immediately.
    precondition(monitor.feed("d", mode: .normal) == .pending)
    precondition(monitor.feed("i", mode: .normal) == .pending)
    precondition(monitor.feed("w", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("diw"))))
    precondition(monitor.pendingKeys.isEmpty)
    precondition(monitor.feed("j", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("j"))))

    // Counts and registers assemble in any interleaving.
    precondition(monitor.feed("2", mode: .normal) == .pending)
    precondition(monitor.feed("\"", mode: .normal) == .pending)
    precondition(monitor.feed("a", mode: .normal) == .pending)
    precondition(monitor.feed("3", mode: .normal) == .pending)
    precondition(monitor.feed("d", mode: .normal) == .pending)
    precondition(monitor.feed("d", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("2\"a3dd"))))

    // A key the gate handed to the app drops the half-typed command: the app may
    // have moved the caret, so completing `d` later would delete somewhere the
    // user never aimed. The Insert-mode typed log is deliberately untouched.
    precondition(monitor.feed("d", mode: .normal) == .pending)
    monitor.cancelPending()
    precondition(monitor.pendingKeys.isEmpty)
    precondition(monitor.feed("d", mode: .normal) == .pending)   // not `dd`

    monitor.reset()
    precondition(monitor.feed("h", mode: .insert) == .passthrough)
    monitor.cancelPending()
    precondition(monitor.feed("<Esc>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "h")))

    // So does a click since the last key, which the runtime tells by its count of button events (LIN-1104).
    precondition(monitor.feed("d", mode: .normal, clicks: 6) == .pending)
    precondition(monitor.feed("w", mode: .normal, clicks: 7) == .command(RawMonitor.Completed(command: RawCommand("w"))))
    precondition(monitor.feed("d", mode: .normal, clicks: 7) == .pending)
    precondition(monitor.feed("w", mode: .normal, clicks: 7) == .command(RawMonitor.Completed(command: RawCommand("dw"))))
    precondition(monitor.feed("h", mode: .insert, clicks: 7) == .passthrough)
    precondition(monitor.feed("<Esc>", mode: .insert, clicks: 9) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "h")))

    // Esc cancels a pending command; idle, it is the app's in Normal and leaves Visual.
    precondition(monitor.feed("d", mode: .normal) == .pending)
    precondition(monitor.feed("<Esc>", mode: .normal) == .cancelled)
    precondition(monitor.feed("<Esc>", mode: .normal) == .passthrough)
    precondition(monitor.feed("/", mode: .normal) == .pending)
    precondition(monitor.feed("<Esc>", mode: .normal) == .cancelled)
    precondition(monitor.feed("i", mode: .visual) == .pending)
    precondition(monitor.feed("<Esc>", mode: .visual) == .cancelled)
    precondition(monitor.feed("<Esc>", mode: .visual) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"))))
    precondition(monitor.feed("\u{1B}", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("\u{1B}"))))

    // Visual: bare operators fire on the selection; i/a await their object.
    precondition(monitor.feed("d", mode: .visual) ==
        .command(RawMonitor.Completed(command: RawCommand("d"))))
    precondition(monitor.feed("i", mode: .visual) == .pending)
    precondition(monitor.feed("w", mode: .visual) ==
        .command(RawMonitor.Completed(command: RawCommand("iw"))))

    // Prompts stay open until submitted; backspace edits, then cancels.
    precondition(monitor.feed("/", mode: .normal) == .pending)
    precondition(monitor.feed("n", mode: .normal) == .pending)
    precondition(monitor.feed("e", mode: .normal) == .pending)
    precondition(monitor.feed("<CR>", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("/ne<CR>"))))
    precondition(monitor.feed("/", mode: .normal) == .pending)
    precondition(monitor.feed("n", mode: .normal) == .pending)
    precondition(monitor.feed("<BS>", mode: .normal) == .pending)
    precondition(monitor.feed("<BS>", mode: .normal) == .cancelled)

    // Insert: passthrough with a typed log, handed over once at Esc; an arrow makes it lossy.
    precondition(monitor.feed("h", mode: .insert) == .passthrough)
    precondition(monitor.feed("i", mode: .insert) == .passthrough)
    precondition(monitor.feed("<Left>", mode: .insert) == .passthrough)
    precondition(monitor.feed("<Esc>", mode: .insert) == .command(RawMonitor.Completed(
        command: RawCommand("<Esc>"), insertPayload: "hi", insertPayloadIsLossless: false
    )))
    precondition(monitor.feed("<Esc>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "")))

    for token in ["h", "e", "l", "o", "<BS>", "l", "o", "<CR>", "x"] {
        precondition(monitor.feed(token, mode: .insert) == .passthrough)
    }
    precondition(monitor.feed("<Esc>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "hello\nx")))

    // Backspace past the typed text is lossy.
    precondition(monitor.feed("a", mode: .insert) == .passthrough)
    precondition(monitor.feed("<BS>", mode: .insert) == .passthrough)
    precondition(monitor.feed("<BS>", mode: .insert) == .passthrough)
    precondition(monitor.feed("<Esc>", mode: .insert) == .command(RawMonitor.Completed(
        command: RawCommand("<Esc>"), insertPayload: "", insertPayloadIsLossless: false
    )))

    precondition(monitor.feed("a", mode: .insert) == .passthrough)
    monitor.markInsertLogLossy()
    precondition(monitor.feed("<Esc>", mode: .insert) == .command(RawMonitor.Completed(
        command: RawCommand("<Esc>"), insertPayload: "a", insertPayloadIsLossless: false
    )))
    precondition(monitor.feed("b", mode: .insert) == .passthrough)
    precondition(monitor.feed("<Esc>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "b")))
    monitor.markInsertLogLossy()
    monitor.reset()
    precondition(monitor.feed("<Esc>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "")))

    // <C-[> must complete insert, cancel pending, and dispatch alone, even idle in Normal.
    precondition(monitor.feed("h", mode: .insert) == .passthrough)
    precondition(monitor.feed("<C-[>", mode: .insert) ==
        .command(RawMonitor.Completed(command: RawCommand("<Esc>"), insertPayload: "h")))
    precondition(monitor.feed("d", mode: .normal) == .pending)
    precondition(monitor.feed("<C-[>", mode: .normal) == .cancelled)
    precondition(monitor.feed("<C-[>", mode: .normal) ==
        .command(RawMonitor.Completed(command: RawCommand("<C-[>"))))
}
