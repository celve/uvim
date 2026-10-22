// MARK: - The learner's commit rule

let learnRung = "company.thebrowser.dia|app.notion.com|role:AXTextField"

// The store commits at once; `true` asks to persist and re-resolve.
let learnVersions = Versions(app: "1.49.1")

var passed = RunAttribution()

func learned(_ store: inout BeliefStore, _ strikes: inout Strikes, _ run: [Evidence], under offsets: OffsetsAnswer = .value,
             versions: Versions = learnVersions, overridden: Bool = false) -> Learning.Lesson {
    Learning.learn(
        store: &store, strikes: &strikes, rung: learnRung, versions: versions, model: ReadModel(answer: offsets),
        observed: Learning.Observation(before: offsets, source: .start), run: run, overridden: { _ in overridden },
        provenance: Provenance(), tally: Tally()
    )
}

var struck = RunAttribution()

func strikesAfter(_ runs: [(run: [Evidence], under: OffsetsAnswer, app: String)]) -> (Strikes, BeliefStore) {
    var store = BeliefStore()
    var strikes = Strikes()
    for item in runs { _ = learned(&store, &strikes, item.run, under: item.under, versions: Versions(app: item.app)) }
    return (strikes, store)
}

// LIN-1929: a text write that returned no error and left the field as the passing settle before it read it is off at once.
let beforeDelete = Expectation(selection: 4..<9, length: 15, selectedText: "hello")
let afterDelete = Expectation(selection: 4..<4, length: 10)
func deleted(_ selection: Range<Int>?, _ length: Int?, before: Expectation? = beforeDelete, after: Expectation = afterDelete,
             writeError: Int32? = nil) -> [Evidence] {
    var run = RunAttribution()
    run.record(.setSelection(4..<9))
    if let before { run.record(.settle(before), passed: true, selection: 4..<9, length: 15, selectedText: "hello") }
    run.record(.replaceSelection(""))
    run.record(.settle(after), passed: false, selection: selection, length: length, writeError: writeError)
    return run.evidence
}
func offAfter(_ run: [Evidence]) -> Int? {
    var store = BeliefStore()
    var strikes = Strikes()
    return (1...Strikes.limit).first { _ in learned(&store, &strikes, run).committed != nil }
}
let ignoredDelete = deleted(4..<9, 15)

var ignoredStore = BeliefStore()
var ignoredStrikes = Strikes()
let ignoredOnce = learned(&ignoredStore, &ignoredStrikes, ignoredDelete)

