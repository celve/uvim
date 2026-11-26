/// Where insertText is broken, as in Slack's composer: typing that keeps the selection is undone, learned, then avoided (LIN-3277).
let typingProfile = removing([.insertText], from: axProfile)

func typingSim(_ text: String, caret: Int) -> Sim {
    var field = Sim(text: text, caret: caret, profile: typingProfile)
    field.typesBesideWrittenSelection = true
    field.learn(with: Sim.Learner(probed: typingProfile))
    return field
}

func testTypeOver() {
    let resolved = CapabilityResolver.resolve(probed: typingProfile, config: [:], learned: [])
    precondition(resolved.profile.statuses[.typeOver] == .unknown && !resolved.profile.denies(.typeOver))
    let learned = CapabilityResolver.resolve(probed: typingProfile, config: [:], learned: [.typeOver])
    precondition(learned.report.entries[.typeOver] == CapabilityReport.Entry(status: .unavailable, source: .learned))
    let userOn = CapabilityResolver.resolve(probed: typingProfile, config: [.typeOver: ConfigChoice(override: .on)], learned: [.typeOver])
    precondition(userOn.profile.has(.typeOver))

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
    precondition(field.attribution.evidence.contains { $0.question == .write(.typeOver) && $0.outcome == .supports(nil) })

    var together = typingSim("hello world abc", caret: 12)
    together.undoesEditsTogether = true
    together.type("xrb")
    precondition(together.text == "hello world bbc" && together.settleFailures == 2 && together.profile.denies(.typeOver),
                 "⇧⌘Z returns the earlier edit an undo step took back with the typing")

    for (keys, caret, after) in [("~", 0, "Hello world"), ("gUiw", 6, "hello WORLD"), ("J", 0, "hello world")] {
        let text = keys == "J" ? "hello\nworld" : "hello world"
        var over = typingSim(text, caret: caret)
        over.type(keys)
        precondition(over.text == text && over.settleFailures == 1 && over.profile.denies(.typeOver), "\(keys): undone and learned")
        over.type(keys)
        precondition(over.text == after && over.settleFailures == 1, "\(keys): then made by ⇧→")
    }

    var plain = Sim(text: "hello world abc", caret: 12, profile: typingProfile)
    plain.learn(with: Sim.Learner(probed: typingProfile))
    plain.type("rx")
    precondition(plain.text == "hello world xbc" && plain.settleFailures == 0 && plain.profile.statuses[.typeOver] == .unknown)
    precondition(!physical("rx", text: plain.text, caret: 12, profile: plain.profile).steps.contains(.press(.selectRight, count: 1)))

    var empty = Sim(text: "ab\n\ncd", caret: 3, profile: typingProfile)
    empty.type("rx")
    precondition(empty.text == "ab\n\ncd" && empty.bells == 1, "r on an empty line rings")
}
