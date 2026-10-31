// MARK: - Discovery carried across typing (LIN-1874)

// A node boundary at the run's offset moves with the leaf the run went into, which only a line break in AXValue shows.
func runLines(_ old: (value: String, markers: String), _ new: (value: String, markers: String)) -> (Discovery.Run, Discovery.Lines) {
    let edit = try! Discovery.run(markers: old.markers, value: old.value, to: new.markers, value: new.value).get()
    return (edit.run, Discovery.Lines(value: old.value, markers: old.markers, shown: edit.shown)!)
}

/// What a snapshot asks the walk for, with `AXValue` aligned to the marker text.
func documentRequest(_ value: String, _ raw: String, caret: Int? = 0, proseMirror: Bool = true, folds: Bool = true)
    -> FieldDocument.Request {
    // A text the marker text does not line up with, as a refused edit's, keeps no breaks.
    FieldDocument.Request(value: value, markers: raw, aligned: ParagraphBreaks(value: value, fieldText: MarkerText.plain(raw)) ?? ParagraphBreaks(),
                          caret: caret, proseMirror: proseMirror, folds: folds)
}
/// The runtime's walk over a fake tree, keeping what it read.
func documentWalk(_ request: FieldDocument.Request, _ tree: [FakeNode], roots: Int?, budget: Int = FieldDocument.readBudget,
                  why: Discovery.Rewalk = .first) -> FieldDocument.Memo {
    let recorder = Discovery.Recorder<FakeNode>(budget: budget, block: \.block, offset: { node, end in end ? node.end : node.start })
    let reads = TreeReads(budget: budget, block: recorder.block, offset: recorder.offset)
    let document = FieldDocument.walk(request, roots: { recorder.roots(tree) }, tree: reads)
    return FieldDocument.Memo(request: request, blocks: tree.count, roots: roots, document: document, reads: recorder.reads,
                              origin: .walked(why))
}
/// `spec` with `count` units typed (or deleted, below zero) into the text node at `path`: it and its ancestors change
/// length, and every node after it moves.
func typed(_ spec: String, _ count: Int, into path: String) -> String {
    let tokens = spec.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { $0.split(separator: "/").map(String.init) }
    let target = tokens.firstIndex { $0[0] == path }!
    return tokens.enumerated().map { index, token in
        let start = Int(token[2])!
        let end = Int(token[3])!
        if index == target || path.hasPrefix(token[0] + ".") { return [token[0], token[1], token[2], String(end + count)] }
        return index > target ? [token[0], token[1], String(start + count), String(end + count)] : token
    }.map { $0.joined(separator: "/") }.joined(separator: " ")
}
/// A Chromium build over a fake tree, walking it where a memo does not carry; `walks` says why each walk ran.
func treeBuild(
    _ value: String, _ raw: String, _ tree: [FakeNode], memo known: FieldDocument.Memo? = nil, caret: Int = 0,
    proseMirror: Bool = true
) -> (snapshot: FieldSnapshot, memo: FieldDocument.Memo?, walks: [Discovery.Rewalk]) {
    let aligned = ParagraphBreaks(value: value, fieldText: MarkerText.plain(raw))!
    var reads = FieldSnapshot.Reads(
        field: FieldReads(text: value, plain: caret..<caret, markers: MarkerReads(
            breaks: aligned, value: aligned.valueRange(caret..<caret) { _ in .start(skipping: 0) }
        )),
        length: value.utf16.count, webContent: true, blocks: tree.count, marked: caret..<caret, markerText: raw
    )
    reads.proseMirror = proseMirror
    reads.roots = proseMirror ? tree.count : nil
    var memo = known
    var walks: [Discovery.Rewalk] = []
    let built = FieldSnapshot.Step.run(taking: { need in
        switch need {
        case .side(let end): reads.sides.updateValue(.start(skipping: 0), forKey: end)
        case .emptyParagraph: reads.inEmptyParagraph = false
        case .document(let request, let why):
            walks.append(why)
            memo = documentWalk(request, tree, roots: reads.roots, why: why)
        }
    }) {
        FieldSnapshot.build(reads, capabilities: keyProfile, answer: .textContent, anchor: nil, cursor: nil, memo: memo)
    }
    return (built.snapshot, built.memo, walks)
}
func linedCandidates(_ value: String, _ plain: String) -> UnreachableLines.Candidates {
    UnreachableLines.candidates(text: value, breaks: ParagraphBreaks(value: value, fieldText: MarkerText.plain(plain))!, raw: plain)
}
/// Builds a field before and after an edit, carried and walked; nil when they differ.
func carriedEdit(
    _ before: (value: String, raw: String, spec: String), _ after: (value: String, raw: String, spec: String),
    carets: (Int, Int) = (0, 0), proseMirror: Bool = true, linear: Bool = true
) -> [Discovery.Rewalk]? {
    let old = treeBuild(before.value, before.raw, fakeTree(before.spec, linear: linear), caret: carets.0, proseMirror: proseMirror)
    let tree = fakeTree(after.spec, linear: linear)
    let carried = treeBuild(after.value, after.raw, tree, memo: old.memo, caret: carets.1, proseMirror: proseMirror)
    let walked = treeBuild(after.value, after.raw, tree, caret: carets.1, proseMirror: proseMirror)
    guard carried.snapshot == walked.snapshot, carried.memo?.document.emptyParagraphs == walked.memo?.document.emptyParagraphs,
          carried.memo?.document.exhausted == walked.memo?.document.exhausted,
          carried.memo?.document.found == walked.memo?.document.found
    else { return nil }
    return carried.walks
}
func edited(_ value: String, _ raw: String, _ spec: String, _ path: String, _ from: String, _ to: String)
    -> (value: String, raw: String, spec: String) {
    (value.replacing(from, with: to, maxReplacements: 1), raw.replacing(from, with: to, maxReplacements: 1),
     typed(spec, to.utf16.count - from.utf16.count, into: path))
}

