func plan(_ source: String, state: VimState = .initial) -> LogicalPlan {
    LogicalPlanner.plan(RawCommand(source), state: state)
}

func deleting(_ expectation: Expectation, _ selection: Range<Int>, before length: Int?) -> Expectation {
    var deleting = expectation
    deleting.deletes = selection
    deleting.lengthBefore = length
    return deleting
}
func checkingWrite(_ expectation: Expectation) -> Expectation {
    var checking = expectation
    checking.checksWrite = true
    return checking
}

func physical(
    _ keys: String,
    text: String? = nil,
    caret: Int? = nil,
    selection: Range<Int>? = nil,
    profile: CapabilityProfile,
    state: VimState = .initial
) -> PhysicalPlan {
    let logical = LogicalPlanner.plan(RawCommand(keys), state: state)
    let snapshot = FieldSnapshot(capabilities: profile, text: text, selection: selection ?? caret.map { $0..<$0 })
    return PhysicalPlanner.plan(logical, snapshot: snapshot)
}

func adding(_ extra: Set<Capability>, to profile: CapabilityProfile) -> CapabilityProfile {
    var statuses = profile.statuses
    for capability in extra { statuses[capability] = .available }
    return CapabilityProfile(statuses: statuses)
}
func removing(_ gone: Set<Capability>, from profile: CapabilityProfile) -> CapabilityProfile {
    var statuses = profile.statuses
    for capability in gone { statuses[capability] = .unavailable }
    return CapabilityProfile(statuses: statuses)
}

// In web content only a selection left behind is blamed.
func webPhysical(
    _ keys: String, text: String, caret: Int, profile: CapabilityProfile, breaks: ParagraphBreaks? = nil
) -> PhysicalPlan {
    PhysicalPlanner.plan(LogicalPlanner.plan(RawCommand(keys), state: .initial),
                         snapshot: FieldSnapshot(capabilities: profile, text: text, selection: caret..<caret, webContent: true,
                                                 breaks: breaks))
}

// `chromium`: reads fall short by one per paragraph break.
func keyedSim(_ text: String, caret: Int, profile: CapabilityProfile = nativeRead, chromium: Bool = false) -> Sim {
    var keyed = Sim(text: text, caret: caret, profile: profile)
    keyed.emulatesKeys = true
    keyed.reads = chromium ? omitsBreaks : nil
    return keyed
}

/// A Chromium `<p>` editor: every `\n` is a generated paragraph break.
func paragraphPlanning(
    _ keys: String, text: String, caret: Int, profile: CapabilityProfile, state: VimState = .initial
) -> PhysicalPlanner.Planning {
    let breaks = ParagraphBreaks(offsets: text.utf16.enumerated().filter { $0.element == 10 }.map(\.offset))
    let snapshot = FieldSnapshot(capabilities: profile, text: text, selection: caret..<caret, breaks: breaks)
    return PhysicalPlanner.planning(LogicalPlanner.plan(RawCommand(keys), state: state), snapshot: snapshot)
}

/// For each step that deletes or types, the text the settle right before it checks.
func checkedTexts(_ plan: PhysicalPlan) -> [String?] {
    var texts: [String?] = []
    for (index, step) in plan.steps.enumerated() {
        switch step {
        case .press(.deleteBack, _), .typeText, .replaceSelection:
            if index > 0, case .settle(let expectation) = plan.steps[index - 1] {
                texts.append(expectation.selectedText)
            } else {
                texts.append(nil)
            }
        default:
            break
        }
    }
    return texts
}

/// The control character a ⌃-letter arrives as: ⌃a is U+0001.
func controlCharacter(_ letter: Character) -> String {
    String(UnicodeScalar(letter.asciiValue! - 96))
}

func typed(_ keys: String, text: String, caret: Int, profile: CapabilityProfile) -> Sim {
    var host = Sim(text: text, caret: caret, profile: profile)
    host.type(keys)
    return host
}

/// Chromium's rule 1 (LIN-1533): the read leaves out the breaks before the caret.
func omitsBreaks(_ offset: Int, _ text: String) -> Int {
    offset - TextModel(text).newlineCount(in: 0..<offset)
}
func checkedText(_ step: PhysicalStep?) -> String? {
    guard case .settle(let expectation)? = step else { return nil }
    return expectation.selectedText
}

// The rule itself (LIN-1855): elements are numbers here, 100 and 200 two pages, and a site is its role.
typealias Focus = FocusTransition.Focus<Int, String>

func edge(_ old: Focus?, _ new: Focus?) -> FocusTransition { FocusTransition.between(old, new) }

func committing(_ store: inout BeliefStore, _ capability: Capability, at rung: String = learnRung,
                under offsets: OffsetsAnswer = .value, versions: Versions = learnVersions) -> Bool {
    store.commit(broken: capability, at: rung, judgedUnder: offsets, versions: versions, provenance: Provenance(tag: "e1.c1"))
}

