// MARK: - Focus transitions

let offByPage = CapabilityReport.Entry(status: .unavailable, source: .probed)
let offBySeed = CapabilityReport.Entry(status: .unavailable, source: .seeded)
let offByUser = CapabilityReport.Entry(status: .unavailable, source: .user)
let onByDefault = CapabilityReport.Entry(status: .available, source: .probed)
let onByUser = CapabilityReport.Entry(status: .available, source: .user)
func reported(_ session: CapabilityReport.Entry?) -> CapabilityReport {
    CapabilityReport(entries: session.map { [.fieldIsSession: $0] } ?? [:])
}
func field(
    _ element: Int, in page: Int? = nil, _ session: CapabilityReport.Entry = onByDefault, role: String = "AXTextArea", pid: Int32 = 1,
    window: Int? = nil
) -> Focus {
    let report = reported(session)
    return Focus(element: element, pid: pid, site: role, everyFieldIsSession: report.everyFieldIsSession,
                 windowIsDocument: report.windowIsDocument, enclosing: page, window: window)
}

// End-to-end: `v` at 1 in a block, then focus takes the rule's own edge into its page or another block (LIN-1855).
func crossedInVisual(_ crossing: FocusTransition, to text: String, caret: Int, profile: CapabilityProfile, _ keys: String...) -> Sim {
    var sim = Sim(text: "abc", caret: 1, profile: enclosedField.profile)
    sim.emulatesKeys = true
    sim.type("v")
    sim.refocus(crossing, text: text, caret: caret)
    sim.profile = profile
    for key in keys {
        if key.hasPrefix("<") { sim.feed(key) } else { sim.type(key) }
    }
    return sim
}

// A click in the same field ends a half-typed command, which its last key would run at the clicked caret (LIN-1104).
func clicked(_ before: String, at offset: Int, _ after: String, in text: String = "one two three four") -> Sim {
    var sim = Sim(text: text, caret: 0, profile: axProfile)
    sim.type(before)
    sim.click(at: offset)
    if after.hasPrefix("<") { sim.feed(after) } else { sim.type(after) }
    return sim
}

