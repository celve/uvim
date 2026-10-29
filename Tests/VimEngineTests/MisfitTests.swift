// MARK: - Misfits: the field model before the key (LIN-2370)

func testMisfits() {
    // `•one⏎•two⏎•three` in field offsets, its markers held: `•` at 0..<1 starts the field, at 8..<9 a paragraph after another.
    let held = [Expectation.Equivalence(run: 0..<1, afterBreak: false), Expectation.Equivalence(run: 8..<9, afterBreak: true)]
    var lineStart = Expectation(landing: .exact(9..<9), length: 16, edge: .paragraphStart)
    lineStart.equivalences = held
    let start = ParagraphBreaks.Side.start(skipping: 0)
    precondition(lineStart.converged(selection: 8..<8, length: 16, selectedText: nil, side: start), "before a held marker, on its start side")
    precondition(!lineStart.converged(selection: 8..<8, length: 16, selectedText: nil, side: .end), "the paragraph before's end is not")
    precondition(!lineStart.converged(selection: 8..<8, length: 16, selectedText: nil, side: nil), "nor an unread side")
    precondition(!lineStart.converged(selection: 8..<8, length: 15, selectedText: nil, side: start), "an equivalent place, a wrong length")
    precondition(!lineStart.converged(selection: 7..<7, length: 16, selectedText: nil, side: start), "a marker merely nearby")
    precondition(!lineStart.converged(selection: 10..<10, length: 16, selectedText: nil, side: start), "nor past it")
    var lineEnd = Expectation(landing: .exact(8..<8), length: 16)
    lineEnd.equivalences = held
    precondition(!lineEnd.converged(selection: 9..<9, length: 16, selectedText: nil, side: start), "the line above's end is not the next one's start")
    var before = Expectation(landing: .exact(8..<8), length: 16, edge: .paragraphStart)
    before.equivalences = held
    precondition(before.converged(selection: 9..<9, length: 16, selectedText: nil, side: start), "unless the expectation means its start side")
    var fieldStart = Expectation(landing: .exact(1..<1), length: 16)
    precondition(!fieldStart.matches(selection: 0..<0, length: 16), "only across a run the model holds")
    fieldStart.equivalences = held
    precondition(fieldStart.matches(selection: 0..<0, length: 16), "the field's start needs no side")
    var word = Expectation(landing: .exact(1..<4), length: 16, selectedText: "one")
    word.equivalences = held
    precondition(word.matches(selection: 0..<4, length: 16, selectedText: "one") && !word.matches(selection: 0..<4, length: 16, selectedText: "•one"),
                 "a selection's end across a marker, its text still checked")
    var third = Expectation(landing: .exact(9..<14), length: 16)
    third.equivalences = held
    precondition(!third.matches(selection: 8..<14, length: 16), "a selection's lower end has no side read")
    var after = Expectation(landing: .caretAfter(8, strict: true), length: 16)
    after.equivalences = held
    precondition(after.matches(selection: 8..<8, length: 16, side: start), "any landing, across a held marker")
    var strictBefore = Expectation(landing: .caretBefore(10, strict: true), length: 20, blame: .init(capability: .wordKeys, unmoved: [10..<10]))
    strictBefore.equivalences = [Expectation.Equivalence(run: 8..<10, afterBreak: true)]
    precondition(!strictBefore.converged(selection: 10..<10, length: 20, selectedText: nil, side: nil)
                 && !strictBefore.converged(selection: 8..<8, length: 20, selectedText: nil, side: start), "the same place is no progress")
    precondition(strictBefore.converged(selection: 8..<8, length: 20, selectedText: nil, side: .end), "the line above's end is")
    var strictAfter = Expectation(landing: .caretAfter(0, strict: true), length: 20)
    strictAfter.equivalences = [Expectation.Equivalence(run: 0..<2, afterBreak: false)]
    precondition(!strictAfter.matches(selection: 2..<2, length: 20) && strictAfter.matches(selection: 3..<3, length: 20),
                 "crossing only a marker is no progress")
    var within = Expectation(landing: .caretWithin(9...12), length: 16)
    within.equivalences = held
    precondition(within.matches(selection: 8..<8, length: 16, side: start) && !within.matches(selection: 8..<8, length: 16, side: .end))
    precondition(lineStart.asksSide(at: 3..<3) && !word.asksSide(at: 4..<4) && word.asksSide(at: 8..<8) && !word.asksSide(at: 0..<0),
                 "a side is read for an edge, or at a held run's lower end after a break")

    // The pre-#81 Slack `k`: ⌃A expected at 8, the start of `•three` as text, lands after the `•` it cannot reach.
    let unmoved = Expectation.Blame(capability: .lineStartKey, unmoved: [9..<9])
    var k = Expectation(landing: .exact(8..<8), length: 16, edge: .paragraphStart, blame: unmoved)
    k.onBreak = true
    precondition(k.misfit(selection: 9..<9, length: 16, selectedText: nil) { start } == 8..<9)
    precondition(k.misfit(selection: 9..<9, length: 15, selectedText: nil) { start } == nil, "a wrong length is no misfit")
    precondition(k.misfit(selection: 9..<9, length: 16, selectedText: nil) { .end } == nil, "nor a wrong side")
    precondition(k.misfit(selection: 15..<15, length: 16, selectedText: nil) { start } == nil, "nor beyond a marker's reach")
    precondition(k.misfit(selection: 9..<10, length: 16, selectedText: nil) { start } == nil, "nor a selection")
    precondition(k.misfit(selection: nil, length: 16, selectedText: nil) { start } == nil, "nor a non-answer")
    var lineAboveEnd = Expectation(landing: .exact(8..<8), length: 16)
    lineAboveEnd.onBreak = true
    precondition(lineAboveEnd.misfit(selection: 9..<9, length: 16, selectedText: nil) { start } == nil, "a caret short of the line above's end")
    let afterNewline = Expectation(landing: .exact(6..<6), length: 13, blame: unmoved)
    precondition(afterNewline.misfit(selection: 7..<7, length: 13, selectedText: nil) { nil } == 6..<7, "no break, so no side to tell")
    precondition(Expectation(landing: .caretBefore(9, strict: true), length: 16).misfit(selection: 9..<9, length: 16, selectedText: nil) { start } == nil,
                 "a relative landing is no misfit")
    let past = Expectation(landing: .exact(9..<9), length: 16)
    precondition(past.misfit(selection: 8..<8, length: 16, selectedText: nil) { nil } == nil, "a caret before may be the line above's end")
    precondition(past.misfit(selection: 8..<8, length: 16, selectedText: nil) { start } == 8..<9)
    precondition(Expectation(landing: .exact(1..<1), length: 16).misfit(selection: 0..<0, length: 16, selectedText: nil) { nil } == 0..<1)

    var misfitting = RunAttribution()
    misfitting.record(.settle(k), passed: false, selection: 9..<9, length: 16, misfit: true)
    precondition(misfitting.evidence == [key(.lineStartKey, .neutral, .misfit)], "a misfit strikes nothing")
    precondition(!Learning.teaches(misfitting.evidence[0]))
    precondition(judged(k, 9..<9) == key(.lineStartKey, .refutes, .unmoved), "unexplained, the unmoved key strikes")
    let text = Expectation(landing: .exact(8..<8), length: 16, selectedText: "")
    var written = RunAttribution()
    written.record(.setSelection(8..<8))
    written.record(.settle(text), passed: false, selection: 9..<9, length: 16, selectedText: "x", misfit: true)
    precondition(written.evidence == [Evidence(.write(.writeSelection), .neutral, why: .misfit, seen: .settle(1))],
                 "a write's misfit is never offsets evidence")
    var long = RunAttribution()
    long.record(.setSelection(8..<8))
    long.record(.settle(Expectation(landing: .exact(8..<8), length: 16)), passed: false, selection: 8..<8, length: 15)
    precondition(long.evidence == [Evidence(.write(.writeSelection), .refutes, why: .length, seen: .settle(1))], "a wrong length")
    var sided = RunAttribution()
    sided.record(.setSelection(8..<8))
    sided.record(.settle(Expectation(landing: .exact(8..<8), length: 16, edge: .paragraphStart)), passed: false, selection: 8..<8, length: 16)
    precondition(sided.evidence == [Evidence(.write(.writeSelection), .refutes, why: .edge, seen: .settle(1))], "a wrong side")

    // Quill's tree, as `UnreachableLineTests` has it: each item's `::before` group holds a generated `•`.
    let quillTree = fakeTree("0/L/0/12 0.0/G/0/4 0.0.0/G/0/1 0.0.0.0/T/0/1 0.0.1/T/1/4 0.1/G/4/6 0.1.0/G/4/5 0.1.0.0/T/4/5 0.2/G/6/12 0.2.0/G/6/7 0.2.0.0/T/6/7 0.2.1/T/7/12", linear: false)
    var generated = Set(quillTree[0].children.map { ObjectIdentifier($0.children[0].children[0]) })
    func generates(_ run: Range<Int>, in roots: [FakeNode], budget: Int = GeneratedText.runBudget) -> Bool {
        var scan = GeneratedTextScan<FakeNode>(budget: budget) { node in
            node.fails ? nil : .init(role: node.role, id: generated.contains(ObjectIdentifier(node)) ? -1000000002 : 9, children: node.children)
        }
        return scan.generates(run, in: roots, offset: { node, end in end ? node.end : node.start })
    }
    precondition(generates(0..<1, in: quillTree) && generates(4..<5, in: quillTree) && generates(6..<7, in: quillTree))
    precondition(!generates(1..<2, in: quillTree) && !generates(0..<2, in: quillTree) && !generates(5..<6, in: quillTree),
                 "the item's own text, or a run past the marker")
    precondition(!generates(6..<7, in: quillTree, budget: 4), "past the budget")
    quillTree[0].children[2].fails = true
    precondition(!generates(6..<7, in: quillTree), "a failed read")
    // Linear's ordered marker is two generated nodes, `1` and `.` (softlash/LIN-2369's linearExample4).
    let linearSpec = "0/L/0/2 0.0/G/0/2 0.0.0/G/0/1 0.0.0.0/Tg/0/1 0.0.1/G/1/2 0.0.1.0/T/1/2 1/L/2/5 1.0/G/2/5 1.0.0/G/2/4 1.0.0.0/Tg/2/3 1.0.0.1/Tg/3/4 1.0.1/G/4/5 1.0.1.0/T/4/5 2/G/5/12 2.0/T/5/12"
    let linearTree = fakeTree(linearSpec, linear: false)
    for token in linearSpec.split(separator: " ") where token.split(separator: "/")[1] == "Tg" {
        let path = token.split(separator: "/")[0].split(separator: ".").map { Int($0)! }
        generated.insert(ObjectIdentifier(path.dropFirst().reduce(linearTree[path[0]]) { $0.children[$1] }))
    }
    precondition(generates(2..<4, in: linearTree) && generates(0..<1, in: linearTree), "a marker over two leaves")
    precondition(!generates(2..<5, in: linearTree) && !generates(1..<3, in: linearTree), "and not past them")
    let nativeTree = fakeTree("0/L/0/9 0.0/G/0/5 0.0.0/M/0/2 0.0.1/T/2/5 0.1/G/5/9 0.1.0/M/5/7 0.1.1/T/7/9", linear: false)
    precondition(generates(5..<7, in: nativeTree) && !generates(4..<6, in: nativeTree), "Chromium's own marker")

    // The Sim's Quill list without discovery is uvim's model before #81: `k`'s ⌃A misfits and strikes nothing.
    for (text, keys) in ["one\ntwo\nthree", "one\n\nthree"].flatMap({ text in ["jjkk", "jjjkkk", "Gkk", "jj0k"].map { (text, $0) } }) {
        var slack = Sim(text: text, caret: 0, profile: keyProfile)
        slack.emptyParagraphs = true
        slack.quill = true
        slack.listLines = Array(repeating: Sim.ListLine(marker: "\u{2022}", inline: true), count: 3)
        slack.emulatesKeys = true
        slack.readModel = .textContent
        slack.findsUnreachable = false
        slack.learn(with: Sim.Learner(chromium: true, probed: keyProfile))
        var misfits = 0
        for key in keys {
            slack.type(String(key))
            misfits += slack.attribution.evidence.filter { $0.why == .misfit }.count
        }
        precondition(misfits > 0 && slack.blamed.isEmpty && slack.learner!.strikes.runs(.lineStartKey) == 0, "Slack's \(keys) in \(text)")
    }

    // With the model right and ⌃A really dead, `k` from mid-line still strikes it.
    var dead = Sim(text: "one\ntwo\nthree", caret: 10, profile: keyProfile)
    dead.emptyParagraphs = true
    dead.quill = true
    dead.listLines = Array(repeating: Sim.ListLine(marker: "\u{2022}", inline: true), count: 3)
    dead.emulatesKeys = true
    dead.readModel = .textContent
    dead.ignoredChords = [.paragraphStart]
    dead.type("k")
    precondition(dead.blamed == [.lineStartKey], "an unmoved key beside a marker it is not next to")
}
