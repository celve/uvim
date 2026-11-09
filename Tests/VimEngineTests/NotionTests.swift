// MARK: - Notion's table cells and code blocks take keys only (LIN-2766)

/// Field and parent classes in Chrome 156 (softlash/LIN-2048 scripts/live/evidence/trees/notion-page.jsonl).
let notionCellClasses = ["notion-table-cell-text", "content-editable-leaf-rtl", "notranslate"]
let notionBlockClasses = ["content-editable-leaf-rtl", "notranslate"]
let notionCodeParent = ["line-numbers", "notion-code-block"]
let notionTextParent = ["notion-selectable", "notion-text-block"]

/// What the probe claims in a Chromium block field, which names the page around it; Chromium ignores text writes, so
/// `insertText` is learned off (uvim-text-writes-by-engine).
let notionProbed = CapabilityProfile(available: Set(Capability.allCases.filter { $0.species == .mechanism }))

func notionResolved(classes: [String], parent: [String], config: [Capability: ConfigChoice] = shippedSeeds) -> CapabilityReport {
    let keysOnly = EditorFacts.keysOnly(editor: Surface.editor(classes: classes), classes: classes, parentClasses: parent)
    return CapabilityResolver.resolve(probed: notionProbed, enclosed: true, keysOnly: keysOnly, config: config, learned: [.insertText]).report
}

func notionSim(_ text: String, caret: Int, report: CapabilityReport) -> Sim {
    var host = Sim(text: text, caret: caret, profile: CapabilityProfile(statuses: report.entries.mapValues(\.status)))
    host.webContent = true
    host.emulatesKeys = true
    host.writesDeadenKeys = true
    return host
}

func testNotionKeysOnly() {
    precondition(Surface.editor(classes: notionCellClasses) == "notion" && Surface.editor(classes: notionBlockClasses) == "notion")
    precondition(EditorFacts.keysOnly(editor: "notion", classes: notionCellClasses, parentClasses: [])
                 && EditorFacts.keysOnly(editor: "notion", classes: notionBlockClasses, parentClasses: notionCodeParent))
    precondition(!EditorFacts.keysOnly(editor: "notion", classes: notionBlockClasses, parentClasses: notionTextParent)
                 && !EditorFacts.keysOnly(editor: "prosemirror", classes: notionCellClasses, parentClasses: notionCodeParent)
                 && !EditorFacts.keysOnly(editor: nil, classes: notionCellClasses, parentClasses: []), "plain blocks and other editors write")
    precondition(EditorFacts(classes: notionCellClasses).isEmpty, "no Navigation row changes")

    let cell = notionResolved(classes: notionCellClasses, parent: [])
    let code = notionResolved(classes: notionBlockClasses, parent: notionCodeParent)
    let plain = notionResolved(classes: notionBlockClasses, parent: notionTextParent)
    for report in [cell, code] {
        precondition(report.traceGrid.contains("WS-p IT-l DC-p WD-p FS-p"), report.traceGrid)
    }
    precondition(plain.traceGrid.contains("WS+p IT-l DC-p WD-p FS-p"), plain.traceGrid)
    let userOn = notionResolved(classes: notionCellClasses, parent: [], config: [.writeSelection: ConfigChoice(override: .on)])
    precondition(userOn.entries[.writeSelection] == .init(status: .available, source: .user), "the user's On writes again")
    let userOff = notionResolved(classes: notionBlockClasses, parent: notionTextParent, config: [.writeSelection: ConfigChoice(override: .off)])
    precondition(userOff.entries[.writeSelection] == .init(status: .unavailable, source: .user))

    // A write leaves the keys dead, so the next command's keys miss; keys alone land.
    let cases: [(text: String, caret: Int, keys: String, after: String, report: CapabilityReport)] = [
        ("Aone apple bread", 0, "wx", "Aone pple bread", cell),
        ("Aone apple bread", 0, "ex", "Aon apple bread", cell),
        ("Aone apple bread", 0, "wdw", "Aone bread", cell),
        ("Aone apple bread", 6, "0dw", "apple bread", cell),
        ("code one alpha\ncode two beta", 0, "wx", "code ne alpha\ncode two beta", code),
        ("code one alpha\ncode two beta", 0, "wjx", "code one alpha\ncode wo beta", code),
    ]
    for (text, caret, keys, after, report) in cases {
        var notion = notionSim(text, caret: caret, report: report)
        notion.type(keys)
        precondition(notion.text == after && notion.settleFailures == 0 && notion.blamed.isEmpty,
                     "\(keys): \(notion.text.debugDescription) \(notion.settleFailures) \(notion.blamed)")
        var writing = notionSim(text, caret: caret, report: plain)
        writing.type(keys)
        precondition(writing.text != after || writing.settleFailures > 0, "\(keys): the write lane misses after a write")
    }
}
