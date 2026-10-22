// MARK: - The recorder's renderers

// A hard settle behind a press can name no capability, so it rings and teaches nothing.
func settleFollowsPress(_ plan: PhysicalPlan) -> Bool {
    for (index, step) in plan.steps.enumerated() where index > 0 {
        guard case .settle = step, case .press = plan.steps[index - 1] else { continue }
        return true
    }
    return false
}

func testRenderers() {
    precondition(ciwA.traceShape == "W!!R!CCC")
    precondition(physical("ciw", text: "say hello world", caret: 6, profile: readProfile).traceShape
                 == "P2P5!!P?CCC")
    precondition(physical("ciw", text: "say hello world", caret: 6, profile: blindProfile).traceShape
                 == "P2P5PCCC")

    precondition(settleFollowsPress(physical("ciw", text: "say hello world", caret: 6, profile: readProfile)))
    precondition(!settleFollowsPress(ciwA))
    precondition(!physical("ciw", text: "say hello world", caret: 6, profile: blindProfile).traceShape
                 .contains("!"))

    precondition(physical("3w", text: "say hello world", caret: 0, profile: readProfile).traceShape == "P15!C")

    precondition(CapabilityReport(entries: [
        .readText: .init(status: .available, source: .probed),
        .writeSelection: .init(status: .unavailable, source: .learned),
    ]).traceGrid == "RT+p RL?? RC?? RS?? WS-l IT?? DC?? WD?? FS?? KA?? KE?? KT?? KB?? NM?? WK?? PK??")
}

// MARK: - The redaction rule

let secret = "hunter2"

func testRedaction() {
    let leaky: [LogicalStep] = [
        .insertText(secret),
        .replaceSelection(secret),
        .setMark("h"),
        .bell(.unsupported(secret)),
        .bell(.emptyRegister("h")),
        .bell(.unsetMark("h")),
    ]
    for step in leaky {
        precondition(!step.traceName.contains(secret), "traceName leaked a text payload")
    }
    precondition(LogicalStep.insertText(secret).traceName == "insertText(7)")

    let leakySteps = PhysicalPlan(steps: [
        .replaceSelection(secret), .typeText(secret), .clipboardInsert(secret),
        .commit(.setLastInsert(secret)),
    ])
    precondition(!leakySteps.traceShape.contains(secret), "traceShape leaked a text payload")
    precondition(leakySteps.traceShape == "RTVC")

    // `Z` and `hunter2` are the operands; no case name `shape` emits holds either.
    for leak in ["/hunter2<CR>", "d/hunter2<CR>", "d?hunter2<CR>", "y/hunter2<CR>",
                 ":s/hunter2/x<CR>", "rZ", "dfZ", "ctZ", "\"ZY", "mZ", "`Z", "ciZ", "qZ"] {
        let rendered = RawCommand(leak).traceKeys
        precondition(!rendered.contains("Z") && !rendered.contains("hunter2"),
                     "traceKeys leaked an operand: " + leak + " -> " + rendered)
    }

    // The `.incomplete` forms are why the check scans `source`: the parse discards a count.
    for digits in ["4111111111111111w", "d4111111111111111w", "4155551234x", "41111",
                   "3dd", "12j", "2yy", "d3w",
                   "d4111111111111111", "d4111111111111111f", "y4155551234"] {
        let rendered = RawCommand(digits).traceKeys
        precondition(rendered != digits, "a counted command reached the log verbatim: " + digits)
        let shape = String(rendered.split(separator: "…").first ?? "")
        precondition(!shape.contains(where: \.isNumber),
                     "traceKeys leaked a count digit: " + digits + " -> " + rendered)
    }
    precondition(RawCommand("3dd").traceKeys == "op(delete,line)…(3)")
    precondition(RawCommand("4111111111111111w").traceKeys == "motion(word)…(17)")
    precondition(RawCommand("d4111111111111111w").traceKeys == "op(delete,word)…(18)")
    precondition(RawCommand("d4111111111111111").traceKeys == "incomplete…(17)")
    precondition(RawCommand("y4155551234").traceKeys == "incomplete…(11)")
    precondition(RawCommand("0").traceKeys == "motion(lineStart)…(1)")
    precondition(RawCommand("d/hunter2<CR>").traceKeys == "op(delete,search)…(13)")
    precondition(RawCommand("rS").traceKeys == "edit(replaceCharacter)…(2)")
    precondition(RawCommand("dfS").traceKeys == "op(delete,find)…(3)")
    precondition(RawCommand("mS").traceKeys == "mark…(2)")
    precondition(RawCommand("`S").traceKeys == "motion(mark)…(2)")
    precondition(RawCommand("\"aY").traceKeys == "edit(yankLine)…(3)")
    precondition(RawCommand("/hunter2<CR>").traceKeys == "search…(12)")
    precondition(RawCommand(":s/x/y<CR>").traceKeys == "cmdline…(10)")

    for plain in ["ciw", "w", "b", "dd", "x", "p", "gg", "A", "S", "gU", "diw", "yy", "u"] {
        precondition(RawCommand(plain).traceKeys == plain, "needlessly redacted: " + plain)
    }
}

