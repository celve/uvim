// MARK: - Generated text (LIN-1930)

final class ShownNode {
    let role: String
    let id: Int?
    let value: String?
    let children: [ShownNode]
    var fails = false

    init(_ role: String, _ id: Int?, _ value: String? = nil, _ children: [ShownNode] = []) {
        self.role = role
        self.id = id
        self.value = value
        self.children = children
    }

    var read: GeneratedTextScan<ShownNode>.Read? {
        fails ? nil : .init(role: role, generated: id.map { $0 < 0 } == true, value: value, children: children)
    }
}
func shownScan(_ roots: [ShownNode], budget: Int = GeneratedText.readBudget) -> (texts: [String]?, reads: Int) {
    var scan = GeneratedTextScan<ShownNode>(budget: budget, read: \.read)
    return (scan.run(roots: roots), scan.reads)
}

// ChatGPT's box on Dia 1.51.1 as probed: every capability but the seeded-off native motions.
let chatProfile = CapabilityProfile(available: Set(Capability.allCases).subtracting([.nativeMotions]))
func chatBox(_ text: String = "", caret: Int = 0, reads placeholderCaret: Int = 0,
             profile: CapabilityProfile = chatProfile) -> Sim {
    var host = chromiumSim(text, caret: caret, profile: profile, markers: true, chromium: true)
    host.placeholder = "Ask anything"
    host.placeholderCaret = placeholderCaret
    host.refocus(.newSession)
    return host
}

