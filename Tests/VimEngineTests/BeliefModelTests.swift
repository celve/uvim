// MARK: - The belief model

let supportsValue = Evidence.offsets(.supports(.value), .plainIsValue)
let supportsTextContent = Evidence.offsets(.supports(.textContent), .plainIsTextContent)

func resolving(_ store: BeliefStore, starting: OffsetsAnswer = .value, versions: Versions = learnVersions,
               pins: Bool = false, children: Bool = true) -> ResolvedBeliefs {
    store.resolve(rungs: diaPageField.rungs, rung: learnRung, versions: versions, chromium: starting == .textContent,
                  children: children, userPinsOffsets: pins)
}

func lesson(_ store: inout BeliefStore, model: ReadModel, snapshot: (OffsetsAnswer, Evidence?, OffsetsAnswer),
            source: OffsetsSource = .start, run: [Evidence] = []) -> Learning.Lesson {
    let observed = Learning.Observation(before: snapshot.0, source: source, evidence: snapshot.1, after: snapshot.2)
    var strikes = Strikes()
    return Learning.learn(store: &store, strikes: &strikes, rung: learnRung, versions: learnVersions, model: model,
                          observed: observed, run: run, overridden: { _ in false }, provenance: Provenance(tag: "e2.c5"),
                          tally: Tally())
}

func writeStrike(_ expectation: Expectation, selection: Range<Int>?, length: Int?) -> Evidence.Why? {
    var run = RunAttribution()
    run.record(.replaceSelection("x"))
    run.record(.settle(expectation), passed: false, selection: selection, length: length)
    return run.evidence.first?.why
}

// The resolver's table before beliefs, which it must still match.
func previousTable(probed: CapabilityProfile, config: [Capability: ConfigChoice], learned: Set<Capability>)
    -> [Capability: CapabilityReport.Entry] {
    var entries: [Capability: CapabilityReport.Entry] = [:]
    for capability in Capability.allCases where capability.species == .mechanism {
        let choice = config[capability]?.override
        if probed.has(capability), choice == .off {
            entries[capability] = .init(status: .unavailable, source: .user)
        } else if probed.has(capability), learned.contains(capability), choice != .on {
            entries[capability] = .init(status: .unavailable, source: .learned)
        } else {
            entries[capability] = .init(status: probed.has(capability) ? .available : .unavailable, source: .probed)
        }
    }
    for capability in Capability.allCases where capability.species == .policy {
        let mechanism = capability.parent.map { entries[$0] ?? .init(status: .unavailable, source: .probed) }
        let choice = config[capability] ?? ConfigChoice()
        if let mechanism, mechanism.status != .available {
            entries[capability] = .init(status: .unavailable, source: mechanism.source)
        } else if choice.override == .off {
            entries[capability] = .init(status: .unavailable, source: .user)
        } else if choice.seededOff, choice.override != .on {
            entries[capability] = .init(status: .unavailable, source: .seeded)
        } else {
            entries[capability] = .init(status: .available, source: choice.override == .on ? .user : .probed)
        }
    }
    return entries
}
var draw: UInt64 = 0x9E37_79B9_7F4A_7C15
func coin(_ sides: UInt64) -> UInt64 {
    draw ^= draw << 13
    draw ^= draw >> 7
    draw ^= draw << 17
    return draw % sides
}

// The focus rule before enclosing fields, which it must still match where no field names one.
func previousEdge(_ old: Focus?, _ new: Focus?) -> FocusTransition {
    guard let old, let new else { return .newSession }
    if old.forcedWindow != nil || new.forcedWindow != nil {
        return old.forcedWindow != nil && new.forcedWindow != nil && old.pid == new.pid && old.forcedWindow == new.forcedWindow
            ? .sameElement
            : .newSession
    }
    if old.element == new.element { return .sameElement }
    guard old.session?.status == .unavailable, new.session?.status == .unavailable, old.pid == new.pid, old.site == new.site,
          let oldWindow = old.window, let newWindow = new.window, oldWindow == newWindow else { return .newSession }
    return .sameDocument
}
func randomFocus(enclosing: Bool) -> Focus? {
    if coin(12) == 0 { return nil }
    let pid = Int32(coin(2))
    if coin(6) == 0 { return Focus(element: 0, pid: pid, site: "", forcedWindow: UInt32(coin(2))) }
    let page: Int? = enclosing && coin(2) == 0 ? 100 + Int(coin(2)) : nil
    // `main` denied `fieldIsSession` by a seed or the user only; the page's answer is new.
    let session = [onByDefault, onByUser, offBySeed, offByUser, offByPage][Int(coin(enclosing ? 5 : 4))]
    let window: Int? = FocusTransition.windowIsDocument(session) && coin(4) != 0 ? 7 + Int(coin(2)) : nil
    return Focus(
        element: coin(3) == 0 ? 100 + Int(coin(2)) : Int(coin(4)), pid: pid, site: ["AXTextArea", "AXTextField"][Int(coin(2))],
        session: session, enclosing: page, window: window
    )
}

