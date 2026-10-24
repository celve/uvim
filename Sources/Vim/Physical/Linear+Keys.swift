/// Linear's entry, continued: what its keys do at its stops, rules and tables, as measured (LIN-1686, LIN-1726, LIN-1780).
extension Linear {
    /// Which plain arrows stop at a stop.
    static func visits(_ stop: Stop, _ way: KeyModel.Way) -> Bool {
        switch stop {
        case .gap, .boxedGap: way != .left
        case .upGap: way == .up
        case .rule, .ruleGap: true
        case .backGap: way == .left || way == .up
        }
    }

    /// A press from a stop, into one or at a table; nil where Cocoa's bindings take it.
    static func press(_ chord: Chord, keys: inout KeyModel, in model: TextModel) -> Bool? {
        if let at = keys.inStop, let left = leave(at, chord, keys: &keys, in: model) { return left }
        let shift = chord.modifiers.contains(.shift)
        let collapsed = keys.anchor == keys.focus
        if !shift, collapsed, let entered = enter(chord, keys: keys, in: model) {
            keys.focus = entered.line - 1
            keys.anchor = keys.focus
            keys.inStop = entered
            return true
        }
        if !shift, collapsed, let crossed = crossTable(chord, keys: keys, in: model) {
            guard let crossed else { return false }
            keys.focus = crossed
            keys.anchor = crossed
            return true
        }
        return nil
    }

    /// The stops before the line starting at `line`, top first.
    private static func stops(before line: Int, keys: KeyModel) -> [Stop] {
        keys.stops[line] ?? (keys.gaps.contains(line) ? [.gap] : [])
    }

    /// The stop the press enters: → from a line's end, ↓ from its last row, ← from the next line's start or ↑ from its first row.
    private static func enter(_ chord: Chord, keys: KeyModel, in model: TextModel) -> KeyModel.Stop? {
        func first(_ line: Int, _ way: KeyModel.Way) -> KeyModel.Stop? {
            stops(before: line, keys: keys).firstIndex { visits($0, way) }.map { KeyModel.Stop(line: line, index: $0) }
        }
        func last(_ line: Int, _ way: KeyModel.Way) -> KeyModel.Stop? {
            stops(before: line, keys: keys).lastIndex { visits($0, way) }.map { KeyModel.Stop(line: line, index: $0) }
        }
        let focus = keys.focus
        switch chord {
        case .right:
            guard focus < model.length, model.graphemes(from: focus, toLineEnd: true, atMost: 0) == 0 else { return nil }
            return first(focus + 1, .right)
        case .down:
            let end = model.lineBreak(of: focus)
            guard end < model.length, keys.row(of: focus, in: model).end == end else { return nil }
            return first(end + 1, .down)
        case .left:
            guard focus > 0, model.lineStart(of: focus) == focus else { return nil }
            return last(focus, .left)
        case .up:
            let start = model.lineStart(of: focus)
            guard start > 0, keys.row(of: focus, in: model).start == start else { return nil }
            return last(start, .up)
        default:
            return nil
        }
    }

    /// The press from a stop; nil for a key that acts from the line above's end.
    private static func leave(_ at: KeyModel.Stop, _ chord: Chord, keys: inout KeyModel, in model: TextModel) -> Bool? {
        let kinds = stops(before: at.line, keys: keys)
        let kind = kinds[at.index]
        func next(_ way: KeyModel.Way) -> Int? { kinds.indices.first { $0 > at.index && visits(kinds[$0], way) } }
        func previous(_ way: KeyModel.Way) -> Int? { kinds.indices.last { $0 < at.index && visits(kinds[$0], way) } }
        var landing: Int
        switch chord {
        case .right, .down:
            if let index = next(chord == .right ? .right : .down) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            landing = at.line
        case .selectRight where kind == .gap || kind == .boxedGap:
            guard next(.right) == nil else { return false }
            landing = at.line
        case .left, .up:
            if let index = previous(chord == .left ? .left : .up) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            if chord == .left || kind == .rule || kind == .backGap {
                // ↑ through a rule, or the stop between one and a table above it, lands at the line above's end, as ← does.
                landing = at.line - 1
            } else if isBelowTable(at.line, keys: keys, in: model) {
                guard let table = lastRow(of: model.lineStart(of: at.line - 1), keys: keys, in: model) else { return false }
                landing = table
            } else {
                landing = keys.row(of: at.line - 1, in: model).start
            }
        case .paragraphStart where kind == .rule:
            // ⌃A on a selected rule goes to the line below it.
            landing = at.line
        case .paragraphStart, .paragraphEnd, Chord.paragraphStart.shifted, Chord.paragraphEnd.shifted:
            return kind == .rule ? false : true
        default:
            guard kind != .rule else { return false }
            keys.inStop = nil
            return nil
        }
        keys.focus = landing
        keys.anchor = landing
        keys.inStop = nil
        return true
    }

