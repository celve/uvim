/// Layer 4 of the field model (softlash/LIN-2329 field-model.md §5 L4): what a press does at a stop or a table, as rows keyed by
/// stop kind and chord. The structure's rows are as each stop was measured where it is made, and the editor facts in scope
/// override single rows: ProseMirror's are shared by Linear and Tiptap (softlash/LIN-2048), Linear's are its own (LIN-1686,
/// LIN-1726, LIN-1780).
struct Navigation: Equatable, Sendable {
    /// What a press from a stop does.
    enum Leave: Equatable, Sendable {
        /// The next stop the way visits, else the line's start.
        case onward(KeyModel.Way)
        /// The line's start where no stop → visits follows; past one the model cannot tell.
        case onwardLast
        /// The previous stop the way visits, else the line above's end.
        case back(KeyModel.Way)
        /// The previous stop ↑ visits, else under a table its way in, else the start of the line above's last row.
        case backUp
        /// The next rule, or the previous, past any gap cursor between; else the line's start, or the line above's end.
        case rule(forward: Bool)
        case lineStart
        case stay
        case unknown
        /// The press acts from the line above's end, out of the stop.
        case fromLineAbove
    }

    /// Where ↑ from column 0 of the line right below a table lands.
    enum TableEntry: Equatable, Sendable {
        /// The first line of the table's last row.
        case lastRow
        /// The line above, its last row's last cell.
        case lastLine
    }

    /// Which plain arrows stop at each stop kind.
    var visiting: [Linear.Stop: Set<KeyModel.Way>]
    /// Each stop kind's rows by chord, and the row for a chord it has none for.
    var leaves: [Linear.Stop: [Chord: Leave]]
    var otherwise: [Linear.Stop: Leave]
    /// ⌥→ at a cell's end lands on the next line's start, past any stop after the table; elsewhere the model cannot tell.
    var cellWordRight: Bool
    var upIntoTable: TableEntry

    /// The structure's rows, and the facts' over them.
    init(_ facts: EditorFacts) {
        let all: Set<KeyModel.Way> = [.right, .left, .up, .down]
        visiting = [.gap: [.right, .up, .down], .boxedGap: [.right, .up, .down], .upGap: [.up], .rule: all, .ruleGap: all,
                    .backGap: [.left, .up]]
        let lineKeys = [Chord.paragraphStart, .paragraphEnd, Chord.paragraphStart.shifted, Chord.paragraphEnd.shifted]
        leaves = [:]
        otherwise = [:]
        for kind in visiting.keys {
            // ↑ through a rule, or the stop between one and a table above it, lands at the line above's end, as ← does.
            var rows: [Chord: Leave] = [.right: .onward(.right), .down: .onward(.down), .left: .back(.left),
                                        .up: kind == .rule || kind == .backGap ? .back(.up) : .backUp]
            // Only Linear makes these kinds, and nothing measured a line key at ProseMirror's own.
            let ownKeys = kind != .rule && kind != .ruleGap
            for chord in lineKeys { rows[chord] = ownKeys ? .stay : .unknown }
            if kind.isGap { rows[.selectRight] = .onwardLast }
            // ProseMirror takes ⌘ and ⌥ arrows from a rule or gap cursor to the next selectable node, the next rule.
            if !ownKeys {
                for chord in Self.edgeKeys { rows[chord] = .rule(forward: chord == .lineEnd || chord == .wordRight) }
            }
            leaves[kind] = rows
            otherwise[kind] = ownKeys ? .fromLineAbove : .unknown
        }
        cellWordRight = false
        upIntoTable = .lastLine
        guard facts.contains(.linear) else { return }
        // ⌃A on a selected rule goes to the line below it.
        leaves[.rule]?[.paragraphStart] = .lineStart
        for chord in lineKeys { leaves[.ruleGap]?[chord] = .stay }
        otherwise[.ruleGap] = .fromLineAbove
        cellWordRight = true
        upIntoTable = .lastRow
    }

    /// The modified arrows ProseMirror handles as plain ones at a textblock's edge, selecting a rule beside it.
    static let edgeKeys: [Chord] = [.lineStart, .lineEnd, .wordLeft, .wordRight]