// MARK: - Rejections and the reason that already existed

// The 27th: the lowering drops `BellReason`, but the logical plan still holds it.
func bellReason(_ keys: String) -> String? {
    for step in LogicalPlanner.plan(RawCommand(keys), state: .initial).steps {
        if case .bell(let reason) = step { return reason.traceName }
    }
    return nil
}

func testRejections() {
    // A rejection carries no reason, so the failing step's type is it.
    let joinReject = traced("J", text: "a\nb", caret: 0, profile: blockProfile)
    precondition(joinReject.plan == .rejected)
    precondition(joinReject.rejection?.index == 0)
    precondition(joinReject.rejection!.step.traceName == "joinLines(2)")

    let markReject = traced("ma", profile: blindProfile)
    precondition(markReject.plan == .rejected)
    precondition(markReject.rejection!.step.traceName == "setMark")

    precondition(traced("ciw", text: "say hello world", caret: 6, profile: axProfile).rejection == nil)
    precondition(traced("ciw", text: "say hello world", caret: 6, profile: axProfile).plan == ciwA)

    precondition(bellReason("gv") == "noPriorVisual")
    precondition(bellReason("g-") == "unsupported")
    precondition(bellReason("\"ap") == "emptyRegister")
    precondition(bellReason("'a") == "unsetMark")
    precondition(bellReason("ciw") == nil)
}

// MARK: - The settle's comparison

func testSettleComparison() {
    precondition(Expectation(selection: 4..<9, length: 15).traceFields == "sel=4..9 len=15")
    precondition(Expectation().traceFields == "sel=nil len=nil")
    // The settle line used to assemble these four fragments by hand; pinned so the one
    // restructured line in `Diag` stays byte-identical.
    precondition(
        " want \(Expectation(selection: 4..<9, length: 15).traceFields)"
            + " got \(Expectation(selection: 0..<0, length: 15).traceFields)"
            == " want sel=4..9 len=15 got sel=0..0 len=15"
    )

    precondition(Expectation().matches(selection: nil, length: nil), "a prediction of nothing is already met")
    precondition(Expectation().matches(selection: 3..<4, length: 99), "unpredicted fields are not checked")
    precondition(Expectation(selection: 4..<9).matches(selection: 4..<9, length: nil))
    precondition(!Expectation(selection: 4..<9).matches(selection: 0..<0, length: nil), "disagreed")
    precondition(!Expectation(selection: 4..<9).matches(selection: nil, length: nil), "no answer")
    precondition(!Expectation(length: 15).matches(selection: nil, length: nil), "no answer")
    precondition(Expectation(selection: 4..<9, length: 15).matches(selection: 4..<9, length: 15))
    precondition(!Expectation(selection: 4..<9, length: 15).matches(selection: 4..<9, length: 14))

    let checkedWord = Expectation(selection: 4..<9, length: 15, selectedText: "hello")
    precondition(checkedWord.matches(selection: 4..<9, length: 15, selectedText: "hello"))
    precondition(!checkedWord.matches(selection: 4..<9, length: 15, selectedText: "mber "), "offsets agree, text does not")
    precondition(!checkedWord.matches(selection: 4..<9, length: 15), "no answer")
    precondition(Expectation(selection: 4..<9).matches(selection: 4..<9, length: nil, selectedText: "mber "))
    precondition(!Expectation(selectedText: "a\u{FFFC}b").matches(selection: nil, length: nil, selectedText: "ab"), "an attachment counts")
    precondition(checkedWord.traceFields == "sel=4..9 len=15 text=(5)")
    precondition(!Expectation(selectedText: secret).traceFields.contains(secret), "traceFields leaked the selected text")

    let paragraphEnd = Expectation(selection: 2..<2, length: 5, edge: .paragraphEnd)
    precondition(paragraphEnd.converged(selection: 2..<2, length: 5, selectedText: nil, side: .end))
    precondition(!paragraphEnd.converged(selection: 2..<2, length: 5, selectedText: nil, side: .start(skipping: 0)), "the other side")
    precondition(!paragraphEnd.converged(selection: 2..<2, length: 5, selectedText: nil, side: nil), "no marker read")
    precondition(!paragraphEnd.converged(selection: 3..<3, length: 5, selectedText: nil, side: .end), "offsets still decide")
    precondition(Expectation(selection: 2..<2, edge: .paragraphStart)
        .converged(selection: 2..<2, length: nil, selectedText: nil, side: .start(skipping: 2)), "past a list marker")
    precondition(Expectation(selection: 4..<9).converged(selection: 4..<9, length: nil, selectedText: nil, side: nil))
}
