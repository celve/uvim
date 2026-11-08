// MARK: - Lark's composer, editor-kit (LIN-2509)

/// The composer's classes in LarkSuite 8.4.19 (softlash/LIN-2369 docs/fixtures/raw/lark-empty.jsonl).
let editorKitClasses = ["zone-container", "editor-kit-container", "innerdocbody", "notranslate", "chrome", "chrome88"]

/// Lark's composer with no selection write: editor-kit's ⌃A and ⌃E, which ⇧ does not make extend, read through its classes.
func editorKitSim(_ paragraphs: [String], caret: Int, classes: [String] = editorKitClasses) -> Sim {
    var host = blankSim(paragraphs, caret: caret)
    host.webContent = true
    host.pullsBackFromLineEnds = true
    host.runsAreNewlines = true
    host.reboundChords = [Chord.paragraphStart.shifted: .paragraphStart, Chord.paragraphEnd.shifted: .paragraphEnd]
    host.fieldClasses = classes
    return host
}

func testEditorKit() {
    precondition(EditorFacts(classes: editorKitClasses) == .editorKit && EditorFacts(classes: ["ProseMirror"]).isEmpty
                 && Surface.editor(classes: editorKitClasses) == "editor-kit")
    var kit = Navigation.editorKit
    precondition(!kit.lineKeysExtend && Navigation.structure.lineKeysExtend && Navigation.linear.lineKeysExtend)
    kit.lineKeysExtend = true
    precondition(kit == .structure, "editor-kit overrides one row of the structure's")
    var keys = KeyModel(text: "hello world\(zw)\nsecond\(zw)", anchor: 6, focus: 6, navigation: .editorKit)
    precondition(keys.press(Chord.paragraphEnd.shifted) && keys.selection == 12..<12
                 && keys.press(Chord.paragraphStart.shifted) && keys.selection == 0..<0, "⇧⌃E and ⇧⌃A leave a caret")

    let two = ["hello world\(zw)", "second line\(zw)"]
    for (keys, after) in [("D", "hello \(zw)"), ("d$", "hello \(zw)"), ("d0", "world\(zw)"), ("y$P", "hello worldworld\(zw)")] {
        var lark = editorKitSim(two, caret: 6)
        lark.type(keys)
        precondition(lark.text == after + "\nsecond line\(zw)" && lark.settleFailures == 0 && lark.blamed.isEmpty,
                     "\(keys): \(lark.text.debugDescription) \(lark.blamed)")
    }

    // From no beliefs, where every D failed and taught nothing (LIN-1975).
    var learning = editorKitSim(two, caret: 6)
    learning.learn(with: Sim.Learner(store: BeliefStore(), chromium: true, probed: keyProfile))
    for _ in 1...Strikes.limit {
        learning.type("D")
        precondition(learning.text == "hello \(zw)\nsecond line\(zw)" && learning.settleFailures == 0, learning.text.debugDescription)
        learning.type("u")
    }
    precondition(learning.profile.has(.lineEndKey) && learning.profile.has(.lineStartKey) && learning.blamed.isEmpty)

    // Without editor-kit's classes the field is any Chromium one's, where ⇧⌃E extends.
    var plain = blankSim(["hello world", "second line"], caret: 6)
    plain.webContent = true
    plain.fieldClasses = ["notranslate"]
    plain.type("D")
    precondition(plain.text == "hello \nsecond line" && plain.settleFailures == 0)
}
