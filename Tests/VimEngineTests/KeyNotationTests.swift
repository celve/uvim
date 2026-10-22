// MARK: - KeyNotation

/// The gate between hardware and the engine. nil means the app keeps the key;
/// a token means vim CONSUMES it, because Normal/Visual has no passthrough
/// exit. So every nil below is a shortcut that still works while vim is
/// engaged, and every token is a promise the engine can act on it.
private func expectToken(
    _ keyCode: Int,
    _ chord: KeyNotation.Chord,
    _ characters: String,
    _ expected: String?,
    escapeEngages: Bool = false,
    file: StaticString = #file,
    line: UInt = #line
) {
    let token = KeyNotation.token(keyCode: keyCode, chord: chord, characters: characters, escapeEngages: escapeEngages)
    precondition(
        token == expected,
        "Unexpected token for keyCode \(keyCode) chord \(chord.rawValue): \(token ?? "nil")",
        file: file, line: line
    )
}

// The ⌃-letters the gate admits must be exactly the ones the engine can
// EXECUTE — not the ones the parser merely recognizes. The parser binds
// eleven; nine plan to a bare bell, and admitting those would steal ⌃a
// (beginning-of-line), ⌃e (end-of-line) and friends to play a beep.
//
// Both sides are derived, so this fails the day someone implements the page
// motions — which is exactly when the gate needs to change to match.
let alphabet = "abcdefghijklmnopqrstuvwxyz"
func gateAdmits(_ profile: CapabilityProfile) -> Set<Character> {
    Set(alphabet.filter {
        KeyNotation.token(keyCode: 0, chord: [.control], characters: controlCharacter($0), profile: profile) != nil
    })
}
func engineExecutes(_ profile: CapabilityProfile) -> Set<Character> {
    Set(alphabet.filter { letter in
        let command = RawCommand("<C-\(letter)>")
        guard command.isComplete else { return false }   // <C-w> never completes alone
        let plan = PhysicalPlanner.plan(
            LogicalPlanner.plan(command, state: .initial),
            snapshot: FieldSnapshot(capabilities: profile, text: "alpha beta\nsecond line\n", selection: 3..<3)
        )
        return plan.steps != [.bell]
    })
}

func testKeyNotation() {
    // Bare keys are vim's; the tap resolves shift into `characters`.
    expectToken(38, [], "j", "j")
    expectToken(38, [.shift], "J", "J")
    expectToken(123, [], "", "<Left>")
    expectToken(36, [], "\r", "<CR>")
    expectToken(48, [], "\t", "\t")          // bare Tab stays vim's — deliberate scope
    expectToken(53, [], "\u{1B}", nil)       // physical Esc is the app's under the ⌃[ setting
    expectToken(38, [.command], "j", nil)

    expectToken(53, [], "\u{1B}", "<Esc>", escapeEngages: true)
    expectToken(53, [.shift], "\u{1B}", "<Esc>", escapeEngages: true)
    expectToken(53, [.option], "\u{1B}", nil, escapeEngages: true)
    expectToken(53, [.command], "\u{1B}", nil, escapeEngages: true)
    expectToken(53, [.control], "\u{1B}", "<C-[>")
    expectToken(33, [.control], "\u{1B}", "<C-[>", escapeEngages: true)
    expectToken(38, [], "j", "j", escapeEngages: true)

    // ⇧ is transparent on the navigation cluster…
    expectToken(123, [.shift], "", "<Left>")
    // …but not on Tab: ⇧⇥ reverses focus and inserts nothing, so the app keeps it.
    expectToken(48, [.shift], "\t", nil)

    // The keycode table used to run before any modifier check, so a chorded
    // navigation key laundered into a bare vim token — irrecoverably, since the
    // modifier was gone by the time the monitor saw `<Up>`.
    expectToken(126, [.control], "", nil)        // ⌃↑ Mission Control
    expectToken(125, [.control], "", nil)        // ⌃↓ App Exposé
    expectToken(123, [.option], "", nil)         // ⌥← word-left
    expectToken(51, [.option], "\u{7F}", nil)    // ⌥⌫ delete-word-back
    expectToken(48, [.control], "\t", nil)       // ⌃⇥ next tab

    // ⌃ on a key with no character identity used to fall into the ⌃-letter
    // branch and be read as a letter: Home is U+0001, every F-key is U+0010.
    expectToken(115, [.control], controlCharacter("a"), nil)   // ⌃Home, was <C-a>
    expectToken(119, [.control], controlCharacter("d"), nil)   // ⌃End,  was <C-d>
    expectToken(120, [.control], controlCharacter("p"), nil)   // ⌃F2,   was <C-p>

    // Bare F-keys and document keys passed only by accident (no character, so the
    // `< 0x20` guard dropped them). Now explicit.
    expectToken(122, [], "", nil)   // F1
    expectToken(90, [], "", nil)    // F20
    expectToken(115, [], "", nil)   // Home
    expectToken(121, [], "", nil)   // PgDn

    // ⌥ and Globe never reach the engine: ⌥j resolves to "∆", and 🌐E arrives as
    // a bare "e" — the fn bit is all that separates it from the word-end motion.
    expectToken(38, [.option], "∆", nil)
    expectToken(14, [.fn], "e", nil)             // 🌐E emoji picker

    // The engage key survives every one of those rejections, including ⌥: on
    // layouts where `[` itself needs Option, ⌃[ IS a ⌃⌥ chord, and losing it
    // would strand Normal mode. The keycode route is the layout-independent one.
    expectToken(33, [.control], "\u{1B}", "<C-[>")
    expectToken(33, [.control, .option], "\u{1B}", "<C-[>")
    expectToken(33, [.control], "ü", "<C-[>")    // German: keycode 33 prints ü

    let everything = CapabilityProfile(available: Set(Capability.allCases))
    let everythingButNative = CapabilityProfile(available: Set(Capability.allCases).subtracting([.nativeMotions]))
    for profile in [everything, everythingButNative, blindProfile, CapabilityProfile(available: [.nativeMotions])] {
        precondition(
            gateAdmits(profile) == engineExecutes(profile),
            "⌃-allowlist drifted from what the engine executes: gate \(gateAdmits(profile).sorted()) vs engine \(engineExecutes(profile).sorted())"
        )
    }
    precondition(gateAdmits(everythingButNative) == Set("rv"), "expected ⌃r and ⌃v: \(gateAdmits(everythingButNative).sorted())")
    precondition(gateAdmits(everything) == Set("rvfb"), "nativeMotions pages with ⌃f and ⌃b: \(gateAdmits(everything).sorted())")
}