// Chrome 153's blank line: typing elsewhere replays the walk, and anything else walks again.
func blankTree(_ paragraphs: [String]) -> [FakeNode] {
    var at = 0
    return paragraphs.map { text in
        defer { at += max(text.utf16.count, 1) }
        return text.isEmpty ? blank(at) : paragraph(at, at + text.utf16.count)
    }
}
func blankRequest(_ paragraphs: [String]) -> FieldDocument.Request {
    let shown = EmptyParagraphs.chromium(paragraphs)
    return documentRequest(shown.value, shown.markers, caret: nil, proseMirror: false, folds: false)
}
let blankMemo = documentWalk(blankRequest(blankParagraphs), blankTree(blankParagraphs), roots: nil)
func blankCarried(
    _ edit: (inout [String]) -> Void, memo: FieldDocument.Memo = blankMemo
) -> Result<FieldDocument.Memo, Discovery.Rewalk> {
    var paragraphs = blankParagraphs
    edit(&paragraphs)
    let carried = memo.carried(blankRequest(paragraphs), blocks: paragraphs.count, roots: nil)
    if case .success(let kept) = carried {
        let walked = documentWalk(blankRequest(paragraphs), blankTree(paragraphs), roots: nil, budget: memo.reads?.budget ?? 0)
        precondition(kept.document.emptyParagraphs == walked.document.emptyParagraphs
                     && kept.document.exhausted == walked.document.exhausted, "\(paragraphs)")
    }
    return carried
}

