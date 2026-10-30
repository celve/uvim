// MARK: - The engine and editor rungs (LIN-2390)

let slackApp = Surface(
    bundleID: "com.tinyspeck.slackmacgap", origin: "app.slack.com", role: "AXTextArea", editor: "quill", engine: .chromium
)
let slackInDia = Surface(
    bundleID: "company.thebrowser.dia", origin: "app.slack.com", role: "AXTextArea", editor: "quill", engine: .chromium
)
let quillInDia = Surface(
    bundleID: "company.thebrowser.dia", origin: "quilljs.com", role: "AXTextArea", editor: "quill", engine: .chromium
)
let quillPage = Surface(bundleID: "com.google.Chrome", origin: "quilljs.com", role: "AXTextArea", editor: "quill", engine: .chromium)
let linearApp = Surface(
    bundleID: "com.linear", origin: "linear.app", role: "AXTextArea", editor: "prosemirror", engine: .chromium
)

/// Strikes `capability` at `surface`'s learner rung until the learner commits it or stops.
func committedAt(
    _ surface: Surface, _ store: inout BeliefStore, _ capability: Capability = .wordKeys, under offsets: OffsetsAnswer = .value,
    app: String = "1.0"
) -> Learning.Lesson {
    let miss = Evidence(Question(capability), .refutes, why: .unmoved, seen: .settle(1))
    var strikes = Strikes()
    var lesson = Learning.Lesson()
    for _ in 0..<Strikes.limit(for: capability, why: .unmoved) {
        lesson = Learning.learn(
            store: &store, strikes: &strikes, rung: surface.roleRung!, editor: surface.editor, versions: Versions(app: app),
            model: ReadModel(answer: offsets), observed: Learning.Observation(before: offsets, source: .start), run: [miss],
            overridden: { _ in false }, provenance: Provenance(), tally: Tally()
        )
    }
    return lesson
}

func brokenAt(_ surface: Surface, _ store: BeliefStore, app: String = "7.0", offsets: OffsetsAnswer = .value) -> ResolvedBeliefs {
    store.resolve(rungs: surface.rungs, rung: surface.roleRung, versions: Versions(app: app), chromium: offsets == .textContent,
                  children: true, userPinsOffsets: false)
}

func testEditorRungs() {
    precondition(slackApp.rungs == [
        "com.tinyspeck.slackmacgap|app.slack.com|role:AXTextArea",
        "com.tinyspeck.slackmacgap|app.slack.com",
        "web:app.slack.com",
        "com.tinyspeck.slackmacgap",
        "editor:quill",
        "engine:chromium",
    ], "engine → editor → app → site → role → field, read narrowest first")
    precondition(Surface(bundleID: "com.apple.TextEdit", role: "AXTextArea", engine: .appkit).rungs
                 == ["com.apple.TextEdit|role:AXTextArea", "com.apple.TextEdit", "engine:appkit"])
    precondition(Surface(bundleID: "a", editor: "").rungs == ["a"])
    precondition(slackApp.writableScopes.map(\.scope) == [.fieldsOfRole("AXTextArea"), .site("app.slack.com"), .app],
                 "the menu writes no claim about every app")

    precondition(Surface.editor(classes: ["ql-editor", "ql-blank"]) == "quill")
    precondition(Surface.editor(classes: ["tiptap", "ProseMirror", "ProseMirror-focused"]) == "prosemirror")
    precondition(Surface.editor(classes: ["tiptap"]) == "prosemirror")
    precondition(Surface.editor(classes: ["ProseMirror-focused", "editor"]) == nil && Surface.editor(classes: []) == nil)

    precondition(BeliefStore.editorPrefix == Surface.editorPrefix && BeliefStore.isEditorRung(slackApp.editorRung!))
    precondition(BeliefStore.website(ofRoleRung: slackApp.roleRung!).map { "\($0.app)|\($0.host)" } == slackApp.rungs[1])
    precondition(BeliefStore.website(ofRoleRung: diaChrome.roleRung!) == nil && BeliefStore.website(ofRoleRung: "editor:quill") == nil)

    let seeds: SurfaceLadder.Seeds = ["editor:quill": ["fieldIsSession"], "engine:chromium": ["wholeDocument", "fieldIsSession"]]
    precondition(SurfaceLadder.seedEntry("fieldIsSession", rungs: slackApp.rungs, seeds: seeds) == "editor:quill")
    precondition(SurfaceLadder.seedEntry("wholeDocument", rungs: slackApp.rungs, seeds: seeds) == "engine:chromium")
    precondition(SurfaceLadder.seedEntry("fieldIsSession", rungs: linearApp.rungs, seeds: seeds) == "engine:chromium")
    precondition(SurfaceLadder.seedEntry("fieldIsSession", rungs: diaChrome.rungs, seeds: seeds) == nil)

    // A user's choice at any rung, the widest included, beats a shipped or learned fact at a narrower one.
    let atEngine: SurfaceLadder.UserStore = ["engine:chromium": ["fieldIsSession": "on", "wordKeys": "on"]]
    let user = SurfaceLadder.userEntry("fieldIsSession", rungs: slackApp.rungs, store: atEngine)
    precondition(user?.rung == "engine:chromium" && user?.value == "on")
    let profile = CapabilityProfile(available: Set(Capability.allCases))
    let unseeded = CapabilityResolver.resolve(
        probed: profile, config: [.fieldIsSession: ConfigChoice(override: .on, seededOff: true)], learned: []
    ).report.entries[.fieldIsSession]
    precondition(unseeded == CapabilityReport.Entry(status: .available, source: .user))
    let overLearned = CapabilityResolver.resolve(
        probed: profile, config: [.wordKeys: ConfigChoice(override: .on)], learned: [.wordKeys]
    ).report.entries[.wordKeys]
    precondition(overLearned == CapabilityReport.Entry(status: .available, source: .probed))
    let atEditor = CapabilityConfig.resolve(slackApp, capability: "insertText", overrides: ["editor:quill": ["insertText": "off"]])
    precondition(atEditor.override == .off && atEditor.overrideRung == "editor:quill")
    let narrower = CapabilityConfig.resolve(
        slackApp, capability: "insertText",
        overrides: ["editor:quill": ["insertText": "off"], "com.tinyspeck.slackmacgap": ["insertText": "on"]]
    )
    precondition(narrower.override == .on && narrower.overrideRung == "com.tinyspeck.slackmacgap")
    precondition(CapabilityConfig.resolve(linearApp, capability: "insertText", overrides: ["editor:quill": ["insertText": "off"]])
        .override == nil)
}