func testFocusTransitions() {
    // The entry policy as a value — pinned nowhere until now.
    precondition(VimState.Field.entry.mode == .insert)

    // A fully-populated field, to prove exactly what each edge keeps.
    let populated = VimState.Field(
        mode: .normal,
        insertStart: 3,
        marks: ["a": MarkPoint(offset: 2, textLength: 9, context: "he")],
        lastVisual: VisualMemory(kind: .character, range: 1..<4),
        cursor: 2..<3
    )

    // sameElement: nothing moved, so nothing is stale.
    precondition(populated.carried(across: .sameElement) == populated)

    // sameDocument: residency survives; every offset-bearing member does not.
    let crossed = populated.carried(across: .sameDocument)
    precondition(crossed.mode == .normal)
    precondition(crossed.insertStart == nil)
    precondition(crossed.marks.isEmpty)
    precondition(crossed.lastVisual == nil)
    precondition(crossed.cursor == nil)

    // Visual carries, since dropping to Normal would break `v j j d`, but not its anchor: an offset in the field focus left.
    let visualContext = VimState.VisualContext(kind: .character, anchor: 0)
    precondition(
        VimState.Field(mode: .visual(visualContext)).carried(across: .sameDocument).mode
            == .visual(VimState.VisualContext(kind: .character, anchor: nil))
    )
    precondition(VimState.Field(mode: .visual(visualContext)).carried(across: .sameElement).mode == .visual(visualContext))

    // newSession: the entry policy, whatever the old field held.
    precondition(populated.carried(across: .newSession) == VimState.Field.entry)

    // Keys-in-flight and the dot body move as one unit, and only a new session
    // drops them.
    precondition(FocusTransition.newSession.clearsChangeInFlight)
    precondition(!FocusTransition.sameDocument.clearsChangeInFlight)
    precondition(!FocusTransition.sameElement.clearsChangeInFlight)
    precondition(FocusTransition.sameElement.preservesDrawnCursor)
    precondition(!FocusTransition.sameDocument.preservesDrawnCursor)

    precondition(edge(nil, field(1)) == .newSession && edge(field(1), nil) == .newSession)
    precondition(edge(field(1, in: 100, offByPage), field(1, in: 100, offByPage)) == .sameElement)
    precondition(edge(field(1, in: 100, offByPage), field(2, in: 100, offByPage)) == .sameDocument)
    precondition(edge(field(1, in: 100, offByPage), field(2, in: 200, offByPage)) == .newSession)
    precondition(edge(field(1, in: 100, offByPage), field(2, in: 100, offByPage, role: "AXTextField")) == .sameDocument)
    precondition(edge(field(1, in: 100, offByPage), field(100)) == .sameDocument && edge(field(100), field(1, in: 100, offByPage)) == .sameDocument,
                 "a block and the page it names are one document")
    precondition(edge(field(1), field(2)) == .newSession)
    precondition(edge(field(1, in: 100, onByUser), field(2, in: 100, offByPage)) == .newSession)
    precondition(edge(field(1, in: 100, offByPage), field(100, onByUser)) == .newSession, "the user's On keeps a field a session")
    precondition(edge(field(1, offBySeed, window: 7), field(2, offByUser, window: 7)) == .sameDocument)
    precondition(edge(field(1, offBySeed, window: 7), field(2, offBySeed, window: 8)) == .newSession)
    precondition(edge(field(1, offBySeed, window: 7), field(2, offBySeed, role: "AXTextField", window: 7)) == .newSession)
    precondition(edge(field(1, offBySeed, window: 7), field(2, offBySeed, pid: 2, window: 7)) == .newSession)
    precondition(edge(field(1, offBySeed), field(2, offBySeed)) == .newSession, "an unread window fails closed")
    precondition(edge(field(1, in: 100, offByPage, window: 7), field(2, in: 200, offByPage, window: 7)) == .newSession,
                 "the page's own answer never makes the window the document")
    precondition(edge(field(1, in: 100, offBySeed, window: 7), field(2, in: 200, offBySeed, window: 7)) == .sameDocument)
    precondition(edge(field(1, in: 100, offBySeed, window: 7), field(2, offBySeed, window: 7)) == .sameDocument)
    precondition(edge(field(1, in: 100, offBySeed, window: 7), field(2, in: 100, offBySeed, window: 8)) == .sameDocument)
    precondition(reported(offBySeed).windowIsDocument && reported(offByUser).windowIsDocument)
    precondition(!reported(offByPage).windowIsDocument && !reported(onByUser).windowIsDocument
        && !reported(onByDefault).windowIsDocument && !reported(nil).windowIsDocument)
    precondition(reported(onByUser).everyFieldIsSession && [onByDefault, offByUser, offBySeed, offByPage, nil].allSatisfy {
        !reported($0).everyFieldIsSession
    })
    let forcedApp = Focus(element: 0, pid: 1, site: "", forcedWindow: 7)
    precondition(edge(forcedApp, forcedApp) == .sameElement)
    precondition(edge(forcedApp, Focus(element: 0, pid: 1, site: "", forcedWindow: 8)) == .newSession)
    precondition(edge(forcedApp, Focus(element: 0, pid: 2, site: "", forcedWindow: 7)) == .newSession)
    precondition(edge(forcedApp, field(0)) == .newSession && edge(field(0), forcedApp) == .newSession)

    let blockToPage = edge(field(1, in: 100, offByPage), field(100))
    let blockToBlock = edge(field(1, in: 100, offByPage), field(2, in: 100, offByPage))
    let pageProfile = CapabilityResolver.resolve(probed: axProfile, config: shippedSeeds, learned: []).profile
    let pageText = "header\nabcdefghij\nfooter"
    let intoPage = crossedInVisual(blockToPage, to: pageText, caret: 10, profile: pageProfile, "j", "d")
    precondition(intoPage.text == "header\nabcter" && intoPage.bells == 0, "the block's anchor must not select in the page")
    precondition(crossedInVisual(blockToPage, to: pageText, caret: 10, profile: pageProfile, "l", "l", "d").text == "header\nabcfghij\nfooter")
    precondition(crossedInVisual(blockToBlock, to: "second block", caret: 7, profile: enclosedField.profile, "l", "d").text == "second lock",
                 "nor in another block, where `l` is planned in the block's own text")
    let leftVisual = crossedInVisual(blockToPage, to: pageText, caret: 10, profile: pageProfile, "j", "<Esc>")
    precondition(leftVisual.state.field.mode == .normal && leftVisual.text == pageText && leftVisual.bells == 0, "Esc still leaves Visual")

    // End-to-end through the Sim: engaging Normal then crossing a block keeps
    // Normal — the bug this exists for — while a genuinely new field opens in
    // Insert.
    var refocused = Sim(text: "one", state: .initial, profile: blockProfile)
    refocused.feed("<C-[>")
    precondition(refocused.state.field.mode == .normal)
    refocused.refocus(.sameDocument, text: "two")
    precondition(refocused.state.field.mode == .normal, "a block crossing must not end the session")
    refocused.refocus(.newSession, text: "three")
    precondition(refocused.state.field.mode == .insert)

    var leaving = Sim(text: "abc", caret: 0, profile: axProfile)
    leaving.type("l")
    precondition(leaving.selection == 1..<2 && leaving.state.field.cursor == 1..<2)
    leaving.refocus(.sameElement)
    precondition(leaving.selection == 1..<2)
    var unwritable = leaving
    leaving.refocus(.newSession)
    precondition(leaving.selection == 1..<1 && leaving.state.field.cursor == nil)
    unwritable.profile = readProfile
    unwritable.refocus(.newSession)
    precondition(unwritable.selection == 1..<2, "without a write the drawn cursor stays: a key would reach the new focus")

    // The dot body survives a crossing the user's own ⏎ caused: `ciw` opens the
    // body, the new block arrives mid-Insert, and Esc must still close it.
    var carriedChange = Sim(text: "say hello", caret: 4, profile: axProfile)
    carriedChange.feed("<C-[>")
    carriedChange.type("ciwfoo")
    carriedChange.refocus(.sameDocument, text: "bar")
    carriedChange.feed("<Esc>")
    precondition(carriedChange.state.session.lastChange == VimState.ChangeMemory(body: "ciw", insert: "foo"),
                 "sameDocument must not half-clear the dot body")

    let clickedOperator = clicked("d", at: 8, "w")
    precondition(clickedOperator.text == "one two three four" && clickedOperator.selection == 14..<15, "`w` only moves, from the click")
    precondition(clicked("", at: 8, "dw").text == "one two four", "typed whole after the click, it runs there")
    precondition(clicked("3", at: 4, "x", in: "abcdefgh").text == "abcdfgh")
    let clickedRegister = clicked("\"a", at: 8, "yw").state.session
    precondition(clickedRegister.register("a") == nil
        && clickedRegister.register("0") == .content(RegisterContent(text: "three ", wise: .character)))
    let clickedArgument = clicked("r", at: 8, "l")
    precondition(clickedArgument.text == "one two three four" && clickedArgument.selection == 9..<10)
    precondition(clicked("/t", at: 8, "w").selection == 14..<15, "an open prompt ends too")
    precondition(clicked("vi", at: 8, "<Esc>").state.field.mode == .normal, "Esc leaves Visual, with no object pending to cancel")
    var clickedInsert = Sim(text: "one two three four", caret: 0, profile: axProfile)
    clickedInsert.type("ciwONE")
    clickedInsert.click(at: 10)
    clickedInsert.type("X")
    clickedInsert.feed("<Esc>")
    precondition(clickedInsert.text == "ONE two thXree four" && clickedInsert.state.session.lastInsert == "ONEX")
    precondition(clickedInsert.state.session.lastChange == .unreplayable, "the typed log cannot say where the click put X")

    // An opaque selection is press-built and lives in the queued channel, so the
    // yank must ride the same queue (⌘C). `blockProfile` HAS readSelectedText —
    // the tempting synchronous AX read — and must still not use it here: it would
    // beat the queued presses and capture the selection as it was before them.
    let opaqueYank = physical("yj", text: "one", caret: 0, profile: blockProfile).steps
    precondition(opaqueYank.contains(.clipboardCopy), "opaque yank must stay in the queued channel")
    precondition(!opaqueYank.contains(where: {
        if case .captureSelectedText = $0 { return true }
        return false
    }), "a synchronous AX read would beat the queued presses")
}

