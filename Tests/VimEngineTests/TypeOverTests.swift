/// Where insertText is broken, as in Slack's composer: typing that keeps the selection is undone, learned, then avoided (LIN-3277).
let typingProfile = removing([.insertText], from: axProfile)

func typingSim(_ text: String, caret: Int) -> Sim {
    var field = Sim(text: text, caret: caret, profile: typingProfile)
    field.typesBesideWrittenSelection = true
    field.learn(with: Sim.Learner(probed: typingProfile))
    return field
}

func testTypeOver() {
    var denied = removing([.insertText], from: writeKeys)
    denied.statuses[.typeOver] = .unavailable
    let resolved = CapabilityResolver.resolve(probed: typingProfile, config: [:], learned: [])
    precondition(resolved.profile.statuses[.typeOver] == .unknown && !resolved.profile.denies(.typeOver))
    let learned = CapabilityResolver.resolve(probed: typingProfile, config: [:], learned: [.typeOver])
    precondition(learned.report.entries[.typeOver] == CapabilityReport.Entry(status: .unavailable, source: .learned))
    let userOn = CapabilityResolver.resolve(probed: typingProfile, config: [.typeOver: ConfigChoice(override: .on)], learned: [.typeOver])
    precondition(userOn.profile.has(.typeOver))

    var typed = Expectation(selection: 13..<13, length: 15)
    (typed.typedOver, typed.typedOverWrite) = (1, true)
    var missed = RunAttribution()
    missed.record(.softSettle(typed), passed: true, selection: 12..<12, length: 14)
    precondition(missed.evidence.isEmpty, "a soft miss supports nothing")
    var unmoved = RunAttribution()
    unmoved.record(.softSettle(typed), passed: true, selection: 12..<13, length: 15, converged: false)
    precondition(unmoved.evidence.isEmpty, "nor one whose length happens to match")

    var overOne = Expectation(length: 3)
    overOne.typedOver = 1
    let typedOn: (PhysicalStep) -> [PhysicalStep] = { [$0, .typeText("x"), .softSettle(overOne)] }
    let judged = { (steps: [PhysicalStep]) -> Bool? in
        guard case .softSettle(let expectation)? = PhysicalPlanner.judgingTypedOver(steps).last else { return nil }
        return expectation.typedOverWrite
    }
    precondition(judged(typedOn(.setSelection(0..<1))) == true)
    precondition(judged([.setSelection(0..<0)] + typedOn(.press(.selectRight, count: 1))) == false, "arrows finished the selection")

    var field = typingSim("hello world abc", caret: 12)
    precondition(field.profile.statuses[.typeOver] == .unknown)
    field.type("rx")
    precondition(field.text == "hello world abc" && field.settleFailures == 1)
    precondition(field.attribution.evidence.contains { $0.question == .write(.typeOver) && $0.outcome == .refutes && $0.why == .kept })
    precondition(field.learner!.lessons.last?.committed == .typeOver && field.profile.denies(.typeOver))
    precondition(broken(field.learner!.store, rung: field.learner!.rung, versions: field.learner!.versions) == [.typeOver])

    let keyed = physical("rx", text: field.text, caret: field.caret, profile: field.profile)
    precondition(keyed.steps.contains(.press(.selectRight, count: 1)))
    field.type("rx")
    precondition(field.text == "hello world xbc" && field.settleFailures == 1)
    precondition(!field.attribution.evidence.contains { $0.question == .write(.typeOver) }, "a selection keys made says nothing of writes")

    var together = typingSim("hello world abc", caret: 12)
    together.undoesEditsTogether = true
    together.type("xrb")
    precondition(together.text == "hello world bc" && together.settleFailures == 2 && together.profile.denies(.typeOver),
                 "⇧⌘Z returns the earlier edit an undo step took back with the typing, which goes alone")

    var accent = typingSim("xa\u{301}bc", caret: 0)
    accent.undoesEditsTogether = true
    accent.type("xra")
    precondition(accent.text == "a\u{301}bc" && accent.profile.denies(.typeOver), "the typed run ends on a whole character")

    let held = FieldSnapshot(
        capabilities: denied, text: "ab\nw\nzz", selection: 3..<3,
        breaks: ParagraphBreaks(offsets: [2, 4], hidden: [.init(at: 3, text: "")])
    )
    let folded = PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("rx"), state: .initial), snapshot: held).steps
    if let operand = folded.firstIndex(where: { if case .settle = $0 { return true }; return false }),
       let arrow = folded[operand...].firstIndex(of: .press(.selectRight, count: 1)) {
        precondition(folded[operand..<arrow].contains { if case .setSelection = $0 { return true }; return false },
                     "a folded line's start writes its caret from the held letter: \(folded.map(\.traceCode).joined())")
    } else {
        preconditionFailure("\(folded.map(\.traceCode).joined())")
    }

    for (keys, caret, after) in [("~", 0, "Hello world"), ("gUiw", 6, "hello WORLD"), ("J", 0, "hello world")] {
        let text = keys == "J" ? "hello\nworld" : "hello world"
        var over = typingSim(text, caret: caret)
        over.type(keys)
        precondition(over.text == text && over.settleFailures == 1 && over.profile.denies(.typeOver), "\(keys): undone and learned")
        over.type(keys)
        precondition(over.text == after && over.settleFailures == 1, "\(keys): then made by ⇧→")
    }

    let doc = listCodeDoc.map(\.0).joined(separator: "\n")
    for (index, line) in listCodeDoc.enumerated() where line.0.first?.isLetter == true {
        var item = listCodeSim(denied, caret: lineStart(of: line.0, in: doc), spans: [])
        item.type("rx")
        let expected = listCodeDoc.enumerated().map { $0.offset == index ? "x" + $0.element.0.dropFirst() : $0.element.0 }
        precondition(item.text == expected.joined(separator: "\n") && item.settleFailures == 0,
                     "\(line.0): its first letter is selected by ⇧→ from a written caret \(item.text.debugDescription)")
    }

    for caret in [0, 34, 51, 66, 67, 82] {
        var host = codeSim(denied, caret: caret)
        let reference = codeSim(removing([.insertText], from: writeKeys), caret: caret)
        var replaced = reference
        replaced.type("rx")
        host.type("rx")
        precondition(host.text == replaced.text && host.bells == replaced.bells && host.settleFailures == 0,
                     "\(caret): ⇧→ over a code span's letter \(host.text.debugDescription) \(host.settleFailures)")
    }

    var plain = Sim(text: "hello world abc", caret: 12, profile: typingProfile)
    plain.learn(with: Sim.Learner(probed: typingProfile))
    plain.type("rx")
    precondition(plain.text == "hello world xbc" && plain.settleFailures == 0 && plain.profile.statuses[.typeOver] == .unknown)
    precondition(plain.attribution.evidence.contains { $0.question == .write(.typeOver) && $0.outcome == .supports(nil) })
    precondition(!physical("rx", text: plain.text, caret: 12, profile: plain.profile).steps.contains(.press(.selectRight, count: 1)))

    var empty = Sim(text: "ab\n\ncd", caret: 3, profile: typingProfile)
    empty.type("rx")
    precondition(empty.text == "ab\n\ncd" && empty.bells == 1, "r on an empty line rings")
}
