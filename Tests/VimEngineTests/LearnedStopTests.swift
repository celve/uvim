// MARK: - Stops learned from where the keys land (LIN-2050)

func stopProbes(_ plan: PhysicalPlan) -> [Expectation.StopProbe] {
    plan.steps.compactMap { if case .settle(let expectation) = $0 { expectation.stop } else { nil } }
}

/// The Sim's ProseMirror without Linear's entry, whose field hides the selection at a stop as Tiptap's does.
func tiptapSim(_ doc: [(String, Sim.ListLine)], _ profile: CapabilityProfile = stopsProfile) -> Sim {
    var host = blockSim(profile, doc)
    host.editor = .proseMirror
    host.hidesSelectionAtStops = true
    return host
}

/// A table, then a rule with ProseMirror's gap cursor between them that no tree read shows (gapcursor's `GapCursor.valid`).
func gapDoc(unseen: [Linear.Stop] = [.ruleGap]) -> [(String, Sim.ListLine)] {
    var ruled = Sim.ListLine(ruled: 1, before: [.rule])
    ruled.unseen = unseen
    return [("Top paragraph", .init()), ("Cell one", .init(cell: true)), ("Cell two", .init(lastRow: true)),
            ("After a rule", ruled), ("Last paragraph.", .init())]
}

func testLearnedStops() {
    let blocks = folded(tiptapBlocksValue, tiptapBlocksObjects, fakeTree(tiptapBlocksSpec, linear: false))
    let fromParaOne = webPhysical("j", text: blocks.text, caret: lineStart(of: "Para one", in: blocks.text), profile: stopsProfile,
                                  breaks: blocks.breaks)
    precondition(stopProbes(fromParaOne) == [.init(chord: .right, line: lineStart(of: "Para two", in: blocks.text))],
                 "the → run crossing to the next line is probed, ⌃E and the column are not")
    precondition(stopProbes(tablesPlan("j", "Paragraph before rule hotel")).isEmpty
                 && stopProbes(tablesPlan("k", "Paragraph after rule india")).isEmpty, "Linear has its entry")
    let flat = webPhysical("j", text: "one\ntwo", caret: 0, profile: stopsProfile, breaks: ParagraphBreaks(offsets: [3], editor: .proseMirror))
    precondition(stopProbes(flat).isEmpty, "a field with no stops or tables plans as before")

    var learned = LearnedStops()
    learned.learn([.init(chord: .right, line: lineStart(of: "Para two", in: blocks.text))], in: blocks.text)
    func learnedPlan(_ text: String) -> [Chord] {
        let caret = lineStart(of: "Para one", in: blocks.text)
        let snapshot = FieldSnapshot(capabilities: stopsProfile, text: text, selection: caret..<caret, webContent: true,
                                     breaks: blocks.breaks)
        return chords(PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand("j"), state: .initial), snapshot: snapshot,
                                               learned: learned).plan)
    }
    precondition(learnedPlan(blocks.text) == chords(fromParaOne) + [.right], "a learned stop is one more →")
    precondition(learnedPlan(blocks.text + " ") == chords(fromParaOne), "and only in the text it was learned in")

    // The Sim: the first crossing presses once more and learns, later ones press it up front, an edit forgets.
    var host = tiptapSim(gapDoc())
    var plain = Sim(text: host.text, caret: 0, profile: stopsProfile)
    plain.emulatesKeys = true
    var retries = 0
    for (index, key) in "jjjjggjjjjxggjjjjk$kj0kjj".enumerated() {
        host.type(String(key))
        plain.type(String(key))
        precondition(host.caret == plain.caret && host.text == plain.text, "at \(index)")
        retries += host.lastLearned.count
    }
    precondition(host.settleFailures == 0 && host.bells == 0 && host.blamed.isEmpty, "every crossing lands")
    precondition(retries == 3, "→ before and after the edit, and ← once: \(retries)")

    // A stop one more press does not clear ends the run, unblamed.
    host = tiptapSim(gapDoc(unseen: [.ruleGap, .ruleGap]))
    for key in "jjj" { host.type(String(key)) }
    precondition(host.settleFailures == 1 && host.blamed.isEmpty && host.lastLearned.isEmpty, "one more press, once")
}