func testGeneratedText() {
    // Dia 1.51.1's trees: ChatGPT's empty box, then local pages' editors (softlash/LIN-1930 docs/generated-text.md).
    let chatGPTEmpty = [ShownNode("AXGroup", 33, nil, [ShownNode("AXStaticText", -1000000006, "Ask anything")])]
    precondition(shownScan(chatGPTEmpty) == (["Ask anything"], 2))
    precondition(GeneratedText.fills("Ask anything", with: ["Ask anything"]))
    let pseudoGroup = [ShownNode("AXGroup", 33, nil, [ShownNode("AXGroup", 1, nil, [ShownNode("AXStaticText", -2, "Ask anything")])])]
    precondition(shownScan(pseudoGroup).texts == ["Ask anything"], "the ::before element itself has a node")
    precondition(GeneratedText.fills("Ask anything\n", with: ["Ask anything"]), "an empty paragraph's <br> adds a \\n")
    precondition(!GeneratedText.fills("\nAsk anything\n", with: ["Ask anything"]) && !GeneratedText.fills("Ask anything\n\n", with: ["Ask anything"]),
                 "two empty paragraphs read as before")
    let quillEmpty = [ShownNode("AXGroup", 5, nil, [ShownNode("AXStaticText", -12, "Message #general")]), ShownNode("AXGroup", 37)]
    precondition(shownScan(quillEmpty) == (["Message #general"], 3))
    precondition(shownScan([ShownNode("AXStaticText", -14, "Type '/' for commands")]) == (["Type '/' for commands"], 1))
    precondition(shownScan([ShownNode("AXGroup", 35, nil, [ShownNode("AXStaticText", 3, "sdf")])]) == (nil, 2),
                 "the page's own text ends the scan at once")
    let markerItem = ShownNode("AXGroup", 47, nil, [ShownNode("AXListMarker", 13, "\u{2022} ")])
    precondition(shownScan([ShownNode("AXList", 46, nil, [markerItem])]).texts == nil, "Chromium's own marker reads as it does")
    let decorated = [ShownNode("AXGroup", 49, nil, [ShownNode("AXStaticText", 15, "real text"), ShownNode("AXStaticText", -9, " \u{21B5}")])]
    precondition(shownScan(decorated).texts == nil)
    let countedHeading = [ShownNode("AXHeading", 56, nil, [ShownNode("AXStaticText", -11, "\u{00A7}"), ShownNode("AXStaticText", 22, "Heading")])]
    precondition(shownScan(countedHeading) == (nil, 3), "generated text beside the page's own keeps the field's text")
    precondition(shownScan([ShownNode("AXGroup", 1, nil, [ShownNode("AXStaticText", nil, "Ask anything")])]).texts == nil,
                 "a text without a node id is the page's")
    chatGPTEmpty[0].fails = true
    precondition(shownScan(chatGPTEmpty).texts == nil, "a failed read fails the scan")
    chatGPTEmpty[0].fails = false
    let deep = (0..<20).reduce(ShownNode("AXStaticText", -1, "x")) { inner, depth in ShownNode("AXGroup", depth + 1, nil, [inner]) }
    precondition(shownScan([deep]).texts == nil && shownScan([deep], budget: 21).texts == ["x"])
    precondition(!GeneratedText.fills("Ask anything else", with: ["Ask anything"]) && !GeneratedText.fills("\n", with: [])
                 && !GeneratedText.fills("Ask anything", with: []))

    let placeholderRaw = FieldReads(text: "Ask anything", plain: 11..<11, selectedText: "")
    for (answer, markers) in [(OffsetsAnswer.textContent, true), (.value, false), (.untrusted, true)] {
        let reads = FieldSnapshot.Reads(generatedOnly: placeholderRaw, length: 12, webContent: true, blocks: 1, markers: markers)
        let built = FieldSnapshot.Step.run(taking: { preconditionFailure("an empty field needs no read: \($0)") }) {
            FieldSnapshot.build(reads, capabilities: axProfile, answer: answer, anchor: nil, cursor: nil, memo: nil)
        }
        let breaks = answer == .textContent ? ParagraphBreaks() : nil
        precondition(built.snapshot == FieldSnapshot(capabilities: axProfile, text: "", selection: answer == .untrusted ? nil : 0..<0,
                                                     length: 0, webContent: true, breaks: breaks), "\(answer)")
        precondition(Learning.observe(reads.field, before: answer, source: .start, newEngine: false).after == answer)
    }

    precondition(Expectation(selection: 0..<0, length: 0).metByEmptyField && Expectation(landing: nil, length: 0).metByEmptyField)
    precondition(Expectation(landing: .caretBefore(5, strict: true), length: 0).metByEmptyField)
    precondition(!Expectation(selection: 0..<12, length: 12).metByEmptyField && !Expectation(selection: 0..<0).metByEmptyField)
    precondition(!Expectation(selection: 0..<0, length: 0, edge: .paragraphStart).metByEmptyField)
    precondition(!Expectation(landing: .caretAfter(0, strict: true), length: 0).metByEmptyField)

    // Polls whose reads stay put while the field turns: a put landing as long as the placeholder, a box emptying under its caret.
    let putCheck = Expectation(landing: nil, length: 12)
    let emptyingCheck = Expectation(selection: 0..<0, length: 0)
    func passing(_ check: Expectation, length: Int, selection: Range<Int>? = 0..<0, answered: Bool = true, generated: Bool,
                 scan: () -> Bool) -> Bool {
        check.passes(selection: selection, length: length, selectedText: nil, side: nil, answered: answered, generated: generated,
                     showsOnlyGeneratedText: scan)
    }
    for (check, generated, scans) in [(putCheck, true, [true, false, false]), (emptyingCheck, false, [false, true, true])] {
        var scanned = scans.makeIterator()
        let verdicts = scans.map { _ in passing(check, length: 12, generated: generated) { scanned.next()! } }
        precondition(verdicts == [false, true, true], "\(check.traceFields)")
    }
    var scanned = false
    precondition(passing(putCheck, length: 12, generated: false) { scanned = true; return true } && !scanned)
    precondition(!passing(putCheck, length: 0, generated: true) { scanned = true; return true } && !scanned)
    precondition(!passing(emptyingCheck, length: 12, selection: nil, answered: false, generated: true) { scanned = true; return true }
                 && !scanned)
    precondition(passing(emptyingCheck, length: 0, generated: true) { scanned = true; return false } && !scanned)

    for placeholderCaret in [0, 11, 12] {
        var empty = chatBox(reads: placeholderCaret)
        precondition(empty.state.field.mode == .insert)
        empty.feed("<C-[>")
        for keys in ["dd", "dd", "dd", "dd", "dd", "dd", "dd", "0", "$", "a", "<C-[>", "x", "D", "gg", "G"] {
            if keys == "<C-[>" { empty.feed(keys) } else { empty.type(keys) }
            precondition(empty.bells == 0 && empty.settleFailures == 0 && empty.softMisses == 0 && empty.unsupportedSteps == 0,
                         "\(keys) with the caret read at \(placeholderCaret)")
        }
        precondition(empty.text.isEmpty && empty.state.field.mode == .normal)
        precondition(empty.learner!.lessons.allSatisfy { $0.refuted == nil && $0.move == nil && !$0.recorded })
        precondition(empty.learner!.store.beliefs.isEmpty, "no belief behind")
    }
    var emptiedBox = chatBox("sdf", profile: removing([.insertText], from: chatProfile))
    emptiedBox.feed("<C-[>")
    emptiedBox.type("dd")
    precondition(emptiedBox.text.isEmpty && emptiedBox.showsPlaceholder && emptiedBox.settleFailures == 0)
    precondition(emptiedBox.softMisses == 0, "the dd that empties the box misses no check")
    // A line as long as the placeholder, put into the empty box: a write Chromium ignores leaves the length a put would.
    var yanked = Sim(text: "abcdefghijk", caret: 0, profile: chatProfile)
    yanked.type("yy")
    for swallows in [true, false] {
        var put = Sim(text: "", caret: 0, state: yanked.state, profile: chatProfile)
        put.reads = omitsBreaks
        put.writesInReadOffsets = true
        put.markers = true
        put.emulatesKeys = true
        put.learn(with: Sim.Learner(chromium: true, probed: chatProfile))
        put.placeholder = "Ask anything"
        put.swallowsReplace = swallows
        put.type("P")
        precondition(put.settleFailures == (swallows ? 1 : 0) && put.text == (swallows ? "" : "abcdefghijk\n"), "swallowed \(swallows)")
    }
    // Once a check finds the box empty, the next one looks for its placeholder too: a `.` of `cc` plans this.
    var emptiedThenPut = Sim(text: "", caret: 0, profile: chatProfile)
    emptiedThenPut.placeholder = "Ask anything"
    emptiedThenPut.swallowsReplace = true
    precondition(!emptiedThenPut.perform([
        .settle(Expectation(selection: 0..<0, length: 0)), .replaceSelection("abcdefghijkl"), .settle(Expectation(landing: nil, length: 12)),
    ]))
    var stuck = chatBox("x", profile: removing([.insertText], from: chatProfile))
    stuck.ignoredChords = [.deleteBack]
    stuck.feed("<C-[>")
    stuck.type("x")
    precondition(stuck.text == "x" && stuck.settleFailures == 1 && stuck.softMisses == 0, "the page's own text still fails")
}
