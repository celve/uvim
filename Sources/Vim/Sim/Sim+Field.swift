// MARK: - The fake field's keys and typing

extension Sim {
    /// As the Controller reads a caret: through the markers where it reads paragraphs, where selected breaks alone are no caret.
    func readsCaret(paragraphs: Bool) -> Bool {
        paragraphs && (markers || emptyParagraphs) ? selection.isEmpty : readSelection.isEmpty
    }

    /// Insert-mode passthrough typing lands in the fake field the way the
    /// real app would apply it.
    mutating func applyTyping(_ token: String) {
        if token == "<BS>" {
            if selection.isEmpty {
                selection = TextModel(text).advance(selection.lowerBound, byGraphemes: -1)..<selection.upperBound
            }
            applyReplace("")
            return
        }
        if token == "<CR>" {
            applyReplace("\n")
            return
        }
        guard token.count == 1, let scalar = token.unicodeScalars.first else { return }
        if scalar.value < 0x20, token != "\n", token != "\r", token != "\t" { return }
        applyReplace(token == "\r" ? "\n" : token)
    }
}

// MARK: - Running a plan in the fake field

extension Sim {
    /// The index of the step that ended the run, nil when every step ran; `generated` as the executor's.
    mutating func execute(_ steps: [PhysicalStep], generated: Bool = false, keys: Int? = nil) -> Int? {
        defer { landLateHistory() }
        let run = StepRunner.run(steps, generated: generated, keys: keys, host: &self)
        attribution = run.attribution
        softMisses += run.misses.filter { !$0.failed }.count
        if run.departure == nil, let miss = run.misses.last, miss.failed {
            settleFailures += 1
            if !miss.soft, miss.misfit == nil, let key = miss.expectation.blamed(observed: miss.read.selection) { blamed.append(key) }
        }
        return run.abortedAt
    }

    /// In `reads`' coordinates a boundary offset lands at the next paragraph's start.
    func landing(_ offset: Int) -> Int {
        if emptyParagraphs { return chromium.landing(offset, from: selection.lowerBound) }
        guard writesInReadOffsets, let reads else { return offset }
        return (0...text.utf16.count).last { reads($0, text) <= offset } ?? 0
    }

    /// A settle's verdict and what it read, judged as the executor judges it beside generated text (LIN-1930).
    func settles(
        _ expectation: Expectation, generated: Bool
    ) -> (passed: Bool, selection: Range<Int>?, length: Int, misfit: Range<Int>?) {
        // A non-answer satisfies nothing, exactly as `Expectation.matches` has it.
        let observed = unreadableSelection ? nil : readSelection
        let answered = observed != nil || expectation.landing == nil
        let length = fieldLength - drawnLength
        // The executor reads a side only where the expectation asks for one.
        let passed = expectation.passes(
            selection: observed, length: length, selectedText: readSelectedText,
            side: expectation.asksSide(at: observed) ? upperSide : nil, answered: answered, generated: generated
        ) { showsPlaceholder }
        let misfit = passed ? nil : expectation.misfit(selection: observed, length: length, selectedText: readSelectedText) {
            upperSide
        }
        return (passed, observed, fieldLength, misfit)
    }

    /// List markers are the page's, Chromium's own and `li::before`'s in Quill and Linear (LIN-2369); code labels are not.
    func generatesText(_ run: Range<Int>) -> Bool {
        guard emptyParagraphs, let lines = listLines else { return false }
        let drawn = lines.filter { $0.marker != nil && !$0.controls }
        return zip(chromium.listMarkers, drawn).contains { start, line in
            start <= run.lowerBound && run.upperBound <= start + (line.marker?.utf16.count ?? 0)
        }
    }

    /// The keys lane B counts with, which run whether or not `emulatesKeys` is on.
    static let countedKeys: Set<Chord> = [.left, .right, .up, .down, .lineStart, .selectRight, .selectLeft, .deleteBack]

    /// ⌘ menu equivalents, which an app the focus has left ignores (LIN-1105).
    static let menuChords: Set<Chord> = [.selectAll, .undo, .redo]

