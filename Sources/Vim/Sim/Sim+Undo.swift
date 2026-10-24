extension Sim {
    /// An undo held past the Controller's wait shows now.
    mutating func releaseHeldHistory() {
        for chord in heldHistory where !ignoredChords.contains(chord) { _ = press(chord) }
        heldHistory = []
    }

    mutating func noteEdit(at offset: Int, typing: Bool) {
        if typing, coalescing, let last = undoGroups.indices.last {
            undoGroups[last].at = min(undoGroups[last].at, offset)
        } else {
            undoGroups.append((before: text, at: offset, listLines: listLines, codeSpans: codeSpans))
        }
        redoGroups = []
        coalescing = typing
    }

    mutating func landLateHistory() {
        for chord in lateHistory where !ignoredChords.contains(chord) { _ = press(chord) }
        lateHistory = []
    }

    /// ⌘Z: the newest group's text back, selected as `undoSelection` has this host select it.
    mutating func undo() -> Bool {
        guard let group = undoGroups.popLast() else { return true }
        redoGroups.append((group: group, after: text, listLines: listLines, codeSpans: codeSpans))
        let restored = group.before.utf16.count - text.utf16.count
        (text, listLines, codeSpans) = (group.before, group.listLines, group.codeSpans)
        (coalescing, codeInside, atWrittenCodeEnd, inListGap, atChipStart, backward) = (false, false, false, nil, false, false)
        let put = TextModel(text).substring(group.at..<group.at + max(0, restored)).utf16
        let toBreak = put.firstIndex(of: 10).map { put.distance(from: put.startIndex, to: $0) }
        let length = switch undoSelection {
        case .restored: put.count
        case .throughBreak: toBreak.map { $0 + 1 } ?? put.count
        case .toBreak: toBreak ?? put.count
        case .start: 0
        }
        selection = undoSelection == .start ? 0..<0 : group.at..<group.at + length
        return true
    }

    /// ⇧⌘Z: the newest undone group's edit again, the caret where it began.
    mutating func redo() -> Bool {
        guard let undone = redoGroups.popLast() else { return true }
        undoGroups.append(undone.group)
        (text, listLines, codeSpans) = (undone.after, undone.listLines, undone.codeSpans)
        (coalescing, codeInside, atWrittenCodeEnd, inListGap, atChipStart, backward) = (false, false, false, nil, false, false)
        let at = TextModel(text).clamp(undone.group.at)
        selection = at..<at
        return true
    }
}