func broken(_ store: BeliefStore, rung: String = learnRung, versions: Versions = learnVersions) -> Set<Capability> {
    store.resolve(rungs: [rung], rung: rung, versions: versions, start: .value, children: true, userPinsOffsets: false).broken
}

func traced(
    _ keys: String, text: String? = nil, caret: Int? = nil, profile: CapabilityProfile
) -> PhysicalPlanner.Planning {
    PhysicalPlanner.planning(
        LogicalPlanner.plan(RawCommand(keys), state: .initial),
        snapshot: FieldSnapshot(capabilities: profile, text: text, selection: caret.map { $0..<$0 })
    )
}

func chords(_ plan: PhysicalPlan) -> [Chord] {
    plan.steps.flatMap { step -> [Chord] in
        switch step {
        case .press(let chord, let count): return Array(repeating: chord, count: count)
        default: return []
        }
    }
}

func judged(_ expectation: Expectation, _ observed: Range<Int>) -> Evidence? {
    var run = RunAttribution()
    run.record(.settle(expectation), passed: false, selection: observed)
    return run.evidence.first
}
func key(_ capability: Capability, _ outcome: Evidence.Outcome, _ why: Evidence.Why) -> Evidence {
    Evidence(.key(capability), outcome, why: why, seen: .settle(0))
}

func chromiumSim(_ text: String, caret: Int, profile: CapabilityProfile, markers: Bool, chromium: Bool = false,
                 store: BeliefStore = BeliefStore()) -> Sim {
    var host = Sim(text: text, caret: caret, profile: profile)
    host.reads = omitsBreaks
    host.writesInReadOffsets = true
    host.markers = markers
    host.emulatesKeys = true
    host.learn(with: Sim.Learner(store: store, chromium: chromium, probed: profile))
    return host
}

func settleTraces(_ plan: PhysicalPlan) -> [String] {
    plan.steps.compactMap { step in
        switch step {
        case .settle(let expectation): return expectation.traceFields
        case .softSettle(let expectation): return "soft " + expectation.traceFields
        default: return nil
        }
    }
}

func blankSim(_ paragraphs: [String], caret: Int, profile: CapabilityProfile = keyProfile) -> Sim {
    var host = Sim(text: paragraphs.joined(separator: "\n"), caret: caret, profile: profile)
    host.emptyParagraphs = true
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}

// The scan over a fake tree: role, subrole, children and plain offsets as Chromium's would read.
final class FakeNode {
    let role: String
    let subrole: String?
    let start: Int
    let end: Int
    let children: [FakeNode]
    var fails = false
    var classes: [String] = []
    var quoteLevel = 0
    var generated = false

    init(_ role: String, _ subrole: String? = nil, _ start: Int, _ end: Int, _ children: [FakeNode] = []) {
        self.role = role
        self.subrole = subrole
        self.start = start
        self.end = end
        self.children = children
    }

    var block: EmptyBlockScan<FakeNode>.Block? {
        fails ? nil : .init(
            role: role, subrole: subrole, children: children, classes: classes, quoteLevel: quoteLevel, generated: generated
        )
    }
}
func text(_ start: Int, _ end: Int) -> FakeNode { FakeNode("AXStaticText", nil, start, end) }
func paragraph(_ start: Int, _ end: Int) -> FakeNode { FakeNode("AXGroup", nil, start, end, [text(start, end)]) }
func blank(_ at: Int) -> FakeNode { FakeNode("AXGroup", "AXEmptyGroup", at, at + 1) }
func scanned(_ blocks: [FakeNode], _ plain: String, budget: Int = EmptyParagraphs.readBudget) -> [Int]? {
    var scan = EmptyBlockScan<FakeNode>(budget: budget, block: \.block, offset: { node, end in end ? node.end : node.start })
    return scan.run(blocks: blocks, plain: Array(plain.utf16))
}