    /// One key as `KeyModel` has Cocoa's bindings do it, which is how LIN-1533 measured Chromium's arrows; false for
    /// a key the model does not know.
    mutating func press(_ chord: Chord) -> Bool {
        if chord == .undo { return undo() }
        if chord == .redo { return redo() }
        if atChipStart, [Key.arrowLeft, .arrowRight].contains(chord.key), !chord.modifiers.contains(.option) {
            atChipStart = false
            return true
        }
        atChipStart = false
        // Measured at some ends and not others, so always here: the first ← or ⇧← after a write at a code span's end.
        defer { atWrittenCodeEnd = false }
        if atWrittenCodeEnd, [.left, .selectLeft].contains(chord) { return true }
        // Measured: from inside a code span's start, ⇧⌃E does nothing, and ⇧→ too unless the span starts its line.
        if [.selectRight, Chord.paragraphEnd.shifted].contains(chord), selection.isEmpty, codeInside,
           isCodeEdge(selection.lowerBound, start: true),
           chord != .selectRight || TextModel(text).lineStart(of: selection.lowerBound) != selection.lowerBound {
            return true
        }
        if inListGap == nil, chord.modifiers.isEmpty, selection.isEmpty, [Key.arrowLeft, .arrowRight].contains(chord.key) {
            let at = selection.lowerBound
            let (start, end) = (isCodeEdge(at, start: true), isCodeEdge(at, start: false))
            // From the side of an edge the arrow points across, it steps inside or out and stays put, but ← leaves a paragraph.
            let crosses = chord.key == .arrowRight
                ? start && !codeInside || end && codeInside
                : start && codeInside && TextModel(text).lineStart(of: at) != at || end && !codeInside
            if crosses {
                codeInside.toggle()
                return true
            }
        }
        if holdsRightAtLineEnds, chord == .right, selection.isEmpty,
           TextModel(text).lineBreak(of: selection.lowerBound) == selection.lowerBound {
            return true
        }
        if chord == .deleteBack, runsAreNewlines, selection.isEmpty, selection.lowerBound > 0 {
            let model = TextModel(text)
            if model.lineStart(of: selection.lowerBound) == selection.lowerBound {
                selection = model.lineEnd(of: model.lineStart(of: selection.lowerBound - 1))..<selection.lowerBound
            }
        }
        let shown = chromium
        var keys = KeyModel(
            text: text,
            anchor: backward ? selection.upperBound : selection.lowerBound,
            focus: backward ? selection.lowerBound : selection.upperBound,
            wrap: wrapWidth,
            atoms: shown.atoms,
            gaps: shown.gaps,
            stops: shown.keyStops,
            cells: shown.cells,
            lastRows: shown.lastRows,
            inStop: inListGap
        )
        guard keys.press(chord) else { return false }
        inListGap = keys.inStop
        if keys.text != text {
            noteEdit(at: keys.selection.lowerBound, typing: true)
            let deleted = keys.selection.lowerBound..<(keys.selection.lowerBound + text.utf16.count - keys.text.utf16.count)
            listLines = listLines.map { ListLine.carried($0, in: text, replacing: deleted, with: "") }
            codeSpans = Self.carried(codeSpans, replacing: deleted, with: "", into: keys.text)
        }
        if keys.text == text, keys.selection != selection { coalescing = false }
        text = keys.text
        selection = pulledBack(keys.selection)
        backward = keys.focus < keys.anchor
        // Measured: → and ⌥→ arrive outside a start and inside an end, ← the reverse but at a line start, the rest outside.
        let arrived = selection.isEmpty ? selection.lowerBound : -1
        switch (chord.key, chord.modifiers) {
        case (.arrowRight, []), (.arrowRight, [.option]): codeInside = isCodeEdge(arrived, start: false)
        case (.arrowLeft, []):
            codeInside = isCodeEdge(arrived, start: true) && TextModel(text).lineStart(of: arrived) != arrived
        default: codeInside = false
        }
        if inListGap != nil { codeInside = false }
        return true
    }

    func pulledBack(_ range: Range<Int>) -> Range<Int> {
        guard pullsBackFromLineEnds else { return range }
        let model = TextModel(text)
        func pulled(_ offset: Int) -> Int {
            guard offset > 0, model.lineBreak(of: offset) == offset else { return offset }
            let before = model.advance(offset, byGraphemes: -1)
            return TextModel.isInvisible(Character(model.substring(before..<offset))) ? before : offset
        }
        return pulled(range.lowerBound)..<pulled(range.upperBound)
    }