    /// Table moves Linear makes its own; nil where the press is not one, `.some(nil)` where the model cannot tell.
    private static func crossTable(_ chord: Chord, keys: KeyModel, in model: TextModel) -> Int?? {
        let cells = keys.cells
        guard !cells.isEmpty else { return nil }
        let focus = keys.focus
        let line = model.lineStart(of: focus)
        switch chord {
        case .wordRight where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            // ⌥→ at a cell's end goes to the next line's start, past any stop after the table.
            return focus + 1
        case .right where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            // Where a closed block follows a table, → from a last-row cell's end leaves the table for the stop between them.
            guard let after = lineAfterTable(from: line, keys: keys, in: model),
                  lastRow(of: line, keys: keys, in: model).map({ $0 <= line }) == true,
                  stops(before: after, keys: keys).contains(where: { visits($0, .right) }) else { return nil }
            return .some(nil)
        case .left where line == focus && isBelowTable(line, keys: keys, in: model):
            // ← from the line right below a table skips the table to the end of the line above it.
            guard !stops(before: line, keys: keys).contains(where: { visits($0, .left) }) else { return nil }
            let first = firstLine(ofTableAbove: line, keys: keys, in: model)
            return first > 0 ? .some(first - 1) : .some(nil)
        case .up where keys.row(of: focus, in: model).start == line && line > 0:
            if isBelowTable(line, keys: keys, in: model) {
                // From column 0 ↑ enters the last row's first cell; elsewhere where the caret's x falls.
                guard !stops(before: line, keys: keys).contains(where: { visits($0, .up) }) else { return nil }
                guard focus == line, let table = lastRow(of: model.lineStart(of: line - 1), keys: keys, in: model) else {
                    return .some(nil)
                }
                return .some(table)
            }
            // ↑ and ↓ go by rows in a table, which the model does not lay out.
            return cells.contains(line) ? .some(nil) : nil
        case .down:
            let end = model.lineBreak(of: focus)
            guard end < model.length, keys.row(of: focus, in: model).end == end else {
                return cells.contains(line) ? .some(nil) : nil
            }
            if cells.contains(line) { return .some(nil) }
            // ↓ into a table lands at the caret's x, which only column 0 tells.
            return cells.contains(end + 1) && !stops(before: end + 1, keys: keys).contains(where: { visits($0, .down) })
                ? (focus == line ? .some(end + 1) : .some(nil)) : nil
        default:
            return nil
        }
    }

    /// The line starting at `line` comes right after a table.
    private static func isBelowTable(_ line: Int, keys: KeyModel, in model: TextModel) -> Bool {
        line > 0 && !keys.cells.contains(line) && keys.cells.contains(model.lineStart(of: line - 1))
    }

    /// The first line of the last row of the table holding the table line `line`.
    private static func lastRow(of line: Int, keys: KeyModel, in model: TextModel) -> Int? {
        var at = line
        while true {
            if keys.lastRows.contains(at) { return at }
            let end = model.lineBreak(of: at)
            guard end < model.length, keys.cells.contains(end + 1) else { break }
            at = end + 1
        }
        at = line
        while at > 0, keys.cells.contains(model.lineStart(of: at - 1)) {
            at = model.lineStart(of: at - 1)
            if keys.lastRows.contains(at) { return at }
        }
        return nil
    }

