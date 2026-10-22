// MARK: - Surface rungs and the precedence walks

// The whole point: one app, two engines. Dia's own search box is native; the
// <input> in the page it is showing is not; both are AXTextField.
let diaChrome = Surface(bundleID: "company.thebrowser.dia", role: "AXTextField", identifier: "address-bar")

let diaPageField = Surface(
    bundleID: "company.thebrowser.dia", origin: "app.notion.com", role: "AXTextField", identifier: "search-input"
)

func testSurfaceRungs() {
    let diaPage = Surface(bundleID: "company.thebrowser.dia", origin: "app.notion.com", role: "AXTextField")

    // Narrowest first, and both element rungs coexist so an identified field still
    // inherits from "all text fields on this site".
    precondition(diaPageField.rungs == [
        "company.thebrowser.dia|app.notion.com|id:search-input",
        "company.thebrowser.dia|app.notion.com|role:AXTextField",
        "company.thebrowser.dia|app.notion.com",
        "web:app.notion.com",
        "company.thebrowser.dia",
    ])
    // No identifier: the id rung simply drops out.
    precondition(diaPage.rungs == [
        "company.thebrowser.dia|app.notion.com|role:AXTextField",
        "company.thebrowser.dia|app.notion.com",
        "web:app.notion.com",
        "company.thebrowser.dia",
    ])
    // Native: no origin, so no site rung and no web: rung. The element rungs hang
    // off the app instead.
    precondition(diaChrome.rungs == [
        "company.thebrowser.dia|id:address-bar",
        "company.thebrowser.dia|role:AXTextField",
        "company.thebrowser.dia",
    ])
    // The bare bundle ID is still the last rung, which is what makes every override
    // written before surfaces existed keep resolving.
    precondition(Surface(bundleID: "notion.id").rungs == ["notion.id"])
    precondition(Surface().rungs.isEmpty)

    // Host normalization: case-folded, `www.` dropped, unusable hosts refused.
    precondition(Surface.normalizedHost("WWW.Notion.SO") == "notion.so")
    precondition(Surface.normalizedHost("docs.google.com") == "docs.google.com")
    precondition(Surface.normalizedHost("") == nil)
    precondition(Surface.normalizedHost(nil) == nil)
    // Subdomains are kept: these are genuinely different editors.
    precondition(Surface.normalizedHost("mail.google.com") != Surface.normalizedHost("docs.google.com"))

    // A `|` in a DOM id must not forge a rung boundary.
    precondition(Surface(bundleID: "a", role: "R", identifier: "x|y").rungs.first == "a|id:x%7Cy")

    // The menu never offers the app-independent web: rung — that is curation's
    // claim, not one a user makes standing in one app.
    precondition(diaPageField.writableScopes.map(\.scope) == [
        .field(identifier: "search-input"), .fieldsOfRole("AXTextField"), .site("app.notion.com"), .app,
    ])
    precondition(diaChrome.writableScopes.map(\.scope) == [
        .field(identifier: "address-bar"), .fieldsOfRole("AXTextField"), .app,
    ])
    precondition(!diaPageField.writableScopes.contains { $0.rung == "web:app.notion.com" })

    // `site` drops the element half. transition() compares THIS: every Notion block
    // is a different element, so comparing whole surfaces would end the session on
    // every line move — the exact failure fieldIsSession exists to prevent.
    precondition(diaPage.site == diaPageField.site)
    precondition(diaPage != diaPageField)

    // --- The two walks -------------------------------------------------------

    let seeds: SurfaceLadder.Seeds = [
        "web:app.notion.com": ["wholeDocument", "drawCursor"],
        "company.thebrowser.dia": ["fieldIsSession"],
    ]

    // Seeds resolve at whichever rung names them, narrowest first.
    precondition(SurfaceLadder.seedEntry("wholeDocument", rungs: diaPageField.rungs, seeds: seeds)
                 == "web:app.notion.com")
    precondition(SurfaceLadder.seedEntry("fieldIsSession", rungs: diaPageField.rungs, seeds: seeds)
                 == "company.thebrowser.dia")
    precondition(SurfaceLadder.seedEntry("readText", rungs: diaPageField.rungs, seeds: seeds) == nil)
    // A native field in the same app never sees the site's seed.
    precondition(SurfaceLadder.seedEntry("wholeDocument", rungs: diaChrome.rungs, seeds: seeds) == nil)

    // The narrowest user entry wins over wider ones.
    let layered: SurfaceLadder.UserStore = [
        "company.thebrowser.dia": ["insertText": "off"],
        "company.thebrowser.dia|app.notion.com": ["insertText": "on"],
    ]
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaPageField.rungs, store: layered)?.rung
                 == "company.thebrowser.dia|app.notion.com")
    // ...and the app-level entry is what a native field in the same app still sees.
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaChrome.rungs, store: layered)?.rung
                 == "company.thebrowser.dia")
    precondition(SurfaceLadder.userEntry("readText", rungs: diaChrome.rungs, store: layered) == nil)

    // THE law a single merged walk would have broken: a user's `.on` at the app
    // rung must still un-seed curation at the narrower web: rung. The walks stay
    // separate precisely so the existing precedence table can see both and apply
    // "`.on` un-seeds" itself.
    let unseeding: SurfaceLadder.UserStore = ["company.thebrowser.dia": ["wholeDocument": "on"]]
    precondition(SurfaceLadder.seedEntry("wholeDocument", rungs: diaPageField.rungs, seeds: seeds)
                 == "web:app.notion.com")
    precondition(SurfaceLadder.userEntry("wholeDocument", rungs: diaPageField.rungs, store: unseeding)?.value
                 == "on")

    // --- The write rule ------------------------------------------------------

    // "The picker must never show a lie": writing at a rung clears the same atom at
    // every narrower one, so the choice just made is the choice that resolves.
    let conflicted: SurfaceLadder.UserStore = [
        "company.thebrowser.dia|app.notion.com|id:search-input": ["insertText": "on"],
        "company.thebrowser.dia|app.notion.com": ["insertText": "on"],
    ]
    let widened = SurfaceLadder.setting(
        "off", "insertText", at: "company.thebrowser.dia", rungs: diaPageField.rungs, store: conflicted
    )
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaPageField.rungs, store: widened)?.value
                 == "off", "a wider write must not be shadowed by the narrow entries it replaces")
    precondition(widened["company.thebrowser.dia|app.notion.com|id:search-input"] == nil)
    precondition(widened["company.thebrowser.dia|app.notion.com"] == nil)

    // Writing narrow leaves wider rungs alone — nothing below them to clear.
    let narrowed = SurfaceLadder.setting(
        "off", "insertText", at: "company.thebrowser.dia|app.notion.com", rungs: diaPageField.rungs, store: layered
    )
    precondition(narrowed["company.thebrowser.dia"]?["insertText"] == "off")
    precondition(narrowed["company.thebrowser.dia|app.notion.com"]?["insertText"] == "off")

    // The Dia shape, end to end: denying the page must leave the chrome untouched.
    let scoped = SurfaceLadder.setting(
        "off", "insertText", at: "company.thebrowser.dia|app.notion.com|role:AXTextField",
        rungs: diaPage.rungs, store: [:]
    )
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaPage.rungs, store: scoped)?.value == "off")
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaChrome.rungs, store: scoped) == nil,
                 "denying the page must not reach the app's own search box")

    // Auto clears the atom at every rung, and touches nothing else.
    let mixed: SurfaceLadder.UserStore = [
        "company.thebrowser.dia|app.notion.com": ["insertText": "off", "drawCursor": "off"],
        "company.thebrowser.dia": ["insertText": "on"],
    ]
    let autoed = SurfaceLadder.setting(
        nil, "insertText", at: nil, rungs: diaPageField.rungs, store: mixed
    )
    precondition(SurfaceLadder.userEntry("insertText", rungs: diaPageField.rungs, store: autoed) == nil)
    precondition(autoed["company.thebrowser.dia|app.notion.com"]?["drawCursor"] == "off", "Auto must be per-atom")

    // Emptied rungs are pruned, so `defaults read` shows exactly what was chosen.
    precondition(SurfaceLadder.setting(
        nil, "insertText", at: nil, rungs: diaChrome.rungs,
        store: ["company.thebrowser.dia": ["insertText": "off"]]
    ).isEmpty)

    // The clear actions wipe a scope and everything narrower than it.
    let cleared = SurfaceLadder.clearing(
        atAndBelow: "company.thebrowser.dia|app.notion.com", rungs: diaPageField.rungs, store: conflicted
    )
    precondition(cleared.isEmpty)
    // ...but never a wider one.
    precondition(SurfaceLadder.clearing(
        atAndBelow: "company.thebrowser.dia|app.notion.com", rungs: diaPageField.rungs, store: layered
    )["company.thebrowser.dia"]?["insertText"] == "off")

    // Every capability the shipped seeds name must still exist, and the rungs they
    // are keyed by must be rungs some surface can actually produce. A renamed atom
    // or a malformed seed key orphans curation silently.
    for (rung, capabilities) in CapabilitySeeds.denied {
        for raw in capabilities {
            precondition(Capability(rawValue: raw) != nil, "seed names unknown capability \(raw)")
        }
        let reachable = rung == Surface.everywhere
            || (rung.hasPrefix("web:")
                ? Surface(bundleID: "any", origin: String(rung.dropFirst(4))).rungs.contains(rung)
                : Surface(bundleID: rung).rungs.contains(rung))
        precondition(reachable, "no surface can ever produce seed rung \(rung)")
    }

    precondition(SurfaceLadder.seedEntry("nativeMotions", rungs: diaPageField.rungs, seeds: CapabilitySeeds.denied)
                 == Surface.everywhere)
    precondition(SurfaceLadder.seedEntry("nativeMotions", rungs: [], seeds: CapabilitySeeds.denied)
                 == Surface.everywhere)
    precondition(CapabilitySeeds.denied.keys.allSatisfy { $0 == Surface.everywhere }, "a shipped default names no app or host")
    for bundleID in ["company.thebrowser.dia", "notion.id"] {
        let block = Surface(bundleID: bundleID, origin: "app.notion.com", role: "AXTextArea")
        for capability in Capability.blockScoped {
            precondition(!CapabilityConfig.resolve(block, capability: capability.rawValue, overrides: [:]).isSeededOff,
                         "a Notion block in \(bundleID) takes \(capability) from the page's read, not a default")
        }
    }
    precondition(SurfaceLadder.seedEntry("wholeDocument", rungs: diaChrome.rungs, seeds: CapabilitySeeds.denied) == nil)
    precondition(!diaPageField.rungs.contains(Surface.everywhere))
    precondition(!diaPageField.writableScopes.contains { $0.rung == Surface.everywhere })
    precondition(Capability.nativeMotions.species == .policy && Capability.nativeMotions.parent == nil)
}