func testCommitRule() {
    // The learner writes at the ROLE learnRung, never the identifier rung: a key per
    // individual field would scatter the evidence so thinly its strikes in a row
    // would never add up.
    precondition(diaPageField.roleRung == "company.thebrowser.dia|app.notion.com|role:AXTextField")
    precondition(diaPageField.roleRung != diaPageField.rungs.first,
                 "the learner must not write at the identifier learnRung")
    precondition(diaChrome.roleRung == "company.thebrowser.dia|role:AXTextField")
    precondition(Surface(bundleID: "company.thebrowser.dia").roleRung == nil)   // no role: nothing to learn against
    precondition(Surface(role: "AXTextField").roleRung == nil)       // no app: likewise
    // The role learnRung is always a learnRung the ladder actually produces, or a demotion
    // would be written where no lookup could ever find it.
    precondition(diaPageField.rungs.contains(diaPageField.roleRung!))
    precondition(diaChrome.rungs.contains(diaChrome.roleRung!))

    let otherRung = "com.other.app|role:AXTextField"

    var trials = BeliefStore()
    precondition(committing(&trials, .insertText))
    precondition(!committing(&trials, .insertText) && !committing(&trials, .insertText))

    precondition(broken(trials) == [.insertText])

    passed.record(.replaceSelection(""))
    passed.record(.settle(Expectation(selection: 4..<4)), passed: true, selection: 4..<4)
    precondition(passed.evidence == [Evidence(.write(.insertText), .supports(nil), why: .settled, seen: .settle(1))])

    for start in [BeliefStore(), trials] {
        var store = start
        var strikes = Strikes()
        let lesson = learned(&store, &strikes, passed.evidence)
        precondition(store == start && !lesson.republish && lesson.committed == nil && strikes.isEmpty)
    }

    var perRung = BeliefStore()
    precondition(committing(&perRung, .insertText) && committing(&perRung, .writeSelection) && committing(&perRung, .insertText, at: otherRung))
    precondition(!committing(&perRung, .insertText) && !committing(&perRung, .insertText, at: otherRung))
    precondition(broken(perRung) == [.insertText, .writeSelection] && broken(perRung, rung: otherRung) == [.insertText])

    precondition(broken(perRung, versions: Versions(app: "1.50")).isEmpty)
    precondition(committing(&perRung, .writeSelection, versions: Versions(app: "1.50")))
    precondition(!perRung.beliefs.contains { $0.rung == learnRung && $0.appVersion == "1.49.1" })
    precondition(perRung.beliefs.contains { $0.rung == otherRung }, "other rungs keep theirs")

    struck.record(.setSelection(4..<9))
    struck.record(.settle(Expectation(selection: 4..<9)), passed: false, selection: 0..<0)
    precondition(struck.evidence == [Evidence(.write(.writeSelection), .refutes, why: .moved, seen: .settle(1))])
    var overruled = BeliefStore()
    var overruledStrikes = Strikes()
    precondition(learned(&overruled, &overruledStrikes, struck.evidence, overridden: true).skip == .userOverride
                 && overruled.beliefs.isEmpty && overruledStrikes.isEmpty)

    // LIN-1685: one refuted write leaves writes on; the third refuted run in a row switches them off.
    var struckStore = BeliefStore()
    var strikes = Strikes()
    for count in 1..<Strikes.limit {
        let lesson = learned(&struckStore, &strikes, struck.evidence)
        precondition(lesson.skip == .strike && lesson.strikes == count && lesson.committed == nil && !lesson.republish)
        precondition(struckStore.beliefs.isEmpty && strikes.runs(.writeSelection) == count)
    }
    let third = learned(&struckStore, &strikes, struck.evidence)
    precondition(third.committed == .writeSelection && third.strikes == Strikes.limit && third.republish)
    precondition(broken(struckStore) == [.writeSelection] && strikes.isEmpty)

    var wrote = RunAttribution()
    wrote.record(.setSelection(4..<9))
    wrote.record(.settle(Expectation(selection: 4..<9)), passed: true, selection: 4..<9)

    let miss = (run: struck.evidence, under: OffsetsAnswer.value, app: "1.49.1")
    let landedBetween = strikesAfter([miss, miss, (wrote.evidence, .value, "1.49.1"), miss])
    precondition(landedBetween.0.runs(.writeSelection) == 1 && landedBetween.1.beliefs.isEmpty, "a write that lands starts the count over")
    let otherPass = strikesAfter([miss, miss, (passed.evidence, .value, "1.49.1"), miss])
    precondition(otherPass.0.isEmpty && broken(otherPass.1) == [.writeSelection], "another write's pass does not")
    let reread = strikesAfter([miss, miss, (struck.evidence, .textContent, "1.49.1")])
    precondition(reread.0.runs(.writeSelection) == 1 && reread.1.beliefs.isEmpty, "a new offsets answer starts it over")
    let updated = strikesAfter([miss, miss, (struck.evidence, .value, "1.50")])
    precondition(updated.0.runs(.writeSelection) == 1 && updated.1.beliefs.isEmpty, "so does an app update")
    var appKeyStore = BeliefStore()
    var appKeyStrikes = Strikes()
    let appKeyMiss = Evidence(.key(.wordKeys), .refutes, why: .unmoved, seen: .settle(1))
    precondition(learned(&appKeyStore, &appKeyStrikes, [appKeyMiss]).committed == .wordKeys
                 && Strikes.limit(for: .paragraphKeys, why: .unmoved) == 1 && Strikes.limit(for: .lineEndKey, why: .unmoved) == 3,
                 "the opt-in app keys keep the one-miss rule")

    precondition(ignoredDelete.last == Evidence(.write(.insertText), .refutes, why: .unchanged, seen: .settle(3)))

    precondition(ignoredOnce.committed == .insertText && ignoredOnce.strikes == 1 && ignoredOnce.republish)
    precondition(broken(ignoredStore) == [.insertText] && ignoredStrikes.isEmpty)
    let keptThree: [(run: [Evidence], why: Evidence.Why)] = [
        (deleted(4..<9, 15, writeError: -25204), .length),
        (deleted(nil, 15), .unanswered),
        (deleted(4..<9, nil), .unanswered),
        (deleted(4..<9, 14), .length),
        (deleted(5..<9, 15), .length),
        (deleted(4..<9, 15, before: nil), .length),
        (deleted(4..<9, 15, before: Expectation(selection: 4..<9, selectedText: "hello")), .length),
        (deleted(4..<9, 15, after: Expectation(selection: 4..<4)), .moved),
        (deleted(4..<9, 15, after: Expectation(length: 10)), .length),
    ]
    for (index, item) in keptThree.enumerated() {
        precondition(item.run.last?.question == .write(.insertText) && item.run.last?.why == item.why, "case \(index)")
        precondition(offAfter(item.run) == Strikes.limit, "case \(index): any other failed text write keeps three")
    }
    var pressedBetween = RunAttribution()
    pressedBetween.record(.settle(beforeDelete), passed: true, selection: 4..<9, length: 15, selectedText: "hello")
    pressedBetween.record(.press(.left, count: 1))
    pressedBetween.record(.replaceSelection(""))
    pressedBetween.record(.settle(afterDelete), passed: false, selection: 4..<9, length: 15)
    precondition(pressedBetween.evidence.last?.why == .length && offAfter(pressedBetween.evidence) == Strikes.limit,
                 "only the settle straight before the write counts")
    var selectionStayed = RunAttribution()
    selectionStayed.record(.settle(Expectation(selection: 0..<0, length: 15)), passed: true, selection: 0..<0, length: 15)
    selectionStayed.record(.setSelection(4..<9))
    selectionStayed.record(.settle(Expectation(selection: 4..<9, length: 15)), passed: false, selection: 0..<0, length: 15)
    precondition(selectionStayed.evidence == [Evidence(.write(.writeSelection), .refutes, why: .moved, seen: .settle(2))])
    precondition(offAfter(selectionStayed.evidence) == Strikes.limit, "a selection write that changed nothing keeps three")
    precondition(offAfter([Evidence(.key(.lineEndKey), .refutes, why: .unmoved, seen: .settle(1))]) == Strikes.limit,
                 "so does a key")
    precondition(Strikes.limit(for: .writeSelection, why: .unchanged) == Strikes.limit)
}

