/// Cocoa's standard key bindings over plain text, as measured in `NSTextView`: where the planner expects lane B's
/// keys to land, and what the Sim's field does with them.
struct KeyModel {
    var text: String
    var anchor: Int
    var focus: Int

    /// Graphemes per visual row for ↓ ↑ ⌘← ⌘→; nil lays each line on one row.
    var wrap: Int?

    /// Offsets of chips, where Linear's shifted ⌃A and ⌃E stop (LIN-1652).
    var atoms: Set<Int> = []

    /// Starts of lines a plain → or ↓ from the line above, or ↑ from them, leaves only after a stop between two blocks (LIN-1686).
    var gaps: Set<Int> = []

    /// Each line start's stops, top first, where they are more than `gaps` says (LIN-1780).
    var stops: [Int: [ParagraphBreaks.Hidden.Kind]] = [:]

    /// Starts of table lines, which ⌥→ from their end leaves for the next line, and of tables' last rows' first lines.
    var cells: Set<Int> = []
    var lastRows: Set<Int> = []

    /// The stop the caret is at: the start of the line it comes before, and its place among that line's stops, top first.
    var inStop: Stop?

    struct Stop: Equatable {
        let line: Int
        let index: Int
    }

    /// The caret is in a stop, before the line after `focus`.
    var inGap: Bool { inStop != nil }

    var selection: Range<Int> { min(anchor, focus)..<max(anchor, focus) }

    /// Applies one press; false for a key the model does not know.
    mutating func press(_ chord: Chord) -> Bool {
        let model = TextModel(text)
        if let at = inStop, let left = leave(at, chord, in: model) { return left }
        let shift = chord.modifiers.contains(.shift)
        let collapsed = anchor == focus
        if !shift, collapsed, let entered = enter(chord, in: model) {
            focus = entered.line - 1
            anchor = focus
            inStop = entered
            return true
        }
        if !shift, collapsed, let crossed = crossTable(chord, in: model) {
            guard let crossed else { return false }
            focus = crossed
            anchor = crossed
            return true
        }
        let moved: Int
        switch Chord(chord.key, chord.modifiers.subtracting(.shift)) {
        case .deleteBack where !shift:
            let range = collapsed ? model.advance(focus, byGraphemes: -1)..<focus : selection
            text = model.replacing(range, with: "")
            anchor = range.lowerBound
            focus = range.lowerBound
            return true
        case .left:
            moved = !shift && !collapsed ? selection.lowerBound : model.advance(focus, byGraphemes: -1)
        case .right:
            moved = !shift && !collapsed ? selection.upperBound : model.advance(focus, byGraphemes: 1)
        case .paragraphStart:
            let from = shift ? focus : selection.lowerBound
            let start = model.lineStart(of: from)
            moved = shift ? atoms.map { $0 + 1 }.filter { start < $0 && $0 <= from }.max() ?? start : start
        case .paragraphEnd:
            let from = shift ? focus : selection.upperBound
            let end = model.lineBreak(of: from)
            moved = shift ? atoms.filter { from <= $0 && $0 < end }.min() ?? end : end
        case .documentStart:
            moved = 0
        case .documentEnd:
            moved = model.length
        case .selectAll where !shift:
            anchor = 0
            focus = model.length
            return true
        case .lineStart:
            moved = row(of: shift ? focus : selection.lowerBound, in: model).start
        case .lineEnd:
            moved = row(of: shift ? focus : selection.upperBound, in: model).end
        case .down:
            moved = vertical(from: shift ? focus : selection.upperBound, by: 1, in: model)
        case .up:
            moved = vertical(from: shift ? focus : selection.lowerBound, by: -1, in: model)
        case .wordRight:
            moved = wordEnd(from: shift ? focus : selection.upperBound, in: model)
        case .wordLeft:
            moved = wordStart(from: shift ? focus : selection.lowerBound, in: model)
        case .paragraphForward where !shift:
            let from = selection.upperBound
            moved = from < model.length ? model.lineBreak(of: model.advance(from, byGraphemes: 1)) : from
        case .paragraphBackward where !shift:
            let from = selection.lowerBound
            moved = from > 0 ? model.lineStart(of: model.advance(from, byGraphemes: -1)) : 0
        case .pageForward where !shift:
            moved = (0..<Self.pageRows).reduce(selection.upperBound) { at, _ in vertical(from: at, by: 1, in: model) }
        case .pageBackward where !shift:
            moved = (0..<Self.pageRows).reduce(selection.lowerBound) { at, _ in vertical(from: at, by: -1, in: model) }
        default:
            return false
        }
        focus = moved
        if !shift { anchor = moved }
        return true
    }

    static let pageRows = 10

    /// The stops before the line starting at `line`, top first.
    private func stops(before line: Int) -> [ParagraphBreaks.Hidden.Kind] {
        stops[line] ?? (gaps.contains(line) ? [.gap] : [])
    }