// MARK: - The web-area walk

// Fake AX tree: element n's parent is n + 1 unless overridden.
func walked(_ tree: [Int: WebAreaWalk.Reading<Int>]) -> WebAreaWalk.Result {
    WebAreaWalk.walk(from: 0, clock: { 0 }) { node in
        tree[node] ?? WebAreaWalk.Reading(role: "AXGroup", parent: node + 1)
    }
}
func page(_ scheme: String?, _ host: String?, at depth: Int) -> [Int: WebAreaWalk.Reading<Int>] {
    [depth: WebAreaWalk.Reading(
        role: "AXWebArea", address: WebAreaWalk.Address(scheme: scheme, host: host), parent: depth + 1
    )]
}

func testWebAreaWalk() {
    // The old 16-hop cap keyed this editor at the app rung.
    let deepEditor = walked(page("https", "WWW.Linear.app", at: 40))
    precondition(deepEditor.origin == "linear.app")
    precondition(deepEditor.stop == .webArea(WebAreaWalk.Address(scheme: "https", host: "WWW.Linear.app")))
    precondition(deepEditor.hops == 40)
    precondition(deepEditor.traceFields == "stop=site@40 ms=0")
    precondition(walked(page("https", "linear.app", at: 3)).origin == "linear.app")
    precondition(walked(page("https", "linear.app", at: WebAreaWalk.maxHops - 1)).origin == "linear.app")

    let pastCap = walked(page("https", "linear.app", at: WebAreaWalk.maxHops))
    precondition(pastCap.origin == nil && pastCap.stop == .hopCap)
    precondition(pastCap.traceFields == "stop=hopCap@64 ms=0")

    let localPage = walked(page("file", nil, at: 4))
    precondition(localPage.origin == nil)
    precondition(localPage.traceFields == "stop=hostless@4 scheme=file ms=0")
    precondition(walked(page("about", nil, at: 2)).traceFields == "stop=hostless@2 scheme=about ms=0")
    precondition(walked(page("https", "", at: 2)).origin == nil)

    let noURL = walked([4: WebAreaWalk.Reading(role: "AXWebArea", parent: 5)])
    precondition(noURL.origin == nil && noURL.traceFields == "stop=noURL@4 ms=0")
    precondition(walked([5: WebAreaWalk.Reading(role: "AXWindow", parent: 6)]).traceFields == "stop=window@5 ms=0")
    precondition(walked([1: WebAreaWalk.Reading(role: "AXApplication", parent: nil)]).traceFields
        == "stop=application@1 ms=0")

    let timedOut = walked([2: WebAreaWalk.Reading(role: "AXGroup", parent: nil, parentError: -25204)])
    precondition(timedOut.stop == .orphan(axError: -25204) && timedOut.origin == nil)
    precondition(timedOut.traceFields == "stop=orphan@2 axerror=-25204 ms=0")
    precondition(walked([0: WebAreaWalk.Reading(role: "AXTextArea", parent: nil)]).traceFields
        == "stop=orphan@0 axerror=nil ms=0")

    var walkClock = 0.0
    var walkReads = 0
    let stalled = WebAreaWalk.walk(from: 0, clock: { walkClock += 0.3; return walkClock }) { node -> WebAreaWalk.Reading<Int> in
        walkReads += 1
        return WebAreaWalk.Reading(role: "AXGroup", parent: node + 1)
    }
    precondition(stalled.stop == .budget && walkReads == 2)
    precondition(stalled.traceFields == "stop=budget@2 ms=900")
    walkReads = 0
    let spent = WebAreaWalk.walk(from: 0, clock: { walkClock += 1; return walkClock }) { node -> WebAreaWalk.Reading<Int> in
        walkReads += 1
        return WebAreaWalk.Reading(role: "AXGroup", parent: node + 1)
    }
    precondition(spent.stop == .budget && spent.hops == 1 && walkReads == 1, "the field itself is always read")
}
