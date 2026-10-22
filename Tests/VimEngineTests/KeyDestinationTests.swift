// MARK: - Where a command's keys land (LIN-1105)

func testKeyDestinations() {
    var clicked = KeyDestination(pid: 7, presses: 4, active: true)
    precondition(clicked.departure(presses: 4, active: true) == nil && clicked.departure(presses: 4, active: nil) == nil)
    precondition(clicked.departure(presses: 5, active: true) == .click)
    precondition(clicked.departure(presses: 4, active: false) == .click, "the first departure stays")
    var deactivated = KeyDestination(pid: 7, presses: 4, active: true)
    precondition(deactivated.departure(presses: 4, active: false) == .app)
    precondition(deactivated.departure(presses: 9, active: true) == .app)
    var overlay = KeyDestination(pid: 7, presses: 4, active: false)
    precondition(overlay.departure(presses: 4, active: false) == nil, "an app that was not active has none to lose")
    precondition(overlay.departure(presses: 6, active: false) == .click)

    let fiveLines = "a\nb\nc\nd\ne"
    var blindCut = Sim(text: fiveLines, caret: 0, profile: CapabilityProfile())
    blindCut.emulatesKeys = true
    blindCut.type("d3j")
    precondition(blindCut.text == "e" && blindCut.pasteboard == "a\nb\nc\nd\n" && blindCut.departure == nil, blindCut.text.debugDescription)
    for (after, unseen) in [(0, 0), (1, 0), (2, 3), (5, 0)] {
        var leaving = Sim(text: fiveLines, caret: 0, profile: CapabilityProfile())
        leaving.emulatesKeys = true
        leaving.focusLeaves = (after, unseen, .click)
        leaving.type("d3j")
        let context = "after \(after), unseen \(unseen)"
        precondition(leaving.text == fiveLines && leaving.pasteboard == nil && leaving.departure == .click, context)
        precondition(leaving.bells == 0 && leaving.settleFailures == 0 && leaving.state.field.mode == .normal, context)
        leaving.type("d3j")
        precondition(leaving.text == "e" && leaving.departure == nil, "the next command runs: \(context)")
    }

    var cutAway = Sim(text: fiveLines, caret: 0, profile: CapabilityProfile())
    cutAway.emulatesKeys = true
    cutAway.focusLeaves = (after: 5, unseen: 1, by: .app)
    cutAway.type("d3j")
    precondition(cutAway.text == fiveLines && cutAway.pasteboard == nil && cutAway.departure == .app)
    precondition(cutAway.state.session.registers == VimState.initial.session.registers, "a cut the focus left stores nothing")

    var unseenAway = Sim(text: fiveLines, caret: 0, profile: CapabilityProfile())
    unseenAway.emulatesKeys = true
    unseenAway.focusLeaves = (after: 2, unseen: 2, by: .app)
    unseenAway.type("d3j")
    precondition(unseenAway.selection == 0..<6 && unseenAway.text == fiveLines && unseenAway.departure == .app,
                 "keys posted before the executor saw its app go still reach the field, and the run stops at its next")

    var repairAway = Sim(text: paragraphs, caret: 24, profile: readProfile)
    repairAway.reads = omitsBreaks
    repairAway.focusLeaves = (after: 7, unseen: 1, by: .click)
    repairAway.type("ciw")
    precondition(repairAway.departure == .click && repairAway.selection == 24..<31, "the repair's only key, unseen, fails its run")

    var leftAfterMisread = false
    for after in 0...24 {
        var leaving = chromiumSim(paragraphs, caret: 24, profile: readProfile, markers: false)
        leaving.focusLeaves = (after, 0, .click)
        leaving.type("ciw")
        guard leaving.departure != nil else { continue }
        leftAfterMisread = leftAfterMisread || leaving.settleFailures > 0
        precondition(leaving.learner!.model.answer == .value && leaving.learner!.lessons.isEmpty, "a run the focus left teaches nothing: \(after)")
    }
    precondition(leftAfterMisread)

    var leavingInsert = Sim(text: "abc", caret: 2, profile: CapabilityProfile())
    leavingInsert.emulatesKeys = true
    leavingInsert.type("i")
    leavingInsert.focusLeaves = (after: 0, unseen: 1, by: .app)
    leavingInsert.feed("<Esc>")
    precondition(leavingInsert.departure == .app && leavingInsert.state.field.mode == .normal, "a mode change survives a run the focus left")

    var wordLeft = keyedSim(nativeThreeParagraphs, caret: 10)
    wordLeft.focusLeaves = (after: 0, unseen: 1, by: .click)
    wordLeft.type("w")
    precondition(wordLeft.departure == .click && wordLeft.blamed.isEmpty && wordLeft.attribution.evidence.isEmpty)
    precondition(wordLeft.caret == 10 && wordLeft.settleFailures == 0)
    var deleteLeft = keyedSim(nativeThreeParagraphs, caret: 0, profile: readProfile)
    deleteLeft.focusLeaves = (after: 1, unseen: 0, by: .click)
    deleteLeft.type("dw")
    precondition(deleteLeft.text == nativeThreeParagraphs && deleteLeft.departure == .click && deleteLeft.state.field.mode == .normal)
}