    /// The start of the line after the table holding the table line `line`, if any.
    private static func lineAfterTable(from line: Int, keys: KeyModel, in model: TextModel) -> Int? {
        var at = line
        while true {
            let end = model.lineBreak(of: at)
            guard end < model.length else { return nil }
            guard keys.cells.contains(end + 1) else { return end + 1 }
            at = end + 1
        }
    }

    /// The first line of the table right above the line starting at `line`.
    private static func firstLine(ofTableAbove line: Int, keys: KeyModel, in model: TextModel) -> Int {
        var at = model.lineStart(of: line - 1)
        while at > 0, keys.cells.contains(model.lineStart(of: at - 1)) { at = model.lineStart(of: at - 1) }
        return at
    }

    /// `j`'s keys line by line: ⇧→ → over a lone stop, read right ~150 ms before → → (LIN-1686), else → per stop, ⌥→ off a cell.
    static func hops(
        from line: Int, count: Int, model: TextModel, stops: [Int: [Stop]], cells: Set<Int>, profile: CapabilityProfile
    ) -> [[Chord]] {
        let starts = lineStarts(after: line, count: count, in: model)
        return zip([line] + starts, starts).map { from, start -> [Chord] in
            let crossed = (stops[start] ?? []).filter { visits($0, .right) }
            // Into a rule a table's last cell leaves by →, after which ⇧→ counts a column right where ⌥→'s does not.
            if cells.contains(from), !crossed.contains(.rule), profile.has(.wordKeys) { return [.wordRight] }
            return crossed == [.gap] ? [.selectRight, .right] : Array(repeating: .right, count: crossed.count + 1)
        } + Array(repeating: [.right], count: count - starts.count)
    }

    /// `k`'s keys: ← per stop ← meets and ⌃A per line; into a table from the line below it, ↑ to its last row, then ⌃E ⌥→ per cell.
    static func upward(
        from line: Int, count: Int, model: TextModel, stops: [Int: [Stop]], cells: Set<Int>, lastRows: Set<Int>,
        profile: CapabilityProfile
    ) -> (chords: [Chord], endsLeft: Bool) {
        // The first line of the last row of the table holding the table line `line`.
        func lastRow(_ line: Int) -> Int? {
            var at = line
            while !lastRows.contains(at) {
                guard at > 0, cells.contains(model.lineStart(of: at - 1)) else { return nil }
                at = model.lineStart(of: at - 1)
            }
            return at
        }
        var chords: [Chord] = []
        var at = line
        var left = count
        var endsLeft = false
        while left > 0, at > 0 {
            let above = model.lineStart(of: at - 1)
            // ← skips a table right above unless a rule between gives it somewhere to stop.
            let backs = (stops[at] ?? []).filter { visits($0, .left) }.count
            if cells.contains(above), !cells.contains(at), backs == 0, let row = lastRow(above) {
                let rows = model.newlineCount(in: row..<above) + 1
                let crossed = (stops[at] ?? []).filter { visits($0, .up) }.count
                chords += Array(repeating: .up, count: crossed + 1) + [.paragraphStart]
                endsLeft = false
                guard left >= rows else {
                    let cell: [Chord] = [.paragraphEnd, profile.has(.wordKeys) ? .wordRight : .right]
                    chords += Array(repeatElement(cell, count: max(0, rows - left)).joined())
                    break
                }
                (at, left) = (row, left - rows)
                continue
            }
            chords += Array(repeating: .left, count: backs + 1) + [.paragraphStart]
            (at, left, endsLeft) = (above, left - 1, true)
        }
        return (chords, endsLeft)
    }

    /// The starts of the `count` lines after `line`'s, as far as the text goes.
    private static func lineStarts(after line: Int, count: Int, in model: TextModel) -> [Int] {
        var starts: [Int] = []
        guard count > 0 else { return starts }
        var end = model.lineBreak(of: line)
        while starts.count < count, end < model.length {
            starts.append(end + 1)
            if starts.count < count { end = model.lineBreak(of: end + 1) }
        }
        return starts
    }
}