    enum Way {
        case right, left, up, down
    }

    /// Which plain arrows stop at a stop, as measured in Linear (LIN-1686, LIN-1726, LIN-1780).
    static func visits(_ kind: ParagraphBreaks.Hidden.Kind, _ way: Way) -> Bool {
        switch kind {
        case .gap, .boxedGap: return way != .left
        case .upGap: return way == .up
        case .rule, .ruleGap: return true
        case .backGap: return way == .left || way == .up
        default: return false
        }
    }

    /// The stop the press enters: → from a line's end, ↓ from its last row, ← from the next line's start or ↑ from its first row.
    private func enter(_ chord: Chord, in model: TextModel) -> Stop? {
        func first(_ line: Int, _ way: Way) -> Stop? {
            stops(before: line).firstIndex { Self.visits($0, way) }.map { Stop(line: line, index: $0) }
        }
        func last(_ line: Int, _ way: Way) -> Stop? {
            stops(before: line).lastIndex { Self.visits($0, way) }.map { Stop(line: line, index: $0) }
        }
        switch chord {
        case .right:
            guard focus < model.length, model.graphemes(from: focus, toLineEnd: true, atMost: 0) == 0 else { return nil }
            return first(focus + 1, .right)
        case .down:
            let end = model.lineBreak(of: focus)
            guard end < model.length, row(of: focus, in: model).end == end else { return nil }
            return first(end + 1, .down)
        case .left:
            guard focus > 0, model.lineStart(of: focus) == focus else { return nil }
            return last(focus, .left)
        case .up:
            let start = model.lineStart(of: focus)
            guard start > 0, row(of: focus, in: model).start == start else { return nil }
            return last(start, .up)
        default:
            return nil
        }
    }

    /// The press from a stop, as measured in Linear; nil for a key that acts from the line above's end.
    private mutating func leave(_ at: Stop, _ chord: Chord, in model: TextModel) -> Bool? {
        let kinds = stops(before: at.line)
        let kind = kinds[at.index]
        func next(_ way: Way) -> Int? { kinds.indices.first { $0 > at.index && Self.visits(kinds[$0], way) } }
        func previous(_ way: Way) -> Int? { kinds.indices.last { $0 < at.index && Self.visits(kinds[$0], way) } }
        var landing: Int
        switch chord {
        case .right, .down:
            if let index = next(chord == .right ? .right : .down) {
                inStop = Stop(line: at.line, index: index)
                return true
            }
            landing = at.line
        case .selectRight where kind == .gap || kind == .boxedGap:
            guard next(.right) == nil else { return false }
            landing = at.line
        case .left, .up:
            if let index = previous(chord == .left ? .left : .up) {
                inStop = Stop(line: at.line, index: index)
                return true
            }
            if chord == .left || kind == .rule || kind == .backGap {
                // ↑ through a rule, or the stop between one and a table above it, lands at the line above's end, as ← does.
                landing = at.line - 1
            } else if isBelowTable(at.line, in: model) {
                guard let table = lastRow(of: model.lineStart(of: at.line - 1), in: model) else { return false }
                landing = table
            } else {
                landing = row(of: at.line - 1, in: model).start
            }
        case .paragraphStart where kind == .rule:
            // ⌃A on a selected rule goes to the line below it.
            landing = at.line
        case .paragraphStart, .paragraphEnd, Chord.paragraphStart.shifted, Chord.paragraphEnd.shifted:
            return kind == .rule ? false : true
        default:
            guard kind != .rule else { return false }
            inStop = nil
            return nil
        }
        focus = landing
        anchor = landing
        inStop = nil
        return true
    }

    /// Table moves Linear makes its own; nil where the press is not one, `.some(nil)` where the model cannot tell.
    private func crossTable(_ chord: Chord, in model: TextModel) -> Int?? {
        guard !cells.isEmpty else { return nil }
        let line = model.lineStart(of: focus)
        switch chord {
        case .wordRight where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            // ⌥→ at a cell's end goes to the next line's start, past any stop after the table.
            return focus + 1
        case .right where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            // Where a closed block follows a table, → from a last-row cell's end leaves the table for the stop between them.
            guard let after = lineAfterTable(from: line, in: model), lastRow(of: line, in: model).map({ $0 <= line }) == true,
                  stops(before: after).contains(where: { Self.visits($0, .right) }) else { return nil }
            return .some(nil)
        case .left where line == focus && isBelowTable(line, in: model):
            // ← from the line right below a table skips the table to the end of the line above it.
            guard !stops(before: line).contains(where: { Self.visits($0, .left) }) else { return nil }
            let first = firstLine(ofTableAbove: line, in: model)
            return first > 0 ? .some(first - 1) : .some(nil)
        case .up where row(of: focus, in: model).start == line && line > 0:
            if isBelowTable(line, in: model) {
                // From column 0 ↑ enters the last row's first cell; elsewhere where the caret's x falls.
                guard !stops(before: line).contains(where: { Self.visits($0, .up) }) else { return nil }
                guard focus == line, let table = lastRow(of: model.lineStart(of: line - 1), in: model) else { return .some(nil) }
                return .some(table)
            }
            // ↑ and ↓ go by rows in a table, which the model does not lay out.
            return cells.contains(line) ? .some(nil) : nil
        case .down:
            let end = model.lineBreak(of: focus)
            guard end < model.length, row(of: focus, in: model).end == end else { return cells.contains(line) ? .some(nil) : nil }
            if cells.contains(line) { return .some(nil) }
            // ↓ into a table lands at the caret's x, which only column 0 tells.
            return cells.contains(end + 1) && !stops(before: end + 1).contains(where: { Self.visits($0, .down) })
                ? (focus == line ? .some(end + 1) : .some(nil)) : nil
        default:
            return nil
        }
    }