func testEditorPromotion() {
    var store = BeliefStore()
    let first = committedAt(slackApp, &store)
    precondition(first.committed == .wordKeys && first.promoted == nil, "one site is no editor's fact")
    precondition(store.beliefs.map(\.editor) == ["quill"] && store.beliefs[0].rung == slackApp.roleRung)
    var otherRole = slackApp
    otherRole.role = "AXTextField"
    precondition(committedAt(otherRole, &store).promoted == nil, "nor two roles of one site")
    precondition(committedAt(linearApp, &store).promoted == nil, "nor a site in another editor")
    precondition(committedAt(slackInDia, &store).promoted == nil, "nor one website in another app")
    precondition(committedAt(quillInDia, &store, under: .textContent).promoted == nil, "nor one judged under another read model")
    precondition(brokenAt(quillPage, store).broken.isEmpty)
    var native = BeliefStore()
    _ = committedAt(Surface(bundleID: "com.example.notes", role: "AXTextArea", editor: "quill"), &native)
    precondition(committedAt(quillInDia, &native).promoted == nil, "a native field names no website to agree from")

    var expired = BeliefStore()
    _ = committedAt(slackInDia, &expired, app: "1.0")
    precondition(committedAt(quillInDia, &expired, app: "2.0").promoted == nil, "the same app's verdict from its last version")
    precondition(committedAt(quillPage, &expired, app: "131.0").promoted == "editor:quill",
                 "another app's verdict agrees at whatever version it judged")

    var agreed = store
    agreed.beliefs.removeAll { $0.rung == quillInDia.roleRung }
    let second = committedAt(quillInDia, &agreed)
    precondition(second.promoted == "editor:quill", "two websites in one editor agree, even in one app")
    precondition(second.traceLines(rung: quillInDia.roleRung!, versions: Versions(app: "1.0"))
        .last == "promote q=wordKeys why=unmoved rung=editor:quill → republish")
    let promoted = agreed.beliefs.filter { $0.rung == "editor:quill" }
    precondition(promoted.count == 1 && promoted[0].editor == "quill" && promoted[0].fieldModel == BeliefStore.fieldModel)
    precondition(agreed.beliefs.contains { $0.rung == slackApp.roleRung } && agreed.beliefs.contains { $0.rung == quillInDia.roleRung },
                 "the sites keep their own verdicts")
    let third = brokenAt(quillPage, agreed, app: "131.0")
    precondition(third.broken == [.wordKeys] && third.inForce.map(\.rung) == ["editor:quill"],
                 "a third Quill field, in another app at another version, takes it")
    precondition(brokenAt(quillPage, agreed, offsets: .textContent).reopened.map(\.rung) == ["editor:quill"])
    precondition(brokenAt(linearApp, agreed, app: "1.0").inForce.map(\.rung) == [linearApp.roleRung!])
    var noEditor = quillPage
    noEditor.editor = nil
    precondition(brokenAt(noEditor, agreed).broken.isEmpty)
    var again = agreed
    precondition(committedAt(quillPage, &again).promoted == nil && again.beliefs.filter { $0.rung == "editor:quill" } == promoted,
                 "a standing editor verdict is not written again")

    var stale = agreed
    let index = stale.beliefs.firstIndex { $0.rung == "editor:quill" }!
    stale.beliefs[index].fieldModel = nil
    precondition(brokenAt(quillPage, stale).broken.isEmpty, "an editor verdict from an earlier field model is not applied")
    stale.beliefs.removeAll { $0.rung == quillInDia.roleRung }
    precondition(committedAt(quillInDia, &stale).promoted == "editor:quill"
        && stale.beliefs.filter { $0.rung == "editor:quill" }.map(\.fieldModel) == [BeliefStore.fieldModel])

    var unstamped = BeliefStore(beliefs: [Belief(
        rung: slackApp.roleRung!, question: .key(.wordKeys), answer: Belief.broken, judgedUnder: .value,
        fieldModel: BeliefStore.fieldModel, versions: Versions(app: "1.0")
    )])
    precondition(committedAt(quillInDia, &unstamped).promoted == nil, "a verdict that recorded no editor shares none")

    var forgotten = agreed
    forgotten.beliefs.removeAll { third.inForce.contains($0) }
    precondition(brokenAt(quillPage, forgotten).broken.isEmpty && brokenAt(slackApp, forgotten, app: "1.0").broken == [.wordKeys],
                 "Try Again in a third Quill field forgets the editor's verdict, not the sites'")
}