    func isCodeEdge(_ offset: Int, start: Bool) -> Bool {
        listLines != nil && codeSpans.contains { (start ? $0.lowerBound : $0.upperBound) == offset }
    }

    /// `spans` after an edit into `text`, as ProseMirror's marks: inside one it stays in, at an edge out; they join, `\n` splits.
    private static func carried(_ spans: [Range<Int>], replacing range: Range<Int>, with replacement: String, into text: String)
        -> [Range<Int>] {
        let count = replacement.utf16.count
        let delta = count - range.count
        let kept = spans.compactMap { span -> Range<Int>? in
            let kept: Range<Int>
            if range.upperBound <= span.lowerBound {
                kept = (span.lowerBound + delta)..<(span.upperBound + delta)
            } else if range.lowerBound >= span.upperBound {
                kept = span
            } else if span.lowerBound <= range.lowerBound, range.upperBound <= span.upperBound {
                kept = span.lowerBound..<(span.upperBound + delta)
            } else if range.lowerBound <= span.lowerBound, span.upperBound <= range.upperBound {
                return nil
            } else if range.lowerBound < span.lowerBound {
                kept = (range.lowerBound + count)..<(span.upperBound + delta)
            } else {
                kept = span.lowerBound..<range.lowerBound
            }
            return kept.isEmpty ? nil : kept
        }.sorted { $0.lowerBound < $1.lowerBound }
        let joined: [Range<Int>] = kept.reduce(into: []) { joined, span in
            if let last = joined.last, last.upperBound >= span.lowerBound {
                joined[joined.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                joined.append(span)
            }
        }
        let units = Array(text.utf16)
        return joined.flatMap { span in
            var pieces: [Range<Int>] = []
            var start = span.lowerBound
            for index in span where index < units.count && units[index] == 10 {
                if index > start { pieces.append(start..<index) }
                start = index + 1
            }
            if span.upperBound > start { pieces.append(start..<span.upperBound) }
            return pieces
        }
    }

    /// Runs a cleanup, landing or release plan, pressing at most `keys` keys where it is given and keeping the command's evidence
    /// for its lesson; false when a step failed.
    @discardableResult
    mutating func executeAside(_ plan: PhysicalPlan, keys: Int? = nil) -> Bool {
        let evidence = attribution
        let aborted = execute(plan.steps, keys: keys)
        attribution = evidence
        return aborted == nil
    }

    /// The executor's check before each key: nil where the run stops there, else whether the field takes the key.
    mutating func posts(menu: Bool) -> Bool? {
        guard !departs() else { return nil }
        guard var leaves = focusLeaves else { return true }
        if leaves.after > 0 {
            leaves.after -= 1
            focusLeaves = leaves
            return true
        }
        guard leaves.unseen > 0 else {
            seen(leaves.by)
            return departs() ? nil : true
        }
        leaves.unseen -= 1
        focusLeaves = leaves
        if leaves.unseen == 0 { seen(leaves.by) }
        return leaves.by == .app && !menu
    }

    /// What the executor's reads find once the focus has gone: the click's presses, or the app inactive.
    private mutating func seen(_ move: KeyDestination.Departure) {
        focusLeaves = nil
        if move == .click { buttonEvents &+= 2 } else { appActive = false }
    }

    /// Whether the focus left, by the executor's reads.
    mutating func departs() -> Bool {
        guard var held = destination else { return false }
        if departure == nil {
            departure = held.departure(presses: buttonEvents, active: appActive)
            destination = held
        }
        return departure != nil
    }

    mutating func applyReplace(_ replacement: String) {
        noteEdit(at: selection.lowerBound, typing: false)
        listLines = listLines.map { ListLine.carried($0, in: text, replacing: selection, with: replacement) }
        let replaced = TextModel(text).replacing(selection, with: replacement)
        codeSpans = Self.carried(codeSpans, replacing: selection, with: replacement, into: replaced)
        codeInside = false
        atWrittenCodeEnd = false
        inListGap = nil
        text = replaced
        let caretAfter = selection.lowerBound + replacement.utf16.count
        selection = caretAfter..<caretAfter
        backward = false
    }
}