// MARK: - Failed checks that blame nothing (LIN-1979)

func corrected(_ expectation: Expectation, passed: Bool, read: Range<Int>) -> [Evidence] {
    var run = RunAttribution()
    run.record(.setSelection(13..<18))
    run.record(.press(.selectLeft, count: 1))
    run.record(.settle(expectation), passed: passed, selection: read, length: 22)
    return run.evidence
}

func selecting(_ plan: PhysicalPlan) -> [Bool] {
    plan.steps.compactMap { if case .settle(let expectation) = $0 { expectation.blame?.selects } else { nil } }
}

func testBlamelessFailures() {
    // `D` as logged in Lark: the write, the ⇧← that brings it back from the paragraph's end, and an end read two short.
    let loggedD = checkingWrite(Expectation(selection: 13..<18, length: 22, edge: .paragraphEnd))

    precondition(corrected(loggedD, passed: false, read: 13..<16)
                 == [Evidence(.write(.writeSelection), .refutes, why: .moved, seen: .settle(2))])
    precondition(offAfter(corrected(loggedD, passed: false, read: 13..<16)) == Strikes.limit)
    precondition(corrected(loggedD, passed: true, read: 13..<18)
                 == [Evidence(.write(.writeSelection), .supports(nil), why: .settled, seen: .settle(2))])
    var unmarkedD = loggedD
    unmarkedD.checksWrite = false
    precondition(corrected(unmarkedD, passed: false, read: 13..<16).isEmpty)
    var settledBetween = RunAttribution()
    settledBetween.record(.setSelection(13..<18))
    settledBetween.record(.settle(Expectation(selection: 13..<18, length: 22)), passed: true, selection: 13..<18, length: 22)
    settledBetween.record(.press(.selectLeft, count: 1))
    settledBetween.record(.settle(loggedD), passed: false, selection: 13..<16, length: 22)
    precondition(settledBetween.evidence.count == 1 && settledBetween.evidence[0].outcome == .supports(nil),
                 "keys after a settle finish no write")
    precondition(dia1D.steps.allSatisfy { if case .settle(let expectation) = $0 { !expectation.checksWrite } else { true } },
                 "a folded write's keys leave the write unchecked")
    var ignoresWrites = chromiumSim("one two\nthree", caret: 4, profile: axProfile, markers: true, chromium: true)
    ignoresWrites.swallowsSelect = true
    for count in 1...Strikes.limit {
        ignoresWrites.type("D")
        let lesson = ignoresWrites.learner!.lessons.last!
        precondition(lesson.refuted?.question == .write(.writeSelection) && lesson.refuted?.why == .moved && lesson.strikes == count)
    }
    precondition(!ignoresWrites.profile.has(.writeSelection) && ignoresWrites.text == "one two\nthree")

    let caretLeft = Expectation(landing: .exact(4..<7), blame: Expectation.Blame(
        capability: .lineEndKey, unmoved: [4..<4], selects: true, exemptions: [.init(.paragraphLines, offTarget: true)]))
    precondition(judged(caretLeft, 7..<7) == key(.lineEndKey, .refutes, .leftCaret) && caretLeft.blamed(observed: 7..<7) == .lineEndKey)
    precondition(judged(caretLeft, 4..<4) == key(.lineEndKey, .refutes, .unmoved))
    precondition(judged(caretLeft, 4..<6) == key(.lineEndKey, .neutral, .paragraphLines), "a selection off target")
    precondition(Evidence.Why.leftCaret.rawValue == "left-caret")

    precondition(selecting(webPhysical("dd", text: "ab\ncdef", caret: 4, profile: keyProfile, breaks: chromiumBreak)) == [false, true])
    precondition(selecting(webPhysical("dd", text: "ab\n\ncd", caret: 3, profile: keyProfile, breaks: ParagraphBreaks(offsets: [2, 3])))
                 == [false, false], "an empty line has nothing to select")
    precondition(selecting(PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand("d0"), state: .initial), snapshot: FieldSnapshot(
        capabilities: keyProfile, text: "ab\ncdef", selection: 2..<2, webContent: true, breaks: ParagraphBreaks(offsets: []),
        caretInEmptyParagraph: true
    ))) == [false], "from a caret in an empty paragraph")
    var proseMirror = chromiumSim("one\ntwo\nthree", caret: 5, profile: keyProfile, markers: true, chromium: true)
    proseMirror.reboundChords = [Chord.paragraphEnd.shifted: .paragraphEnd, Chord.paragraphStart.shifted: .paragraphStart]
    for count in 1...Strikes.limit {
        proseMirror.type("dd")
        let lesson = proseMirror.learner!.lessons.last!
        precondition(lesson.refuted?.question == .key(.lineEndKey) && lesson.refuted?.why == .leftCaret && lesson.strikes == count)
    }
    precondition(!proseMirror.profile.has(.lineEndKey) && proseMirror.text == "one\ntwo\nthree")
    proseMirror.type("dd")
    precondition(proseMirror.text == "one\nthree" && proseMirror.settleFailures == Strikes.limit, "then counted ⇧→ select the line")

    let afterBackspace = deleting(Expectation(selection: 4..<4, length: 10), 4..<9, before: 15)
    precondition(afterBackspace.ignored(selection: 4..<9, length: 15) && afterBackspace.ignored(selection: 4..<9, length: nil))
    precondition(deleting(Expectation(selection: 4..<4), 4..<9, before: nil).ignored(selection: 4..<9, length: 14))
    precondition(!afterBackspace.ignored(selection: 4..<9, length: 14) && !afterBackspace.ignored(selection: 4..<8, length: 15))
    precondition(!afterBackspace.ignored(selection: 4..<4, length: 15) && !afterBackspace.ignored(selection: nil, length: 15))
    precondition(!deleting(Expectation(selection: 4..<4), 4..<4, before: 15).ignored(selection: 4..<4, length: 15),
                 "paragraph breaks alone read as a caret either way")
    precondition(!Expectation(selection: 4..<4, length: 10).ignored(selection: 4..<9, length: 15))
    precondition(!physical("ciw", text: "say hello world", caret: 6, profile: noCursorProfile).steps.contains {
        if case .settle(let expectation) = $0 { expectation.deletes != nil } else { false }
    }, "a text write keeps its own rule")
    var ignoresBackspace = Sim(text: "one\ntwo", caret: 5, profile: readProfile)
    ignoresBackspace.ignoredChords = [.deleteBack]
    ignoresBackspace.type("dd")
    precondition(ignoresBackspace.text == "one\ntwo" && ignoresBackspace.settleFailures == 1 && ignoresBackspace.softMisses == 0)
    precondition(ignoresBackspace.state.session.register("\"") == nil && ignoresBackspace.selection.isEmpty)
    var changeIgnored = Sim(text: "one two", caret: 5, profile: readProfile)
    changeIgnored.ignoredChords = [.deleteBack]
    changeIgnored.type("ciwX")
    precondition(changeIgnored.text == "one X" && changeIgnored.settleFailures == 1, "typing replaces the operand left selected")
    var collapsedOnly = Sim(text: "one two", caret: 5, profile: readProfile)
    collapsedOnly.reboundChords = [.deleteBack: .left]
    collapsedOnly.type("x")
    precondition(collapsedOnly.text == "one two" && collapsedOnly.softMisses == 1 && collapsedOnly.settleFailures == 0)
    // A Visual selection deleted where the selected text cannot be read has no settle before its ⌫.
    let unreadText = CapabilityProfile(available: [.readText, .readLength, .readCaret, .wholeDocument])
    for (keys, after) in [("vld", "one\ntwo"), ("vlcX", "Xne\ntwo")] {
        var visual = Sim(text: "one\ntwo", caret: 0, profile: unreadText)
        visual.emulatesKeys = true
        visual.ignoredChords = [.deleteBack]
        visual.type(keys)
        precondition(visual.text == after && visual.settleFailures == 1 && visual.softMisses == 0, keys)
        precondition(visual.state.session.register("\"") == nil, keys)
    }
}