/// `path/role/start/end` per node, roles abbreviated, as softlash/LIN-1652 scripts/list-probe prints a tree; B is one of
/// Linear's `block-node` groups, Q one that is a quote, N a `node-controls` group and R a rule; roots carry Linear's classes,
/// which `linear` false leaves out. X is a table, Y its `AXTable`, O a row, U a column and Z a collapsible section
/// (LIN-1780), W a cell; a `g` after the code marks a node the page generates (LIN-2369), and a fifth field is a node's blockquote level,
/// where it sits inside a quote.
func fakeTree(_ spec: String, linear: Bool = true) -> [FakeNode] {
    let roles: [Character: (String, String?)] = [
        "L": ("AXList", "AXContentList"), "G": ("AXGroup", nil), "T": ("AXStaticText", nil), "H": ("AXHeading", nil),
        "E": ("AXGroup", "AXEmptyGroup"), "A": ("AXGroup", "AXApplicationGroup"), "K": ("AXLink", nil),
        "I": ("AXImage", nil), "C": ("AXCheckBox", nil), "P": ("AXPopUpButton", nil), "M": ("AXListMarker", nil),
        "D": ("AXGroup", "AXCodeStyleGroup"), "S": ("AXGroup", "AXStrongStyleGroup"), "F": ("AXGroup", "AXEmphasisStyleGroup"),
        "B": ("AXGroup", nil), "Q": ("AXGroup", nil), "N": ("AXGroup", nil), "R": ("AXSplitter", nil),
        "X": ("AXGroup", nil), "Y": ("AXTable", nil), "O": ("AXRow", nil), "U": ("AXColumn", nil),
        "Z": ("AXGroup", "AXLandmarkRegion"), "J": ("AXButton", nil), "W": ("AXCell", nil),
    ]
    var nodes: [[Int]: (code: Character, generated: Bool, start: Int, end: Int, level: Int?)] = [:]
    for token in spec.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
        let parts = token.split(separator: "/")
        nodes[parts[0].split(separator: ".").map { Int($0)! }]
            = (parts[1].first!, parts[1].dropFirst() == "g", Int(parts[2])!, Int(parts[3])!, parts.count > 4 ? Int(parts[4])! : nil)
    }
    func build(_ path: [Int]) -> FakeNode {
        let node = nodes[path]!
        let children = (0...).prefix { nodes[path + [$0]] != nil }.map { build(path + [$0]) }
        let built = FakeNode(roles[node.code]!.0, roles[node.code]!.1, node.start, node.end, children)
        if linear, "BQ".contains(node.code) { built.classes = [Linear.blockClass] }
        if linear, node.code == "N" { built.classes = [Linear.controlsClass] }
        if linear, node.code == "X" { built.classes = [Linear.tableClass] }
        if linear, node.code == "Z" { built.classes = [Linear.sectionClass, Linear.blockClass] }
        if linear, path.count == 1, let kind = ["G": "text-node", "E": "text-node", "L": "list-node", "H": "heading-node"][node.code] {
            built.classes = [kind]
        }
        // A list inside a quote or a section carries Linear's class as a root list does.
        if linear, path.count > 1, node.code == "L" { built.classes = [Linear.listClass] }
        built.generated = node.generated
        if node.code == "Q" { built.quoteLevel = 1 }
        if let level = node.level { built.quoteLevel = level }
        return built
    }
    return (0...).prefix { nodes[[$0]] != nil }.map { build([$0]) }
}
func unreachableScanned(
    _ blocks: [FakeNode], _ candidates: UnreachableLines.Candidates, budget: Int = UnreachableLines.readBudget
) -> UnreachableLines.Found? {
    var scan = UnreachableScan<FakeNode>(budget: budget, block: \.block, offset: { node, end in end ? node.end : node.start })
    return scan.run(blocks: blocks, candidates: candidates)
}
func folded(_ value: String, _ raw: String, _ tree: [FakeNode], proseMirror: Bool = true) -> UnreachableLines.Model {
    let plain = MarkerText.plain(raw)
    let aligned = ParagraphBreaks(value: value, fieldText: plain)!
    let restored = EmptyParagraphs.restore(value: value, fieldText: plain, aligned: aligned, found: scanned(tree, plain)!)!
    let candidates = UnreachableLines.candidates(text: restored.text, breaks: restored.breaks, raw: raw, proseMirror: proseMirror)
    return UnreachableLines.fold(text: restored.text, breaks: restored.breaks, raw: raw,
                                 found: unreachableScanned(tree, candidates)!)
}
func roundTrips(_ model: UnreachableLines.Model) -> Bool {
    let units = Array(model.text.utf16)
    return (0...units.count).allSatisfy { caret in
        let field = model.breaks.fieldOffset(caret)
        let side: ParagraphBreaks.Side = caret == 0 || units[caret - 1] == 10 ? .start(skipping: 0) : .end
        return model.breaks.valueRange(field..<field) { _ in side } == caret..<caret
    }
}

func lineStart(of needle: String, in text: String) -> Int {
    var offset = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix(needle) { return offset }
        offset += line.utf16.count + 1
    }
    preconditionFailure(needle)
}

func blockSim(_ profile: CapabilityProfile, _ doc: [(String, Sim.ListLine)] = blockDoc, caret: Int = 0) -> Sim {
    var host = Sim(text: doc.map(\.0).joined(separator: "\n"), caret: caret, profile: profile)
    host.emptyParagraphs = true
    host.listLines = doc.map(\.1)
    host.emulatesKeys = true
    host.readModel = .textContent
    return host
}