// MARK: - The typing target (LIN-1742)

final class FakeElement: Equatable {
    let role: String?
    let parent: FakeElement?
    var owns: [FakeElement] = []
    var chromium = true
    var hasChildren = false

    init(_ role: String?, in parent: FakeElement? = nil) {
        self.role = role
        self.parent = parent
    }

    static func == (a: FakeElement, b: FakeElement) -> Bool { a === b }
}
func nested(_ role: String, _ depth: Int, in parent: FakeElement) -> FakeElement {
    (0..<depth).reduce(parent) { node, _ in FakeElement(role, in: node) }
}
var typingReads = 0
var caretReads = 0
func typingTarget(of reported: FakeElement, caretOn node: FakeElement?) -> FakeElement? {
    typingReads = 0
    caretReads = 0
    return TypingTarget.field(for: reported, read: { node in
        typingReads += 1
        return TypingTarget.Reading(role: node.role, parent: node.parent, owns: node.owns, isChromium: node.chromium)
    }, caret: { _ in
        caretReads += 1
        return node
    }, hasChildren: { $0.hasChildren })
}

let menuPage = FakeElement("AXWebArea")
let menuInput = FakeElement("AXComboBox", in: menuPage)

// A row destroyed mid-read misses once; a bound field is looked up again on a fresh focus read.
var targetLookups = 0
func target(of reported: FakeElement, bound: FakeElement?, refocus: FakeElement?) -> FakeElement {
    targetLookups = 0
    return TypingTarget.target(of: reported, bound: bound, field: { node in
        targetLookups += 1
        return typingTarget(of: node, caretOn: menuInput)
    }, refocus: { refocus })
}