func testCarriedDiscovery() {
    let typedRun = Discovery.Run(from: "ab\u{FFFC}cd", to: "ab\u{FFFC}cxyd")!
    precondition(typedRun.at == 3 && typedRun.earliest == 3 && typedRun.inserted == 2 && typedRun.removed == 0)
    precondition([2, 3, 4].map { typedRun.shifted($0) } == [2, nil, 6] && typedRun.shifted(3, lands: .before) == 5
                 && typedRun.shifted(3, lands: .after) == 3)
    let deletedRun = Discovery.Run(from: "abcdef", to: "abef")!
    precondition(deletedRun.at == 2 && deletedRun.removed == 2
                 && [1, 2, 3, 4, 5].map { deletedRun.shifted($0) } == [1, nil, nil, 2, 3])
    precondition(deletedRun.shifted(2, lands: .after) == 2 && deletedRun.shifted(2, lands: .before) == nil)
    for (old, new) in [("abcd", "abxd"), ("abcd", "ab\ncd"), ("abcd", "ab\u{FFFC}cd"), ("abcd", "abcd"), ("abcd", "xabcdy")] {
        precondition(Discovery.Run(from: old, to: new) == nil, "\(new.debugDescription) is no one run of text")
    }
    let repeatedRun = Discovery.Run(from: "fooBar", to: "fooBBar")!
    precondition(repeatedRun.earliest == 3 && repeatedRun.at == 4 && repeatedRun.shifted(3) == nil
                 && repeatedRun.shifted(3, lands: .before) == nil && repeatedRun.shifted(4, lands: .before) == 5,
                 "a B typed beside a B may be on either side of the paragraph starting at 3")

    let (endRun, endLines) = runLines(("ab\ncd", "abcd"), ("abx\ncd", "abxcd"))
    let (startRun, startLines) = runLines(("ab\ncd", "abcd"), ("ab\nxcd", "abxcd"))
    let (inlineRun, inlineLines) = runLines(("abcd", "abcd"), ("abxcd", "abxcd"))
    precondition([1, 2, 3].map { endLines.boundary($0, endRun) } == [1, 3, 4] && startLines.boundary(2, startRun) == 2
                 && inlineLines.boundary(2, inlineRun) == nil, "before a break it moves, after one it stays, and with none it is either")
    let (cutRun, cutLines) = runLines(("abbc\nd", "abbcd"), ("abc\nd", "abcd"))
    precondition([1, 2, 3].map { cutLines.boundary($0, cutRun) } == [1, nil, 2], "a b deleted beside a b leaves the one between")
    // A run of newlines holding one of the text's own: which of them Chromium added is a guess, so neither order proves a side.
    for typedValue in ["TopX\n\n", "Top\nX\n"] {
        let (seamRun, seamLines) = runLines(("Top\n\n", "Top\u{FFFC}\n\u{FFFC}"), (typedValue, "Top\u{FFFC}X\n\u{FFFC}"))
        precondition(seamLines.boundary(3, seamRun) == nil, typedValue.debugDescription)
    }

    for (name, value, raw, spec, path, from, to) in [
        ("the end of a list item, where the next marker starts", dia1Value, dia1Raw, dia1Spec, "1.0.1.0", "Numbered one",
         "Numbered onexy"),
        ("a list marker the page renumbers", dia1Value, dia1Raw, dia1Spec, "9.1.0.0", "10.", "100."),
        ("before a chip", dia7Value, dia7Raw, dia7Spec, "1.0", "Two chips ", "Two chips xy"),
        ("where a chip's paragraph starts", dia7Value, dia7Raw, dia7Spec, "1.0", "Two chips ", "xyTwo chips "),
        ("after a chip", dia7Value, dia7Raw, dia7Spec, "1.4", " end.", "xy end."),
        ("in a paragraph with chips", dia7Value, dia7Raw, dia7Spec, "1.4", " end.", " exynd."),
        ("a chip's title the page changes", dia7Value, dia7Raw, dia7Spec, "1.1.0.4", "LIN-1645 Why", "LIN-1645 xWhy"),
    ] {
        let after = edited(value, raw, spec, path, from, to)
        precondition(after.value != value && after.raw != raw, name)
        precondition(carriedEdit((value, raw, spec), after) == [], "\(name): the walk replayed builds what a walk does")
    }
    // A code block's label Linear changes as you type, at its start, its end and inside it.
    let codeLabel = (value: "Before\nC\nabc\nAfter", raw: "BeforeCabcAfter",
                     spec: "0/G/0/6 0.0/T/0/6 1/B/6/10 1.0/N/6/7 1.1/D/7/10 1.1.0/T/7/10 2/G/10/15 2.0/T/10/15")
    let objectiveC = (value: "Before\nObjective-C\nabc\nAfter", raw: "BeforeObjective-CabcAfter", spec: typed(codeLabel.spec, 10, into: "1.0"))
    let cssLabel = (value: "Before\nCSS\nabc\nAfter", raw: "BeforeCSSabcAfter", spec: typed(codeLabel.spec, 2, into: "1.0"))
    precondition(carriedEdit(codeLabel, objectiveC) == [] && carriedEdit(codeLabel, cssLabel) == [],
                 "LIN-1874 round 1: a code label becoming Objective-C or CSS")
    // LIN-1874 round 3: a line the walk did not confirm, a chip over two lines, becomes one when the page deletes the second.
    let splitChip = (value: "Top\n\u{2060}\u{00A0}A\nB\nEnd", raw: "Top\u{2060}\u{00A0}ABEnd",
                     spec: "0/G/0/3 0.0/T/0/3 1/G/3/7 1.0/A/3/7 1.0.0/K/3/7 1.0.0.0/T/3/6 1.0.0.1/T/6/7 2/G/7/10 2.0/T/7/10")
    let splitObject = (value: "Top\n\u{2060}\u{00A0}A\nB\n\u{2022} Other", raw: "Top\u{2060}\u{00A0}AB\u{FFFC}\u{2022} Other",
                       spec: "0/G/0/3 0.0/T/0/3 1/G/3/7 1.0/A/3/7 1.0.0/G/3/6 1.0.0.0/T/3/6 1.0.1/G/6/7 1.0.1.0/T/6/7 "
                           + "1.0.1.1/I/7/7 2/L/7/14 2.0/G/7/14 2.0.0/M/7/9 2.0.1/T/9/14")
    precondition(unreachableScanned(fakeTree(splitChip.spec), linedCandidates(splitChip.value, splitChip.raw))?.chips == [])
    // With an object left on the emptied line, that line is a caret's no walk read, so it walks.
    for (field, path, walks) in [(splitChip, "1.0.0.1", [Discovery.Rewalk]()), (splitObject, "1.0.1.0", [.unread])] {
        let after = (field.value.replacing("A\nB\n", with: "A\n\n"), field.raw.replacing("AB", with: "A"), typed(field.spec, -1, into: path))
        precondition(carriedEdit(field, after) == walks, "\(after.0.debugDescription): the chip is confirmed")
    }
    // And a caret the selection makes a candidate where an object already was: the walk never read there, so it walks.
    let caretTail = (value: "ab\nnext", raw: "ab\u{FFFC}\nnext", spec: "0/G/0/3 0.0/D/0/2 0.0.0/T/0/2 0.1/E/2/3 1/G/3/7 1.0/T/3/7")
    precondition(carriedEdit(caretTail, ("a\nnext", "a\u{FFFC}\nnext", typed(caretTail.spec, -1, into: "0.0.0")), carets: (0, 1))
                 == [.unread])
    // LIN-1874 round 4: a text newline beside an added line break, typed before, in either order the run of newlines allows.
    for (field, path, before, raw) in [
        ((value: "Top\n\n", raw: "Top\u{FFFC}\n\u{FFFC}", spec: "0/G/0/3 0.0/T/0/3 1/E/3/3 2/G/3/4 2.0/T/3/4 3/I/4/4"), "2.0",
         "Top", "Top\u{FFFC}X\n\u{FFFC}"),
        ((value: "Top\n\nabc\nAfter", raw: "Top\nabcAfter",
          spec: "0/G/0/3 0.0/T/0/3 1/B/3/7 1.0/N/3/4 1.0.0/T/3/4 1.1/D/4/7 1.1.0/T/4/7 2/G/7/12 2.0/T/7/12"), "1.0.0", "Top", "TopX\nabcAfter"),
        ((value: "Top\n\n\u{2060}\u{00A0}Chip\nAfter", raw: "Top\n\u{2060}\u{00A0}ChipAfter",
          spec: "0/G/0/3 0.0/T/0/3 1/G/3/10 1.0/T/3/4 1.1/A/4/10 1.1.0/K/4/10 1.1.0.0/T/4/10 2/G/10/15 2.0/T/10/15"), "1.0", "Top",
         "TopX\n\u{2060}\u{00A0}ChipAfter"),
    ] {
        for typedValue in [field.value.replacing(before + "\n\n", with: before + "X\n\n"),
                           field.value.replacing(before + "\n\n", with: before + "\nX\n")] {
            let walks = carriedEdit(field, (typedValue, raw, typed(field.spec, 1, into: path)), carets: (3, 4))
            precondition(walks?.contains(.boundary) == true, "\(typedValue.debugDescription): \(walks.map { "\($0)" } ?? "differs")")
        }
    }

    // Chromium's own list: the page makes a paragraph an item with one run of marker text and no new block.
    let native = (value: "Top\n\u{2022} First\nMiddle\nPlain", raw: "Top\u{2022} FirstMiddlePlain",
                  spec: "0/G/0/3 0.0/T/0/3 1/L/3/10 1.0/G/3/10 1.0.0/M/3/5 1.0.1/T/5/10 2/G/10/16 2.0/T/10/16 3/G/16/21 3.0/T/16/21")
    let nativeMemo = documentWalk(documentRequest(native.value, native.raw, caret: nil, proseMirror: false),
                                  fakeTree(native.spec, linear: false), roots: nil)
    precondition(nativeMemo.document.found?.markers == [3..<5])
    func nativeRequest(_ value: String, _ raw: String, proseMirror: Bool = false) -> FieldDocument.Request {
        documentRequest(value, raw, caret: nil, proseMirror: proseMirror)
    }
    for (name, value, plain) in [("listed", "Top\n\u{2022} First\nMiddle\n\u{2022} Plain", "Top\u{2022} FirstMiddle\u{2022} Plain"),
                                 ("typed like one", "Top\n\u{2022} First\nMi. ddle\nPlain", "Top\u{2022} FirstMi. ddlePlain")] {
        precondition(nativeMemo.carried(nativeRequest(value, plain), blocks: 4, roots: nil) == .failure(.candidates),
                     "a paragraph \(name) gives a walk a line the last one never checked")
    }
    let typedNumber = documentWalk(nativeRequest("Top\n1. Buy", "Top1. Buy"),
                                   fakeTree("0/G/0/3 0.0/T/0/3 1/G/3/9 1.0/T/3/9", linear: false), roots: nil)
    precondition(typedNumber.document.found?.markers == [] && typedNumber.carried(
        nativeRequest("Top\n\u{2022} 1. Buy", "Top\u{2022} 1. Buy"), blocks: 2, roots: nil
    ) == .failure(.candidates), "and a line that already looked like an item, listed, is one line with another marker")
    precondition(carriedEdit(native, edited(native.value, native.raw, native.spec, "0.0", "Top", "Topx"), proseMirror: false,
                             linear: false) == [], "typing before the list still carries")
    let nativeTyped = (value: native.value.replacing("Top", with: "Topx"), raw: native.raw.replacing("Top", with: "Topx"))
    let typedRequest = nativeRequest(nativeTyped.value, nativeTyped.raw)
    precondition(nativeMemo.carried(nativeRequest(nativeTyped.value, nativeTyped.raw, proseMirror: true), blocks: 4, roots: nil)
                     == .failure(.roots)
                 && FieldDocument.Memo(request: nativeMemo.request, blocks: nil, document: nativeMemo.document)
                     .carried(typedRequest, blocks: nil, roots: nil) == .failure(.blocks),
                 "a count unread both times, or a ProseMirror field's roots unread both times, prove nothing unchanged")
    precondition(FieldDocument.Memo(request: nativeMemo.request, blocks: 4, document: nativeMemo.document)
                     .carried(typedRequest, blocks: 4, roots: nil) == .failure(.unread),
                 "a result whose reads were not kept walks")
    let twoRoots = documentWalk(nativeRequest("\u{2022} one\nTwo", "\u{2022} oneTwo"),
                                fakeTree("0/L/0/5 0.0/G/0/5 0.0.0/M/0/2 0.0.1/T/2/5 1/G/5/8 1.0/T/5/8", linear: false), roots: nil)
    let twoTyped = nativeRequest("\u{2022} one\nTwox", "\u{2022} oneTwox")
    precondition(FieldDocument.Memo(request: twoRoots.request, blocks: 1, document: twoRoots.document, reads: twoRoots.reads)
                     .carried(twoTyped, blocks: 1, roots: nil) == .failure(.unread)
                 && twoRoots.carried(twoTyped, blocks: 2, roots: nil).map(\.document.found?.markers) == .success([0..<2]),
                 "reads of a tree with other root blocks than the count")

    precondition(blankMemo.document.emptyParagraphs == [43] && blankCarried { _ in } == .success(blankMemo))
    let blankShifted = try! blankCarried { $0[0] = "Headingxy one" }.get()
    precondition(blankShifted.document.emptyParagraphs == [45]
                 && blankCarried { $0[3] = "Second" }.map(\.document.emptyParagraphs) == .success([43]))
    precondition(blankShifted.origin == .shifted(Discovery.Run(from: blankMarkers, to: "Headingxy one" + blankMarkers.dropFirst(11))!))
    precondition(blankCarried { $0[1] += "x" } == .failure(.boundary), "typed where its <br> starts")
    precondition(blankCarried { $0[2] = "x" } == .failure(.edit) && blankCarried { $0[0] = "Hx"; $0[6] = "Ly" } == .failure(.edit),
                 "typed in the blank line, or in two places")
    precondition(blankCarried { $0.insert("New", at: 1) } == .failure(.blocks))
    precondition(FieldDocument.Memo(request: documentRequest("ab\nc", "ab\nc", proseMirror: false, folds: false), blocks: nil,
                                    document: FieldDocument(markers: "ab\nc", emptyParagraphs: [2], found: nil))
                 .carried(documentRequest("axb\nc", "axb\nc", proseMirror: false, folds: false), blocks: nil, roots: nil) == .failure(.blocks))
    let failedBlank = FieldDocument.Memo(request: blankRequest(blankParagraphs), blocks: blankParagraphs.count,
                                         document: FieldDocument(markers: blankMarkers, emptyParagraphs: nil, found: nil))
    precondition(blankCarried({ $0[0] = "Headingxy one" }, memo: failedBlank) == .failure(.failed), "a failed read is read again")
    for budget in [3, 8] {
        let exhausted = documentWalk(blankRequest(blankParagraphs), blankTree(blankParagraphs), roots: nil, budget: budget)
        precondition(exhausted.document.emptyParagraphs == nil && exhausted.document.exhausted == .emptyParagraphs, "\(budget)")
        precondition(try! blankCarried({ $0[0] = "Headingxy one" }, memo: exhausted).get().document.exhausted == .emptyParagraphs,
                     "a walk past its budget, replayed, runs out again: \(budget)")
    }
    let blankTypedMarkers = EmptyParagraphs.chromium(blankParagraphs.dropLast() + ["Last paragraph herexy."]).markers
    precondition(blankMemo.carried(documentRequest(blankValue + "y", blankTypedMarkers, caret: nil, proseMirror: false, folds: false),
                                   blocks: blankParagraphs.count, roots: nil) == .failure(.value))

    // Enter in a list adds an item but no root block, and the marker text gains only "•z": AXValue's new lines refuse it.
    let dia7Before = treeBuild(dia7Value, dia7Raw, dia7Tree)
    let newItemRaw = dia7Raw.replacing("Plain itemClosing", with: "Plain item\u{2022}zClosing")
    let newItemValue = dia7Value.replacing("Plain item\nClosing", with: "Plain item\n\u{2022}\nz\nClosing")
    precondition(Discovery.Run(from: dia7Raw, to: newItemRaw)?.inserted == 2
                 && dia7Before.memo?.carried(documentRequest(newItemValue, newItemRaw), blocks: dia7Tree.count, roots: dia7Tree.count)
                     == .failure(.value))

    precondition(ChromiumParagraphs(text: "a \u{2060} b\nc \u{2060}\n\u{2060} d", lines: [Sim.ListLine(), Sim.ListLine(), Sim.ListLine()]).shown
                 == ("a \n\u{2060}\u{00A0}LIN-1 chip\n b\nc \n\u{2060}\u{00A0}LIN-1 chip\n\u{2060}\u{00A0}LIN-1 chip\n d",
                     "a \u{2060}\u{00A0}LIN-1 chip bc \u{2060}\u{00A0}LIN-1 chip\n\u{2060}\u{00A0}LIN-1 chip d", []),
                 "a chip is a line of its own, and one ending its paragraph has a <br> after it")
    precondition(ChromiumParagraphs(text: "a \u{2060} \u{2060} b\nc \u{2060} ", lines: [Sim.ListLine(), Sim.ListLine()]).shown.value
                 == "a \n\u{2060}\u{00A0}LIN-1 chip \n\u{2060}\u{00A0}LIN-1 chip\n b\nc \n\u{2060}\u{00A0}LIN-1 chip ",
                 "spaces after a chip share its line")
    for paragraphs in [["L", "", "N"], ["", "L"], ["L", ""], [""], ["a", "", "bc", "", "", "d", ""]] {
        let host = ChromiumParagraphs(text: paragraphs.joined(separator: "\n"), lines: paragraphs.map { _ in Sim.ListLine() })
        precondition(host.shown == EmptyParagraphs.chromium(paragraphs) && host.plainMarkers == host.shown.markers,
                     "without markers or leaves, Linear's lines are Chrome 153's")
    }
    precondition(ChromiumParagraphs(text: "a\nb", lines: [Sim.ListLine(), Sim.ListLine(marker: "1.", leaves: 1)]).shown
                 == ("a\n1.\n\nb", "a1.\u{FFFC}b", []))
    let bullet = Sim.ListLine(marker: "\u{2022} ", inline: true)
    precondition(ChromiumParagraphs(text: "a\nb\n\nc", lines: [Sim.ListLine(), bullet, bullet, bullet]).shown
                 == ("a\n\u{2022} b\n\u{2022} \n\u{2022} c", "a\u{2022} b\u{2022} \n\u{2022} c", []),
                 "Chromium's own list keeps each marker on its item's line")
}