    /// The structure's alone, and Linear's, the facts every stop kind was measured under.
    static let structure = Navigation([])
    static let linear = Navigation([.proseMirror, .linear])

    /// One of those two, which are all the facts select today.
    static func of(_ facts: EditorFacts) -> Navigation {
        facts.contains(.linear) ? linear : structure
    }

    /// Which plain arrows stop at a stop.
    func visits(_ stop: Linear.Stop, _ way: KeyModel.Way) -> Bool {
        visiting[stop]?.contains(way) ?? false
    }

    /// A press from a stop, into one or at a table; nil where Cocoa's bindings take it.
    func press(_ chord: Chord, keys: inout KeyModel, in model: TextModel) -> Bool? {
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
    private static func stops(before line: Int, keys: KeyModel) -> [Linear.Stop] {
        keys.stops[line] ?? (keys.gaps.contains(line) ? [.gap] : [])
    }

    /// The stop the press enters: → from a line's end, ↓ from its last row, ← from the next line's start or ↑ from its first row.
    private func enter(_ chord: Chord, keys: KeyModel, in model: TextModel) -> KeyModel.Stop? {
        func first(_ line: Int, _ way: KeyModel.Way) -> KeyModel.Stop? {
            Self.stops(before: line, keys: keys).firstIndex { visits($0, way) }.map { KeyModel.Stop(line: line, index: $0) }
        }
        func last(_ line: Int, _ way: KeyModel.Way) -> KeyModel.Stop? {
            Self.stops(before: line, keys: keys).lastIndex { visits($0, way) }.map { KeyModel.Stop(line: line, index: $0) }
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
        case .lineStart, .wordLeft:
            // At a textblock's edge ProseMirror selects a rule beside it, where Cocoa's bindings would stay or cross a word.
            let kinds = Self.stops(before: focus, keys: keys)
            guard focus > 0, model.lineStart(of: focus) == focus, kinds.last == .rule else { return nil }
            return KeyModel.Stop(line: focus, index: kinds.count - 1)
        case .lineEnd, .wordRight:
            guard focus < model.length, model.lineBreak(of: focus) == focus,
                  Self.stops(before: focus + 1, keys: keys).first == .rule else { return nil }
            return KeyModel.Stop(line: focus + 1, index: 0)
        default:
            return nil
        }
    }

    /// The press from a stop; nil for a key that acts from the line above's end.
    private func leave(_ at: KeyModel.Stop, _ chord: Chord, keys: inout KeyModel, in model: TextModel) -> Bool? {
        let kinds = Self.stops(before: at.line, keys: keys)
        let kind = kinds[at.index]
        func next(_ way: KeyModel.Way) -> Int? { kinds.indices.first { $0 > at.index && visits(kinds[$0], way) } }
        func previous(_ way: KeyModel.Way) -> Int? { kinds.indices.last { $0 < at.index && visits(kinds[$0], way) } }
        var landing: Int
        switch leaves[kind]?[chord] ?? otherwise[kind] ?? .unknown {
        case .onward(let way):
            if let index = next(way) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            landing = at.line
        case .onwardLast:
            guard next(.right) == nil else { return false }
            landing = at.line
        case .back(let way):
            if let index = previous(way) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            landing = at.line - 1
        case .backUp:
            if let index = previous(.up) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            if Self.isBelowTable(at.line, keys: keys, in: model) {
                guard let table = entry(below: at.line, keys: keys, in: model) else { return false }
                landing = table
            } else {
                landing = keys.row(of: at.line - 1, in: model).start
            }
        case .rule(let forward):
            if let index = forward ? kinds.indices.first(where: { $0 > at.index && kinds[$0] == .rule })
                : kinds.indices.last(where: { $0 < at.index && kinds[$0] == .rule }) {
                keys.inStop = KeyModel.Stop(line: at.line, index: index)
                return true
            }
            landing = forward ? at.line : at.line - 1
        case .lineStart:
            landing = at.line
        case .stay:
            return true
        case .unknown:
            return false
        case .fromLineAbove:
            keys.inStop = nil
            return nil
        }
        keys.focus = landing
        keys.anchor = landing
        keys.inStop = nil
        return true
    }

    /// Where ↑ from column 0 of the line starting at `line`, right below a table, lands; nil where the model cannot tell.
    private func entry(below line: Int, keys: KeyModel, in model: TextModel) -> Int? {
        let last = model.lineStart(of: line - 1)
        return upIntoTable == .lastRow ? Self.lastRow(of: last, keys: keys, in: model) : last
    }

    /// Table moves Cocoa's bindings do not predict; nil where the press is not one, `.some(nil)` where the model cannot tell.
    private func crossTable(_ chord: Chord, keys: KeyModel, in model: TextModel) -> Int?? {
        let cells = keys.cells
        guard !cells.isEmpty else { return nil }
        let focus = keys.focus
        let line = model.lineStart(of: focus)
        switch chord {
        case .wordRight where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            return cellWordRight ? focus + 1 : .some(nil)
        case .right where cells.contains(line) && focus == model.lineBreak(of: focus) && focus < model.length:
            // Where a closed block follows a table, → from a last-row cell's end leaves the table for the stop between them.
            guard let after = Self.lineAfterTable(from: line, keys: keys, in: model),
                  Self.lastRow(of: line, keys: keys, in: model).map({ $0 <= line }) == true,
                  Self.stops(before: after, keys: keys).contains(where: { visits($0, .right) }) else { return nil }
            return .some(nil)
        case .left where line == focus && Self.isBelowTable(line, keys: keys, in: model):
            // ← from the line right below a table skips the table to the end of the line above it.
            guard !Self.stops(before: line, keys: keys).contains(where: { visits($0, .left) }) else { return nil }
            let first = Self.firstLine(ofTableAbove: line, keys: keys, in: model)
            return first > 0 ? .some(first - 1) : .some(nil)
        case .up where keys.row(of: focus, in: model).start == line && line > 0:
            if Self.isBelowTable(line, keys: keys, in: model) {
                // From column 0 ↑ enters the table where its entry says; elsewhere where the caret's x falls.
                guard !Self.stops(before: line, keys: keys).contains(where: { visits($0, .up) }) else { return nil }
                guard focus == line, let table = entry(below: line, keys: keys, in: model) else { return .some(nil) }
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
            return cells.contains(end + 1) && !Self.stops(before: end + 1, keys: keys).contains(where: { visits($0, .down) })
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

    /// `j`'s keys line by line: ⇧→ → over a lone stop, read right ~150 ms before → → (LIN-1686), else → per stop, ⌥→ off a
    /// cell where it lands on the next line.
    func hops(
        from line: Int, count: Int, model: TextModel, stops: [Int: [Linear.Stop]], cells: Set<Int>, profile: CapabilityProfile
    ) -> [[Chord]] {
        let starts = Self.lineStarts(after: line, count: count, in: model)
        return zip([line] + starts, starts).map { from, start -> [Chord] in
            let crossed = (stops[start] ?? []).filter { visits($0, .right) }
            // Into a rule a table's last cell leaves by →, after which ⇧→ counts a column right where ⌥→'s does not.
            if cellWordRight, cells.contains(from), !crossed.contains(.rule), profile.has(.wordKeys) { return [.wordRight] }
            return crossed == [.gap] ? [.selectRight, .right] : Array(repeating: .right, count: crossed.count + 1)
        } + Array(repeating: [.right], count: count - starts.count)
    }

    /// `k`'s keys: ← per stop ← meets and ⌃A per line; into a table from the line below it, ↑ to its way in, and from its
    /// last row's first line ⌃E ⌥→ per cell.
    func upward(
        from line: Int, count: Int, model: TextModel, stops: [Int: [Linear.Stop]], cells: Set<Int>, lastRows: Set<Int>,
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
            let crossed = (stops[at] ?? []).filter { visits($0, .up) }.count
            if cells.contains(above), !cells.contains(at), backs == 0, upIntoTable == .lastLine {
                chords += Array(repeating: .up, count: crossed + 1) + [.paragraphStart]
                (at, left, endsLeft) = (above, left - 1, false)
                continue
            }
            if cells.contains(above), !cells.contains(at), backs == 0, let row = lastRow(above) {
                let rows = model.newlineCount(in: row..<above) + 1
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