func testTypingTarget() {
    let menuList = FakeElement("AXList", in: menuPage)
    let menuRow = FakeElement("AXStaticText", in: menuList)
    menuInput.owns = [menuList]
    precondition(typingTarget(of: menuRow, caretOn: menuInput) == menuInput && typingReads == 2)
    precondition(typingTarget(of: menuList, caretOn: menuInput) == menuInput, "the owned container itself")
    precondition(typingTarget(of: menuRow, caretOn: nil) == nil && typingReads == 1, "no caret in the page")
    precondition(typingTarget(of: menuInput, caretOn: menuInput) == nil && typingReads == 1 && caretReads == 0,
                 "a text field stands for itself")
    menuRow.chromium = false
    precondition(typingTarget(of: menuRow, caretOn: menuInput) == nil && typingReads == 1 && caretReads == 0,
                 "only Chromium defines AXOwns this way")
    menuRow.chromium = true
    precondition(typingTarget(of: FakeElement(nil, in: menuList), caretOn: menuInput) == nil && caretReads == 0, "a failed read")
    precondition(typingTarget(of: menuPage, caretOn: menuInput) == nil && typingReads == 1 && caretReads == 0, "the page itself")

    let groupedRow = FakeElement("AXStaticText", in: FakeElement("AXGroup", in: menuList))
    precondition(typingTarget(of: groupedRow, caretOn: menuInput) == menuInput && typingReads == 3, "a row in a group, as Linear's")
    precondition(typingTarget(of: nested("AXRow", TypingTarget.ownerHops, in: menuList), caretOn: menuInput) == menuInput)
    precondition(typingTarget(of: nested("AXRow", TypingTarget.ownerHops + 1, in: menuList), caretOn: menuInput) == nil)
    let framed = FakeElement("AXStaticText", in: FakeElement("AXWebArea", in: menuList))
    precondition(typingTarget(of: framed, caretOn: menuInput) == nil, "a frame's row is not the outer field's")

    let textArea = FakeElement("AXTextArea", in: menuPage)
    textArea.owns = [menuList]
    precondition(typingTarget(of: menuRow, caretOn: textArea) == textArea)
    textArea.hasChildren = true
    precondition(typingTarget(of: menuRow, caretOn: textArea) == nil, "a rich editor's caret does not say whether it has the focus")
    let unread = FakeElement(nil, in: menuPage)
    unread.owns = [menuList]
    precondition(typingTarget(of: menuRow, caretOn: unread) == nil, "a failed read of the field")
    let owningGroup = FakeElement("AXGroup", in: menuPage)
    owningGroup.owns = [menuList]
    precondition(typingTarget(of: menuRow, caretOn: owningGroup) == nil, "the caret's node is no text field")

    // Focus really elsewhere: Chromium leaves the caret on the text inside the field it left.
    let leftBehind = FakeElement("AXStaticText", in: FakeElement("AXGroup", in: menuInput))
    let pageButton = FakeElement("AXButton", in: menuPage)
    precondition(typingTarget(of: pageButton, caretOn: leftBehind) == nil && typingReads == 1 && caretReads == 0)
    precondition(typingTarget(of: FakeElement("AXStaticText", in: menuList), caretOn: leftBehind) == nil && typingReads == 2,
                 "a row of the field's own list with the real focus")
    precondition(typingTarget(of: FakeElement("AXCell", in: menuList), caretOn: FakeElement("AXGroup", in: menuInput)) == nil,
                 "and an empty field's left-behind caret")
    for role in ["AXButton", "AXLink"] {
        precondition(typingTarget(of: FakeElement(role, in: menuList), caretOn: menuInput) == nil && caretReads == 0,
                     "a button or a link is never a highlighted row")
    }
    let checkbox = FakeElement("AXCheckBox", in: menuPage)
    precondition(typingTarget(of: checkbox, caretOn: menuInput) == nil && typingReads == 3, "the field's list does not hold it")
    let plainInput = FakeElement("AXTextField", in: menuPage)
    precondition(typingTarget(of: checkbox, caretOn: plainInput) == nil && typingReads == 2, "a field that owns nothing")
    precondition(typingTarget(of: FakeElement("AXStaticText", in: FakeElement("AXList", in: menuPage)), caretOn: menuPage) == nil,
                 "a list no field owns")

    let deadRow = FakeElement(nil, in: menuList)
    precondition(target(of: menuInput, bound: menuInput, refocus: nil) == menuInput && targetLookups == 0)
    precondition(target(of: menuRow, bound: nil, refocus: nil) == menuInput && targetLookups == 1)
    precondition(target(of: menuRow, bound: menuInput, refocus: nil) == menuInput && targetLookups == 1)
    precondition(target(of: deadRow, bound: nil, refocus: menuRow) == deadRow && targetLookups == 1, "nothing bound to keep")
    precondition(target(of: deadRow, bound: menuInput, refocus: menuRow) == menuInput && targetLookups == 2)
    precondition(target(of: deadRow, bound: menuInput, refocus: menuInput) == menuInput && targetLookups == 1)
    precondition(target(of: deadRow, bound: menuInput, refocus: deadRow) == deadRow && targetLookups == 1, "focus did not move")
    precondition(target(of: deadRow, bound: menuInput, refocus: nil) == deadRow)
    precondition(target(of: pageButton, bound: menuInput, refocus: pageButton) == pageButton && targetLookups == 1)
    precondition(target(of: deadRow, bound: plainInput, refocus: menuRow) == deadRow && targetLookups == 2, "another field's row")
}