func testBeliefModel() {
    for answer in OffsetsAnswer.allCases {
        for newEngine in [false, true] {
            precondition(answer.next(.neutral, newEngine: newEngine) == answer)
            precondition(answer.next(.refutes, newEngine: newEngine) == .untrusted)
            precondition(answer.next(supportsTextContent.outcome, newEngine: newEngine) == .textContent, "textContent fits again from \(answer)")
        }
        precondition(answer.next(supportsValue.outcome, newEngine: true) == .value)
    }
    precondition(OffsetsAnswer.value.next(supportsValue.outcome, newEngine: false) == .value)
    precondition(OffsetsAnswer.textContent.next(supportsValue.outcome, newEngine: false) == .untrusted, "value needs a new engine")
    precondition(OffsetsAnswer.untrusted.next(supportsValue.outcome, newEngine: false) == .untrusted)

    // In "ab\ncd" a caret before `d` is 4 in `AXValue` and 3 without the break.
    let beforeD = MarkerReads(breaks: ParagraphBreaks(offsets: [2]), value: 4..<4)
    precondition(FieldReads(text: "ab\ncd", plain: 3..<3, markers: beforeD).evidence(current: .value) == supportsTextContent)
    precondition(FieldReads(text: "ab\ncd", plain: 4..<4, markers: beforeD).evidence(current: .textContent) == supportsValue)
    precondition(FieldReads(text: "ab\ncd", plain: 0..<0, markers: beforeD).evidence(current: .textContent) == .offsets(.neutral, .boundarySnap))
    precondition(FieldReads(text: "ab\ncd", plain: 1..<1, markers: MarkerReads(breaks: ParagraphBreaks(offsets: [2]), value: 1..<1))
        .evidence(current: .value) == .offsets(.neutral, .noBreaks))
    precondition(FieldReads(text: "ab\ncd", plain: 3..<3).evidence(current: .value) == nil, "a caret without markers compares nothing")
    precondition(FieldReads(text: "ab\ncd", plain: 3..<3, markers: MarkerReads(breaks: nil, value: nil)).evidence(current: .textContent) == nil)
    // A list marker the side read skips is no break.
    let listItem = ParagraphBreaks(value: "• ab\n• cd", fieldText: "• ab• cd")!
    precondition(FieldReads(text: "• ab\n• cd", plain: 6..<6, markers: MarkerReads(breaks: listItem, value: 7..<7))
        .evidence(current: .textContent) == supportsTextContent)

    let cd = MarkerReads(breaks: ParagraphBreaks(offsets: [2]), value: 3..<5)
    precondition(FieldReads(text: "ab\ncd", plain: 2..<4, selectedText: "cd", markers: cd).evidence(current: .value) == supportsTextContent)
    precondition(FieldReads(text: "ab\ncd", plain: 2..<4, selectedText: "cd").selectedTextEvidence(current: .value) == .offsets(.refutes, .selectedText),
                 "with value the only candidate, a mismatch fits nothing")
    precondition(FieldReads(text: "ab\ncd", plain: 2..<4, selectedText: "cd").selectedTextEvidence(current: .textContent) == .offsets(.neutral, .unaligned))
    precondition(FieldReads(text: "ab\ncd", plain: 3..<5, selectedText: "cd").selectedTextEvidence(current: .value) == .offsets(.neutral, .textAgrees))
    precondition(FieldReads(text: "ab\ncd", plain: 3..<5, selectedText: "c\u{FFFC}d").selectedTextEvidence(current: .value) == .offsets(.neutral, .textAgrees),
                 "Chromium's U+FFFC for a leaf with no text is no disagreement")
    precondition(FieldReads(text: "ab\nab", plain: 2..<4, selectedText: "\na", markers: MarkerReads(breaks: ParagraphBreaks(offsets: [2]), value: 3..<5))
        .evidence(current: .textContent) == .offsets(.refutes, .readsDisagree))
    precondition(FieldReads(text: "ab\ncd", plain: 2..<4, selectedText: "zz", markers: cd).evidence(current: .textContent) == .offsets(.refutes, .selectedText),
                 "a selected-text misfit outranks the offsets")
    precondition(FieldReads(text: "ab", plain: 0..<1, selectedText: "a", markers: MarkerReads(breaks: nil, value: nil))
        .interpreted(under: .textContent) == (nil, ParagraphBreaks(), false, false))
    precondition(FieldReads(text: "ab", plain: 0..<1).interpreted(under: .untrusted) == (nil, nil, false, false))

    var sampling = OffsetsSampling()
    precondition(!sampling.samples(text: "ab", plain: 1..<1) && !sampling.samples(text: "ab\ncd", plain: nil))
    precondition(!sampling.samples(text: "ab\ncd", plain: 1..<1), "a plain read before the first newline is paragraph 1's under any count")
    precondition(sampling.samples(text: "ab\ncd", plain: 2..<2) && sampling.samples(text: "ab\ncd", plain: 0..<2))
    sampling.sampled(markers: true, evidence: .offsets(.neutral, .noBreaks), text: "ab\ncd", plain: 0..<2)
    precondition(sampling.remaining == OffsetsSampling.budget, "a silence at paragraph 1's end costs nothing")
    for _ in 1..<OffsetsSampling.budget {
        sampling.sampled(markers: true, evidence: .offsets(.neutral, .noBreaks), text: "ab\ncd", plain: 3..<3)
        precondition(sampling.samples(text: "ab\ncd", plain: 3..<3))
    }
    sampling.sampled(markers: true, evidence: nil, text: "ab\ncd", plain: 4..<4)
    precondition(!sampling.samples(text: "ab\ncd", plain: 3..<3))
    var informed = OffsetsSampling()
    informed.sampled(markers: true, evidence: supportsValue, text: nil, plain: nil)
    var markerless = OffsetsSampling()
    markerless.sampled(markers: false, evidence: nil, text: nil, plain: nil)
    precondition(!informed.samples(text: "ab\ncd", plain: 3..<3) && !markerless.samples(text: "ab\ncd", plain: 3..<3))

    var dependent = BeliefStore()
    precondition(committing(&dependent, .writeSelection))
    precondition(resolving(dependent).broken == [.writeSelection] && resolving(dependent).reopened.isEmpty)
    let reopenedAtStart = resolving(dependent, starting: .textContent)
    precondition(reopenedAtStart.broken.isEmpty && reopenedAtStart.reopened.map(\.question) == [.write(.writeSelection)])
    precondition(dependent.record(offsets: .textContent, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    let learnedTextContent = resolving(dependent)
    precondition(learnedTextContent.readModel.answer == .textContent && learnedTextContent.readModel.source == .learned)
    precondition(learnedTextContent.broken.isEmpty, "a verdict judged under value reopens when its rung learns textContent")
    precondition(committing(&dependent, .writeSelection, under: .textContent), "a new strike re-judges it under the answer in force")
    precondition(resolving(dependent).broken == [.writeSelection])
    precondition(dependent.record(offsets: .untrusted, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    precondition(resolving(dependent).broken.isEmpty && resolving(dependent).reopened.map(\.question) == [.write(.writeSelection)],
                 "any change of the offsets answer reopens what the old one judged")
    var judgedUntrusted = dependent
    precondition(committing(&judgedUntrusted, .writeSelection, under: .untrusted) && resolving(judgedUntrusted).broken == [.writeSelection])
    precondition(!dependent.record(offsets: .untrusted, at: learnRung, versions: learnVersions, provenance: Provenance(tag: "e9.c9"), tally: Tally()))
    precondition(dependent.offsetsBelief(at: learnRung)?.provenance.tag == nil, "a read model that stood is not rewritten")

    let upgraded = resolving(dependent, versions: Versions(app: learnVersions.app, engine: "42"))
    precondition(upgraded.readModel.answer == .value && upgraded.readModel.source == .start && upgraded.readModel.newEngine)
    let pinned = resolving(dependent, starting: .textContent, pins: true)
    precondition(pinned.readModel.answer == .textContent && pinned.readModel.source == .user)
    precondition(dependent.forget(.offsets, at: learnRung) && resolving(dependent).readModel.source == .start)

    var anchored = BeliefStore()
    precondition(anchored.record(offsets: .textContent, at: learnRung, anchor: true, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    precondition(resolving(anchored).readModel == ReadModel(answer: .value, belief: anchored.offsetsBelief(at: learnRung)))
    precondition(resolving(anchored, starting: .textContent).readModel.answer == .textContent)
    precondition(resolving(anchored, versions: Versions(app: "1.50")).readModel.newEngine)

    var richSibling = BeliefStore()
    precondition(richSibling.record(offsets: .untrusted, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    let textareaBeside = resolving(richSibling, children: false)
    precondition(textareaBeside.readModel.answer == .value && textareaBeside.readModel.source == .plain
                 && textareaBeside.readModel.learned == .untrusted)
    precondition(textareaBeside.traceLines.last?.hasSuffix(" not-this-field") == true)
    precondition(CapabilityResolver.resolve(probed: axProfile, config: [:], beliefs: textareaBeside).profile.has(.readCaret))
    precondition(ReadModel(answer: .value, learned: .textContent).reading(chromium: true, children: false) == (.value, .plain))
    precondition(ReadModel(answer: .value, learned: .textContent).reading(chromium: false, children: true) == (.textContent, .learned))
    precondition(ReadModel(answer: .value, pinned: true).reading(chromium: true, children: true) == (.textContent, .user))

    let migrated = BeliefStore(demotions: [(learnRung, "1.49.1", "writeSelection"), (learnRung, "1.49.1", "noSuchAtom")])
    precondition(migrated.beliefs.count == 1 && migrated.beliefs[0].judgedUnder == .value && migrated.beliefs[0].provenance.tag == "migrated")
    precondition(resolving(migrated).broken == [.writeSelection] && resolving(migrated, starting: .textContent).broken.isEmpty)

    var observed = BeliefStore()
    let moved = lesson(&observed, model: ReadModel(answer: .value), snapshot: (.value, supportsTextContent, .textContent))
    precondition(moved.move == Learning.Move(from: .value, to: .textContent, why: .plainIsTextContent) && moved.recorded && moved.republish)
    precondition(observed.offsetsBelief(at: learnRung)?.provenance.tag == "e2.c5")
    var confirming = BeliefStore()
    let dated = lesson(&confirming, model: ReadModel(answer: .textContent), snapshot: (.textContent, supportsTextContent, .textContent))
    precondition(dated.move == nil && dated.recorded && dated.republish && confirming.offsetsBelief(at: learnRung)?.anchor == true)
    let againDated = lesson(&confirming, model: ReadModel(answer: .textContent, belief: confirming.offsetsBelief(at: learnRung)),
                            snapshot: (.textContent, supportsTextContent, .textContent))
    precondition(!againDated.recorded && !againDated.republish)
    var valueConfirmed = BeliefStore()
    precondition(!lesson(&valueConfirmed, model: ReadModel(answer: .value), snapshot: (.value, supportsValue, .value)).recorded
                 && valueConfirmed.beliefs.isEmpty, "value needs no date")
    var textChecked = RunAttribution()
    textChecked.record(.setSelection(0..<4))
    textChecked.record(.settle(Expectation(selection: 0..<4, length: 7, selectedText: "one\n")), passed: false,
                       selection: 0..<4, length: 7, selectedText: "two\n")
    precondition(textChecked.evidence == [.offsets(.refutes, .textCheck, seen: .settle(1))], "the offsets answer for a text mismatch, not the write")
    var mismatched = BeliefStore()
    let charged = lesson(&mismatched, model: ReadModel(answer: .value), snapshot: (.value, nil, .value), run: textChecked.evidence)
    precondition(charged.move == Learning.Move(from: .value, to: .untrusted, why: .textCheck) && charged.committed == nil)
    var userPinned = BeliefStore()
    precondition(lesson(&userPinned, model: ReadModel(answer: .value, source: .user, pinned: true), snapshot: (.value, nil, .value),
                        source: .user, run: textChecked.evidence).move == nil && userPinned.beliefs.isEmpty, "a user override pins the answer")
    var plainField = BeliefStore()
    precondition(lesson(&plainField, model: ReadModel(answer: .value, source: .plain), snapshot: (.value, nil, .value),
                        source: .plain, run: textChecked.evidence).move == nil && plainField.beliefs.isEmpty,
                 "a field with no children has no breaks to learn about")
    var wrongRange = RunAttribution()
    wrongRange.record(.setSelection(0..<4))
    wrongRange.record(.settle(Expectation(selection: 0..<4, length: 7, selectedText: "one\n")), passed: false,
                      selection: 1..<5, length: 7, selectedText: "ne\nt")
    precondition(wrongRange.evidence == [Evidence(.write(.writeSelection), .refutes, why: .moved, seen: .settle(1))])
    var unanswered = RunAttribution()
    unanswered.record(.setSelection(0..<4))
    unanswered.record(.settle(Expectation(selection: 0..<4, length: 7, selectedText: "one\n")), passed: false,
                      selection: 0..<4, length: 7, selectedText: nil)
    precondition(unanswered.evidence.isEmpty)
    var sideOnly = RunAttribution()
    sideOnly.record(.settle(Expectation(selection: 0..<4, length: 7, edge: .paragraphEnd, selectedText: "one")), passed: false,
                    selection: 0..<4, length: 7, selectedText: "one")
    precondition(sideOnly.evidence.isEmpty)

    let offLine = Expectation(landing: .exact(4..<4), blame: Expectation.Blame(
        capability: .lineStartKey, unmoved: [], leavesCaret: true, exemptions: [.init(.paragraphLines, offTarget: true)]))

    precondition(judged(offLine, 2..<2) == key(.lineStartKey, .neutral, .paragraphLines) && offLine.blamed(observed: 2..<2) == nil)
    precondition(judged(offLine, 2..<5) == key(.lineStartKey, .refutes, .leftSelection), "a selection left behind is still blamed")
    precondition(judged(offLine, 4..<4) == nil)
    let fromEmpty = Expectation(landing: .exact(7..<7), blame: Expectation.Blame(
        capability: .lineEndKey, unmoved: [], exemptions: [.init(.emptyParagraph, unmoved: [5..<5])]))
    precondition(judged(fromEmpty, 5..<5) == key(.lineEndKey, .neutral, .emptyParagraph) && judged(fromEmpty, 6..<6) == nil)
    var webWord = Expectation(landing: .exact(0..<3), blame: Expectation.Blame(
        capability: .wordKeys, unmoved: [0..<0], exemptions: [.init(.webContent, all: true)]))
    webWord.longest = 3
    precondition(webWord.blamed(observed: 0..<0) == nil && webWord.checkedKey == nil)
    precondition(judged(webWord, 0..<5) == key(.wordKeys, .neutral, .webContent) && judged(webWord, 1..<2) == nil)
    var neutralRun = RunAttribution()
    neutralRun.record(.press(.paragraphStart, count: 1))
    neutralRun.record(.settle(offLine), passed: false, selection: 2..<2)
    precondition(neutralRun.evidence == [Evidence(.key(.lineStartKey), .neutral, why: .paragraphLines, seen: .settle(1))])
    let chipLine = webPhysical("0", text: "ab\ncd", caret: 4, profile: keyProfile, breaks: chromiumBreak)
    precondition(chipLine.steps.contains {
        guard case .settle(let expectation) = $0 else { return false }
        return judged(expectation, 5..<5) == key(.lineStartKey, .neutral, .paragraphLines)
    }, "an off-target line key in Chromium rich text is neutral")

    let afterX = Expectation(selection: 5..<5, length: 11)
    precondition(writeStrike(afterX, selection: nil, length: 11) == .unanswered && writeStrike(afterX, selection: 5..<5, length: nil) == .unanswered)
    precondition(writeStrike(afterX, selection: 4..<4, length: 10) == .length, "unchanged text outranks where the caret read")
    precondition(writeStrike(afterX, selection: 4..<4, length: 11) == .moved)
    precondition(writeStrike(Expectation(selection: 5..<5, length: 11, edge: .paragraphEnd), selection: 5..<5, length: 11) == .edge)
    let stuckWord = Expectation(landing: .caretAfter(3, strict: true), blame: Expectation.Blame(capability: .wordKeys, unmoved: [3..<3]))
    precondition(judged(stuckWord, 3..<3) == key(.wordKeys, .refutes, .unmoved))
    var wideWord = Expectation(landing: .exact(0..<3), blame: Expectation.Blame(capability: .wordKeys, unmoved: []))
    wideWord.longest = 3
    precondition(judged(wideWord, 0..<5) == key(.wordKeys, .refutes, .tooLong))
    let aimedEnd = Expectation(landing: .exact(4..<4), blame: Expectation.Blame(capability: .lineEndKey, unmoved: [], offTarget: true))
    precondition(judged(aimedEnd, 6..<6) == key(.lineEndKey, .refutes, .offTarget) && aimedEnd.blamed(observed: 6..<6) == .lineEndKey)
    precondition(Learning.teaches(supportsValue) && Learning.teaches(textChecked.evidence[0]) && !Learning.teaches(.offsets(.neutral, .noBreaks)))
    precondition(Learning.teaches(struck.evidence[0]) && !Learning.teaches(passed.evidence[0]) && !Learning.teaches(neutralRun.evidence[0]))

    for capability in Capability.allCases {
        let question = Question(capability)
        precondition(question.rawValue == capability.rawValue && Question(rawValue: capability.rawValue) == question)
        precondition(question == (Capability.nativeKeys.contains(capability) ? .key(capability) : .write(capability)))
    }
    precondition(Question(rawValue: "offsets") == .offsets && Question.offsets.rawValue == "offsets")
    precondition(Question(rawValue: "offset") == .unknown("offset") && Question.unknown("offset").rawValue == "offset")
    var laterBuild = BeliefStore(beliefs: [Belief(rung: learnRung, question: Question(rawValue: "offset"), answer: Belief.broken,
                                                  versions: learnVersions)])
    precondition(committing(&laterBuild, .writeSelection) && laterBuild.beliefs.count == 2 && broken(laterBuild) == [.writeSelection],
                 "a question this build does not know is kept and ignored")

    for _ in 0..<400 {
        var probed: Set<Capability> = []
        var config: [Capability: ConfigChoice] = [:]
        var demoted: Set<Capability> = []
        var store = BeliefStore()
        for capability in Capability.allCases {
            if coin(2) == 0 { probed.insert(capability) }
            let override: ConfigChoice.Override? = [nil, .on, .off][Int(coin(3))]
            config[capability] = ConfigChoice(override: override, seededOff: coin(3) == 0)
            if capability.species == .mechanism, coin(3) == 0 {
                demoted.insert(capability)
                _ = committing(&store, capability)
            }
        }
        let profile = CapabilityProfile(available: probed)
        let resolved = CapabilityResolver.resolve(probed: profile, config: config, beliefs: resolving(store))
        precondition(resolved.report.entries == previousTable(probed: profile, config: config, learned: demoted))
        precondition(resolved.profile.statuses == previousTable(probed: profile, config: config, learned: demoted).mapValues(\.status))
        let enclosed = CapabilityResolver.resolve(probed: profile, enclosed: true, config: config, beliefs: resolving(store)).report.entries
        for (capability, entry) in resolved.report.entries {
            let read = Capability.blockScoped.contains(capability) && entry == .init(status: .available, source: .probed)
            precondition(enclosed[capability] == (read ? .init(status: .unavailable, source: .probed) : entry),
                         "an enclosing field turns off only what nothing else decided")
        }
    }

    var addedEdges = 0
    for _ in 0..<4000 {
        let (old, new) = (randomFocus(enclosing: false), randomFocus(enclosing: false))
        precondition(edge(old, new) == previousEdge(old, new), "no field names another, so the rule is the one before")
        let (block, other) = (randomFocus(enclosing: true), randomFocus(enclosing: true))
        if edge(block, other) != previousEdge(block, other) {
            precondition(previousEdge(block, other) == .newSession && edge(block, other) == .sameDocument, "enclosing fields only join")
            addedEdges += 1
        }
    }
    precondition(addedEdges > 100)
    var withheld = BeliefStore()
    _ = withheld.record(offsets: .untrusted, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally())
    let untrustedReport = CapabilityResolver.resolve(probed: axProfile, config: [:], beliefs: resolving(withheld)).report
    precondition(untrustedReport.entries[.readCaret] == .init(status: .unavailable, source: .learned))
    precondition(CapabilityResolver.resolve(probed: axProfile, config: [.readCaret: ConfigChoice(override: .on)], beliefs: resolving(withheld))
        .profile.has(.readCaret))

    let judgedBelief = Belief(
        rung: learnRung, question: .write(.writeSelection), answer: Belief.broken, judgedUnder: .value, versions: Versions(app: "1.49.1"),
        provenance: Provenance(build: "1.0.0 (812)", learnedAt: "2026-09-24T10:00:00Z", tag: "e3.c7")
    )
    precondition(judgedBelief.traceFields
        == "q=writeSelection a=broken judged=value ver=1.49.1 build=1.0.0(812) at=2026-09-24T10:00:00Z tag=e3.c7")
    var tallied = Tally()
    tallied.count(supportsTextContent)
    tallied.count(.offsets(.neutral, .noBreaks))
    let offsetsBelief = Belief(rung: learnRung, question: .offsets, answer: "textContent",
                               versions: Versions(app: "1.32.4", engine: "41.3.0"), tally: tallied, anchor: true)
    precondition(offsetsBelief.traceFields == "q=offsets a=textContent ver=1.32.4 engine=41.3.0 tally=v0,tc1,misfit0,neutral1 anchor")
    precondition(ReadModel(answer: .textContent).traceName == "textContent/start")
    precondition(ReadModel(answer: .value, newEngine: true).traceName == "value/start new-engine")
    var shown = BeliefStore(beliefs: [judgedBelief])
    _ = shown.record(offsets: .textContent, at: learnRung, versions: Versions(app: "1.49.1"), provenance: Provenance(tag: "e4.c1"), tally: Tally())
    precondition(resolving(shown, versions: Versions(app: "1.49.1")).traceLines == [
        "belief q=writeSelection a=broken judged=value ver=1.49.1 build=1.0.0(812) at=2026-09-24T10:00:00Z tag=e3.c7 reopened offsets=textContent",
        "belief q=offsets a=textContent ver=1.49.1 tag=e4.c1 tally=v0,tc0,misfit0,neutral0 in-force",
    ])
    precondition(supportsTextContent.traceFields == "q=offsets supports=textContent why=plain=textContent seen=snapshot")
    precondition(textChecked.evidence[0].traceFields == "q=offsets refutes why=text-check seen=settle@1")
    precondition(neutralRun.evidence[0].traceFields == "q=lineStartKey neutral why=paragraph-lines seen=settle@1")
    precondition(struck.evidence[0].traceFields == "q=writeSelection refutes why=moved seen=settle@1")
    precondition(passed.evidence[0].traceFields == "q=insertText supports why=settled seen=settle@1")
    precondition(moved.traceLines(rung: learnRung, versions: learnVersions)
        == ["offsets value→textContent why=plain=textContent rung=\(learnRung) engine=1.49.1 → republish"])
    let lengthStrike = Evidence(.write(.insertText), .refutes, why: .length, seen: .settle(3))
    precondition(Learning.Lesson(refuted: lengthStrike, republish: true).traceLines(rung: learnRung, versions: learnVersions)
        == ["commit q=insertText why=length rung=\(learnRung) ver=1.49.1 → republish"])
    precondition(Learning.Lesson(refuted: lengthStrike, skip: .alreadyCommitted).traceLines(rung: learnRung, versions: learnVersions)
        == ["skip=already-committed q=insertText why=length"])
    precondition(Learning.Lesson(refuted: lengthStrike, skip: .strike, strikes: 2).traceLines(rung: learnRung, versions: learnVersions)
        == ["strike 2/3 q=insertText why=length rung=\(learnRung)"])
    precondition(ignoredDelete[1].traceFields == "q=insertText refutes why=unchanged seen=settle@3")
    precondition(ignoredOnce.traceLines(rung: learnRung, versions: learnVersions)
        == ["commit q=insertText why=unchanged rung=\(learnRung) ver=1.49.1 → republish"])
    precondition(Expectation(selection: 10..<15, length: 21, selectedText: "hello").traceFields(text: true)
        == "sel=10..15 len=21 text=\"hello\"")
    precondition(Expectation(selection: 10..<15, length: 21, selectedText: "hello").traceFields == "sel=10..15 len=21 text=(5)")
    precondition(Expectation(selectedText: "ab").matches(selection: nil, length: nil, selectedText: "a\u{FFFC}b"),
                 "Chromium's leaf with no text is not a different selection")

    let withheldCaret = removing([.readCaret], from: axProfile)
    precondition(physical("rX", text: "say hello", profile: withheldCaret).steps.prefix(2)
        == [.press(.selectRight, count: 1), .typeText("X")], "an AX write would overtake the queued ⇧→")
    precondition(physical("o", text: "say hello", profile: withheldCaret).steps.prefix(2)
        == [.press(.lineEnd, count: 1), .typeText("\n")])
    precondition(physical("rX", text: "say hello", profile: withheldCaret).steps.allSatisfy {
        if case .replaceSelection = $0 { return false }
        return true
    })
    var replayInsert = VimState.initial
    replayInsert.session.lastChange = VimState.ChangeMemory(body: "i", insert: "abc")
    precondition(physical(".", text: "say hello", profile: withheldCaret, state: replayInsert).steps.contains(.replaceSelection("abc")),
                 "with nothing queued the AX write stays")
}

// MARK: - Lessons the menu may forget

let probedAll = CapabilityProfile(available: Set(Capability.allCases))
func taught(_ store: BeliefStore, starting: OffsetsAnswer = .value, probed: CapabilityProfile = probedAll,
            config: [Capability: ConfigChoice] = [:]) -> [ResolvedBeliefs.Lesson] {
    let beliefs = resolving(store, starting: starting, pins: config[.readCaret]?.override != nil)
    let report = CapabilityResolver.resolve(probed: probed, config: config, beliefs: beliefs).report
    return beliefs.lessons(report: report, overridden: Set(config.filter { $0.value.override != nil }.keys))
}

func testForgettableLessons() {
    var twoWrites = BeliefStore()
    precondition(committing(&twoWrites, .writeSelection) && committing(&twoWrites, .insertText))
    let inForceLessons = taught(twoWrites)
    precondition(inForceLessons.map(\.capability) == [.writeSelection, .insertText] && inForceLessons.allSatisfy { $0.state == .inForce })
    precondition(inForceLessons[1].beliefs.map(\.question) == [.write(.insertText)])
    precondition(taught(twoWrites, starting: .textContent).map(\.state) == [.reopened, .reopened])
    precondition(taught(twoWrites, starting: .textContent, config: [.insertText: ConfigChoice(override: .on)]).map(\.capability)
                 == [.writeSelection], "an On decides a reopened verdict")
    precondition(taught(twoWrites, config: [.insertText: ConfigChoice(override: .off)]).map(\.capability) == [.writeSelection])
    precondition(taught(twoWrites, probed: removing([.insertText], from: probedAll)).map(\.capability) == [.writeSelection])
    var forgotten = twoWrites
    for belief in inForceLessons[0].beliefs { forgotten.forget(belief.question, at: belief.rung) }
    precondition(taught(forgotten).map(\.capability) == [.insertText])

    var untrustedCaret = BeliefStore()
    precondition(untrustedCaret.record(offsets: .untrusted, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    let withheldLessons = taught(untrustedCaret, starting: .textContent)
    precondition(withheldLessons.map(\.capability) == [.readCaret] && withheldLessons[0].beliefs == [untrustedCaret.offsetsBelief(at: learnRung)!])
    var learnedValue = BeliefStore()
    precondition(learnedValue.record(offsets: .value, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    precondition(resolving(learnedValue, starting: .textContent).readModel.source == .learned)
    precondition(taught(learnedValue, starting: .textContent).isEmpty, "forgetting it would restart the field at textContent")
    var learnedMarkers = BeliefStore()
    precondition(learnedMarkers.record(offsets: .textContent, at: learnRung, versions: learnVersions, provenance: Provenance(), tally: Tally()))
    precondition(taught(learnedMarkers).isEmpty)
    var brokenCaret = learnedMarkers
    precondition(committing(&brokenCaret, .readCaret, under: .textContent))
    let brokenCaretLessons = taught(brokenCaret)
    precondition(brokenCaretLessons.map(\.capability) == [.readCaret] && brokenCaretLessons[0].beliefs.map(\.question) == [.write(.readCaret)])
    var brokenUntrusted = untrustedCaret
    precondition(committing(&brokenUntrusted, .readCaret, under: .untrusted))
    precondition(taught(brokenUntrusted, starting: .textContent).first?.beliefs.map(\.question) == [.offsets, .write(.readCaret)])

    var policyVerdict = BeliefStore()
    precondition(committing(&policyVerdict, .drawCursor))
    precondition(taught(policyVerdict).isEmpty, "the resolver applies no verdict to a policy")
    var twoRungs = BeliefStore()
    precondition(committing(&twoRungs, .insertText) && committing(&twoRungs, .insertText, at: "company.thebrowser.dia"))
    precondition(taught(twoRungs).first?.beliefs.map(\.rung) == [learnRung, "company.thebrowser.dia"])
    var mixedRungs = BeliefStore()
    precondition(committing(&mixedRungs, .insertText) && committing(&mixedRungs, .insertText, at: "company.thebrowser.dia", under: .textContent))
    precondition(taught(mixedRungs).first?.beliefs.count == 2, "Try Again leaves no reopened verdict behind")
}

// MARK: - Beliefs end to end (the Sim's Chromium read fault)

func testBeliefsEndToEnd() {
    // LIN-1590's worked example: the caret on the `w` of `world` is 16 in `AXValue` and 11 to Chromium.
    let workedExample = "a\nb\nc\nd\ne\nhello world"

    var firstParagraph = chromiumSim(workedExample, caret: 0, profile: axProfile, markers: true)
    firstParagraph.type("l")
    precondition(firstParagraph.learner!.model.answer == .value && firstParagraph.learner!.evidence.isEmpty,
                 "a caret in paragraph 1 reads no markers")
    var discovered = chromiumSim(workedExample, caret: 16, profile: axProfile, markers: true)
    discovered.type("ciwthere")
    discovered.feed("<Esc>")
    precondition(discovered.learner!.evidence.first == supportsTextContent)
    precondition(discovered.learner!.lessons.first?.move == Learning.Move(from: .value, to: .textContent, why: .plainIsTextContent))
    precondition(discovered.learner!.model.answer == .textContent && discovered.learner!.model.source == .learned)
    precondition(discovered.text == "a\nb\nc\nd\ne\nhello there" && discovered.settleFailures == 0, "the move takes effect on its own snapshot")
    var leftDiscovered = discovered
    precondition(leftDiscovered.selection == 20..<21)
    leftDiscovered.refocus(.newSession)
    precondition(leftDiscovered.selection == 20..<20, "the release writes the drawn cursor in field offsets")

    var misreadWord = chromiumSim(workedExample, caret: 16, profile: axProfile, markers: false)
    misreadWord.type("ciw")
    precondition(misreadWord.text == workedExample && misreadWord.settleFailures == 1, "ciw deletes nothing")
    precondition(checkedText(misreadWord.abortedStep) == "hello", "the range reads back as planned while ` worl` is selected")
    precondition(misreadWord.learner!.lessons.last?.move == Learning.Move(from: .value, to: .untrusted, why: .textCheck))
    precondition(misreadWord.learner!.model.answer == .untrusted && !misreadWord.profile.has(.readCaret))
    precondition(misreadWord.learner!.store.offsetsBelief(at: "sim|role:AXTextArea")?.tally?.misfit == 1, "the text check is tallied")
    precondition(misreadWord.state.field.mode == .normal && misreadWord.selection.isEmpty)
    misreadWord.type("ciw")
    precondition(misreadWord.settleFailures == 1 && misreadWord.text == "a\nb\nc\nd\ne\n world" && misreadWord.pasteboard == "hello",
                 "the next ciw lets the field choose the word, from where the check left the caret")
    var misreadKeys = chromiumSim(paragraphs, caret: 24, profile: readProfile, markers: false)
    misreadKeys.type("ciw")
    precondition(misreadKeys.text == paragraphs && misreadKeys.learner!.model.answer == .untrusted)

    var sameEngine = discovered
    sameEngine.reads = nil
    sameEngine.writesInReadOffsets = false
    sameEngine.type("h")
    precondition(sameEngine.learner!.lessons.last?.move == Learning.Move(from: .textContent, to: .untrusted, why: .plainIsValue))
    var newEngine = discovered
    newEngine.reads = nil
    newEngine.writesInReadOffsets = false
    newEngine.update(to: Versions(app: "2"))
    newEngine.type("h")
    precondition(newEngine.learner!.model.answer == .value && newEngine.learner!.evidence.last == supportsValue)
    var fixedChromium = chromiumSim(workedExample, caret: 16, profile: axProfile, markers: true, chromium: true,
                                    store: discovered.learner!.store)
    fixedChromium.reads = nil
    fixedChromium.writesInReadOffsets = false
    fixedChromium.update(to: Versions(app: "2"))
    fixedChromium.type("h")
    precondition(fixedChromium.learner!.lessons.last?.move == Learning.Move(from: .textContent, to: .value, why: .plainIsValue),
                 "a detected Chromium field moves back to value on a new engine")

    var preFix = BeliefStore()
    _ = preFix.commit(broken: .writeSelection, at: "sim|role:AXTextArea", judgedUnder: .value, versions: Versions(app: "1"),
                      provenance: Provenance(tag: "e3.c7"))
    var reopening = chromiumSim(workedExample, caret: 16, profile: axProfile, markers: true, store: preFix)
    precondition(!reopening.profile.has(.writeSelection), "in force while plain reads stand")
    reopening.type("l")
    precondition(reopening.learner!.model.answer == .textContent && reopening.profile.has(.writeSelection))
    precondition(reopening.learner!.resolved!.reopened.map(\.question) == [.write(.writeSelection)])
    reopening.type("ciwthere")
    precondition(reopening.text == "a\nb\nc\nd\ne\nhello there" && reopening.settleFailures == 0)

    var firstThenLater = chromiumSim("alpha beta gamma\nb\nc\nd\ne\nhello world", caret: 2, profile: axProfile, markers: true)
    firstThenLater.type("llll")
    precondition(firstThenLater.caret == 6 && firstThenLater.learner!.model.answer == .value)
    precondition(firstThenLater.learner!.sampling.remaining == OffsetsSampling.budget, "paragraph 1 spends no samples")
    firstThenLater.type("5jl")
    precondition(firstThenLater.learner!.model.answer == .textContent && firstThenLater.learner!.evidence.last == supportsTextContent)

    var untrustedRung = BeliefStore()
    _ = untrustedRung.record(offsets: .untrusted, at: "sim|role:AXTextArea", versions: Versions(app: "1"), provenance: Provenance(),
                             tally: Tally())
    var textarea = Sim(text: "say hello world", caret: 6, profile: axProfile)
    textarea.hasChildren = false
    textarea.learn(with: Sim.Learner(store: untrustedRung, probed: axProfile))
    precondition(textarea.profile.has(.readCaret) && textarea.learner!.model.source == .plain)
    textarea.type("ciwbye")
    textarea.feed("<Esc>")
    precondition(textarea.text == "say bye world" && textarea.settleFailures == 0)
    precondition(textarea.learner!.store == untrustedRung && textarea.learner!.evidence.isEmpty)

    for (keys, after) in [("dd", ""), ("x", "say helo world"), ("ciw", "say  world")] {
        var ignored = Sim(text: "say hello world", caret: 6, profile: axProfile)
        ignored.swallowsReplace = true
        ignored.learn(with: Sim.Learner(probed: axProfile))
        ignored.type(keys)
        let lesson = ignored.learner!.lessons.last
        precondition(ignored.text == "say hello world" && ignored.settleFailures == 1)
        precondition(lesson?.committed == .insertText && lesson?.refuted?.why == .unchanged && !ignored.profile.has(.insertText),
                     "\(keys): one swallowed replace switches it off")
        precondition(ignored.learner!.store.beliefs.map(\.judgedUnder) == [.value])
        if ignored.state.field.mode.isInserting {
            ignored.feed("<Esc>")
            ignored.type("l")
        }
        precondition(physical(keys, text: ignored.text, caret: ignored.caret, profile: ignored.profile).steps
            .contains(.press(.deleteBack, count: 1)))
        ignored.type(keys)
        precondition(ignored.text == after && ignored.settleFailures == 1, "\(keys): then Backspace deletes")
    }
    var swallowedWrites = Sim(text: "say hello world", caret: 6, profile: axProfile)
    swallowedWrites.swallowsSelect = true
    swallowedWrites.learn(with: Sim.Learner(probed: axProfile))
    for count in 1...Strikes.limit {
        swallowedWrites.type("l")
        precondition(swallowedWrites.caret == 6 && swallowedWrites.learner!.lessons.last?.strikes == count)
        precondition(swallowedWrites.profile.has(.writeSelection) == (count < Strikes.limit), "one lost write leaves writes on")
    }
    swallowedWrites.type("l")
    precondition(swallowedWrites.caret == 7, "then keys move the caret")
    var chipKey = chromiumSim("ab\ncd", caret: 4, profile: keyProfile, markers: true, chromium: true)
    chipKey.reboundChords = [.paragraphStart: .paragraphEnd]
    chipKey.type("0")
    precondition(chipKey.settleFailures == 1 && chipKey.blamed.isEmpty)
    precondition(chipKey.attribution.evidence.contains { $0.question == .key(.lineStartKey) && $0.outcome == .neutral && $0.why == .paragraphLines })
    precondition(chipKey.learner!.lessons.last?.committed == nil && chipKey.profile.has(.lineStartKey))
}
