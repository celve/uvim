// MARK: - Lark's composer, editor-kit (LIN-2509)

/// The composer's classes in LarkSuite 8.4.19 (softlash/LIN-2369 docs/fixtures/raw/lark-empty.jsonl).
let editorKitClasses = ["zone-container", "editor-kit-container", "innerdocbody", "notranslate", "chrome", "chrome88"]

/// Lark's composer with no selection write: editor-kit's ⌃A and ⌃E, which ⇧ does not make extend, read through its classes.
func editorKitSim(
    _ paragraphs: [String], caret: Int, classes: [String] = editorKitClasses, profile: CapabilityProfile = keyProfile
) -> Sim {
    var host = blankSim(paragraphs, caret: caret, profile: profile)
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

/// The composer as LarkSuite 8.4.19 shows it: two U+200B-only lines past the last, which its editor's model lacks (LIN-2763).
func larkTailSim(_ lines: [String], caret: Int, profile: CapabilityProfile) -> Sim {
    var host = editorKitSim(lines.map { $0 + zw } + [zw, zw], caret: caret, profile: profile)
    host.trailingLines = 2
    host.pullsBackFromLineEnds = false
    return host
}

func testEditorKitTail() {
    let tail = "\n\(zw)\n\(zw)"
    let none = UnreachableLines.Found(markers: [], chips: [])
    func fold(_ text: String, _ breaks: [Int], _ editor: EditorFacts) -> UnreachableLines.Model {
        UnreachableLines.fold(text: text, breaks: ParagraphBreaks(offsets: breaks), raw: String(text.filter { $0 != "\n" }),
                              found: none, editor: editor)
    }
    let kit = fold("a\(zw)\(tail)", [2, 4], .editorKit)
    precondition(kit.text == "a\(zw)" && kit.folded == 4 && kit.breaks.offsets.isEmpty)
    precondition(fold("a\(zw)\(tail)", [2, 4], []).folded == 0 && fold("a\(zw)\n\(zw)", [2], .editorKit).folded == 0)
    precondition(fold("a\(zw)\(tail)", [2], .editorKit).folded == 0, "a typed break is no paragraph's")
    precondition(fold("\(zw)\(tail)", [1, 3], .editorKit).text == zw, "an emptied composer keeps its line")
    let writes = adding([.writeSelection], to: keyProfile)
    for profile in [keyProfile, writes] {
        for (lines, caret, keys, after) in [
            (["hello world", "second line"], 14, "dd", "hello world\(zw)"),
            (["hello world", "second line"], 2, "dd", "second line\(zw)"),
            (["hello world", "second line"], 2, "Gdd", "hello world\(zw)"),
            (["hello world", "second line"], 2, "dG", zw),
            (["hello world", "second line"], 2, "2dd", zw),
            (["one", "two", "three"], 2, "jdG", "one\(zw)"),
            (["hello world", "second line"], 14, "ddu", "hello world\(zw)\nsecond line\(zw)"),
            (["hello", ""], 2, "Gdd", "hello\(zw)"),
            (["hello world", "second line"], 2, "2ddG", zw),
            (["hello world"], 2, "ddp", "\nhello world\(zw)"),
        ] {
            var lark = larkTailSim(lines, caret: caret, profile: profile)
            lark.type(keys)
            precondition(lark.text == after + tail && lark.settleFailures == 0 && lark.blamed.isEmpty,
                         "\(keys) in \(lines) under \(profile): \(lark.text.debugDescription) \(lark.settleFailures) \(lark.blamed)")
        }
        if profile == writes {
            var put = larkTailSim(["hello world", "second line"], caret: 14, profile: profile)
            put.type("yyp")
            precondition(put.text == "hello world\(zw)\nsecond line\nsecond line\(zw)" + tail && put.settleFailures == 0)
        }
        var bottom = larkTailSim(["hello world", "second line"], caret: 2, profile: profile)
        bottom.type("G")
        precondition(bottom.caret == 13 && bottom.settleFailures == 0, "G stops on the last line: \(bottom.caret)")
    }
}