    /// The line starting at `line` comes right after a table.
    private func isBelowTable(_ line: Int, in model: TextModel) -> Bool {
        line > 0 && !cells.contains(line) && cells.contains(model.lineStart(of: line - 1))
    }

    /// The first line of the last row of the table holding the table line `line`.
    private func lastRow(of line: Int, in model: TextModel) -> Int? {
        var at = line
        while true {
            if lastRows.contains(at) { return at }
            let end = model.lineBreak(of: at)
            guard end < model.length, cells.contains(end + 1) else { break }
            at = end + 1
        }
        at = line
        while at > 0, cells.contains(model.lineStart(of: at - 1)) {
            at = model.lineStart(of: at - 1)
            if lastRows.contains(at) { return at }
        }
        return nil
    }

    /// The start of the line after the table holding the table line `line`, if any.
    private func lineAfterTable(from line: Int, in model: TextModel) -> Int? {
        var at = line
        while true {
            let end = model.lineBreak(of: at)
            guard end < model.length else { return nil }
            guard cells.contains(end + 1) else { return end + 1 }
            at = end + 1
        }
    }

    /// The first line of the table right above the line starting at `line`.
    private func firstLine(ofTableAbove line: Int, in model: TextModel) -> Int {
        var at = model.lineStart(of: line - 1)
        while at > 0, cells.contains(model.lineStart(of: at - 1)) { at = model.lineStart(of: at - 1) }
        return at
    }

    /// Letter, digit and underscore runs; real apps also split Chinese by dictionary.
    private func wordEnd(from offset: Int, in model: TextModel) -> Int {
        var at = offset
        while at < model.length, !isWord(at, in: model) { at = model.advance(at, byGraphemes: 1) }
        while at < model.length, isWord(at, in: model) { at = model.advance(at, byGraphemes: 1) }
        return at
    }

    private func wordStart(from offset: Int, in model: TextModel) -> Int {
        var at = offset
        while at > 0, !isWord(model.advance(at, byGraphemes: -1), in: model) { at = model.advance(at, byGraphemes: -1) }
        while at > 0, isWord(model.advance(at, byGraphemes: -1), in: model) { at = model.advance(at, byGraphemes: -1) }
        return at
    }

    private func isWord(_ offset: Int, in model: TextModel) -> Bool {
        guard let character = model.substring(offset..<model.advance(offset, byGraphemes: 1)).first else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    /// The visual row holding `offset`: a line's graphemes cut every `wrap`, the caret on a cut starting the next row.
    private func row(of offset: Int, in model: TextModel) -> (start: Int, end: Int, index: Int, column: Int) {
        let line = model.lineStart(of: offset)
        let end = model.lineBreak(of: offset)
        let width = wrap ?? Int.max
        let count = model.graphemes(in: line..<end)
        let column = model.graphemes(in: line..<offset)
        let index = count == 0 ? 0 : min(column / width, (count - 1) / width)
        let start = model.advance(line, byGraphemes: index * width)
        let last = index == (count == 0 ? 0 : (count - 1) / width)
        return (start, last ? end : model.advance(start, byGraphemes: width), index, column - index * width)
    }

    /// ↓ and ↑: the same visual column one row over; past the first or last row, the text's end.
    private func vertical(from offset: Int, by delta: Int, in model: TextModel) -> Int {
        let here = row(of: offset, in: model)
        let rowEnd = model.lineBreak(of: offset)
        let target: Int
        if delta > 0 {
            if here.end < rowEnd {
                target = here.end
            } else if rowEnd < model.length {
                target = rowEnd + 1
            } else {
                return model.length
            }
        } else {
            let line = model.lineStart(of: offset)
            if here.start > line {
                target = model.advance(here.start, byGraphemes: -1)
            } else if line > 0 {
                target = line - 1
            } else {
                return 0
            }
        }
        let over = row(of: target, in: model)
        return min(model.advance(over.start, byGraphemes: here.column), over.end)
    }
}
