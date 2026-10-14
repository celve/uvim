/// Pure vim text math over one snapshot of field text.
///
/// Every offset entering or leaving this type is a **UTF-16 code unit**
/// offset — AX's currency. Grapheme handling (what an arrow key moves over,
/// what a `Character` is) happens internally, so the offset↔grapheme hazard
/// lives and dies in this file. Zero dependencies; the physical planner's
/// lanes A and B are its only callers.
public struct TextModel: Equatable, Sendable {
    public let text: String

    /// Offsets of characters that stand for something drawn, such as a chip, however invisible they read.
    public let atoms: Set<Int>

    /// In rich text, the `\n`s Chromium generates between paragraphs; any other `\n` there is a hard break (`<br>`).
    public let paragraphBreaks: Set<Int>?

    public init(_ text: String, atoms: Set<Int> = [], paragraphBreaks: Set<Int>? = nil) {
        self.text = text
        self.atoms = atoms
        self.paragraphBreaks = paragraphBreaks
    }

    public var length: Int { text.utf16.count }

    // MARK: - Offsets

    public func clamp(_ offset: Int) -> Int {
        min(max(offset, 0), length)
    }

    private func index(_ offset: Int) -> String.Index {
        String.Index(utf16Offset: clamp(offset), in: text)
    }

    private func offset(_ index: String.Index) -> Int {
        index.utf16Offset(in: text)
    }

    /// Grapheme-wise advance, clamped to the text. Negative moves left.
    public func advance(_ offset: Int, byGraphemes n: Int) -> Int {
        let i = index(offset)
        let limit = n >= 0 ? text.endIndex : text.startIndex
        let j = text.index(i, offsetBy: n, limitedBy: limit) ?? limit
        return self.offset(j)
    }

    /// The number of arrow-key presses spanning a range.
    public func graphemes(in range: Range<Int>) -> Int {
        text.distance(from: index(range.lowerBound), to: index(range.upperBound))
    }

    /// `graphemes(in:)` from `offset` to its line's break, where ⌃E lands, or its start, where at most `limit`; walks no further.
    public func graphemes(from offset: Int, toLineEnd: Bool, atMost limit: Int) -> Int? {
        guard limit >= 0 else { return nil }
        var i = index(offset)
        for count in 0...limit {
            if toLineEnd ? i == text.endIndex || text[i] == "\n" : i == text.startIndex || text[text.index(before: i)] == "\n" {
                return count
            }
            i = toLineEnd ? text.index(after: i) : text.index(before: i)
        }
        return nil
    }

    public func substring(_ range: Range<Int>) -> String {
        String(text[index(range.lowerBound)..<index(range.upperBound)])
    }

    public func replacing(_ range: Range<Int>, with replacement: String) -> String {
        var copy = text
        copy.replaceSubrange(index(range.lowerBound)..<index(range.upperBound), with: replacement)
        return copy
    }

    public func newlineCount(in range: Range<Int>) -> Int {
        text[index(range.lowerBound)..<index(range.upperBound)].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    // MARK: - Lines

    /// Offset just after the previous newline (or 0). A caret sitting on a
    /// newline belongs to the line that newline terminates.
    public func lineStart(of o: Int) -> Int {
        let i = index(o)
        guard let newline = text[..<i].lastIndex(of: "\n") else { return 0 }
        return offset(text.index(after: newline))
    }

    /// Offset of the line's newline (or the text end), where a host's ⌃E lands.
    public func lineBreak(of o: Int) -> Int {
        let i = index(o)
        guard let newline = text[i...].firstIndex(of: "\n") else { return length }
        return offset(newline)
    }

    /// The end-of-line gap, before invisible characters ending the line (LIN-1978); never before `o`, where a host left a caret.
    public func lineEnd(of o: Int) -> Int {
        max(clamp(o), visibleEnd(from: lineStart(of: o), to: lineBreak(of: o)))
    }

    /// `o`, or its line's end where `o` is among or after the invisible characters ending the line.
    public func visibleOffset(_ o: Int) -> Int {
        guard (0...length).contains(o) else { return o }
        return min(o, lineEnd(of: lineStart(of: o)))
    }

    /// `end` less the invisible characters right before it, back to `start`, but for a line a hard break draws with them alone.
    private func visibleEnd(from start: Int, to end: Int) -> Int {
        let first = index(start)
        var i = index(end)
        while i > first, isInvisible(text.index(before: i)) {
            i = text.index(before: i)
        }
        // Linear draws the line after a `<br>` with a U+200B, and keeps a caret on it after that.
        if i == first, start > 0, let paragraphBreaks, !paragraphBreaks.contains(start - 1) { return end }
        return offset(i)
    }

    private func isInvisible(_ i: String.Index) -> Bool {
        Self.isInvisible(text[i]) && !atoms.contains(offset(i))
    }

    /// A character Unicode draws as nothing, as U+200B, U+2060 or U+FEFF; one joined to the character before is part of that one.
    static func isInvisible(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint)
    }

    /// `i` is among the invisible characters that end its line.
    private func inBreak(_ i: String.Index) -> Bool {
        isInvisible(i) && offset(i) >= lineEnd(of: lineStart(of: offset(i)))
    }

    /// `range` less the invisible characters ending its lines, as a register keeps it.
    public func visibleParts(of range: Range<Int>) -> [Range<Int>] {
        var parts: [Range<Int>] = []
        var start = range.lowerBound
        var i = index(range.lowerBound)
        while i < index(range.upperBound) {
            let next = text.index(after: i)
            if inBreak(i) {
                if offset(i) > start { parts.append(start..<offset(i)) }
                start = offset(next)
            }
            i = next
        }
        if range.upperBound > start { parts.append(start..<range.upperBound) }
        return parts
    }

    public func visibleText(in range: Range<Int>) -> String {
        visibleParts(of: range).map(substring).joined()
    }

    /// Some line ends in invisible characters, past which an app's own keys land.
    public var endsLinesInvisibly: Bool {
        var start = 0
        while true {
            let end = lineBreak(of: start)
            if lineEnd(of: start) < end { return true }
            guard end < length else { return false }
            start = end + 1
        }
    }

    /// Whether a line holding any of `range`, ends included, is empty, as `AXValue` shows lines.
    public func touchesEmptyLine(_ range: Range<Int>) -> Bool {
        var start = lineStart(of: range.lowerBound)
        while start <= range.upperBound {
            let end = lineBreak(of: start)
            if end == start { return true }
            guard end < length else { return false }
            start = end + 1
        }
        return false
    }

    public func firstNonBlank(inLineOf o: Int) -> Int {
        let start = lineStart(of: o)
        var i = index(start)
        let end = index(lineEnd(of: start))
        while i < end, text[i] == " " || text[i] == "\t" {
            i = text.index(after: i)
        }
        return offset(i)
    }

    /// Whole lines from the line containing `a` through the line containing `b`, in either order.
    public func lineSpan(from a: Int, to b: Int, extent: LineExtent) -> Range<Int> {
        lines(from: min(a, b), through: lineBreak(of: max(a, b)), extent)
    }

    /// N whole lines starting at the line containing `o`.
    public func lines(from o: Int, count: Int, extent: LineExtent) -> Range<Int> {
        var end = lineBreak(of: o)
        var remaining = count - 1
        while remaining > 0, end < length {
            end = lineBreak(of: end + 1)
            remaining -= 1
        }
        return lines(from: o, through: end, extent)
    }

    /// From `o`'s line start to the break at `end`, the break taken whole or left with its invisible characters; lines that end
    /// the text, removed, take the newline above them instead, in paragraphs with the line above's invisible characters, which
    /// an editor that closes its lines with one (Lark's) deletes with the newline.
    private func lines(from o: Int, through end: Int, _ extent: LineExtent) -> Range<Int> {
        let start = lineStart(of: o)
        guard extent != .interior, end < length else {
            let last = lineEnd(of: lineStart(of: end))
            guard extent == .removed, start > 0 else { return start..<last }
            return (paragraphBreaks == nil ? start - 1 : lineEnd(of: lineStart(of: start - 1)))..<last
        }
        return start..<(end + 1)
    }

    /// `j`/`k`: move whole lines, preserving the grapheme column, clamped to
    /// the target line's end.
    public func verticalMove(from o: Int, by delta: Int, firstNonBlank fnb: Bool) -> Int {
        var start = lineStart(of: o)
        let column = graphemes(in: start..<o)
        var remaining = delta
        while remaining > 0 {
            let end = lineBreak(of: start)
            guard end < length else { break }
            start = end + 1
            remaining -= 1
        }
        while remaining < 0, start > 0 {
            start = lineStart(of: start - 1)
            remaining += 1
        }
        if fnb { return firstNonBlank(inLineOf: start) }
        return min(advance(start, byGraphemes: column), lineEnd(of: start))
    }

    // MARK: - Words

    private enum CharClass {
        case whitespace
        case keyword
        case punctuation
    }

    private func charClass(_ c: Character, big: Bool) -> CharClass {
        if c == " " || c == "\t" || c == "\n" || c == "\r" { return .whitespace }
        if big { return .keyword }
        if c.isLetter || c.isNumber || c == "_" { return .keyword }
        return .punctuation
    }

    /// The character at `i`'s class, where the invisible characters ending a line are its break's whitespace.
    private func charClass(at i: String.Index, big: Bool) -> CharClass {
        inBreak(i) ? .whitespace : charClass(text[i], big: big)
    }

    /// `w`/`W`: start of the next word.
    public func wordForward(from o: Int, big: Bool) -> Int {
        var i = index(o)
        guard i < text.endIndex else { return length }
        let cls = charClass(at: i, big: big)
        if cls != .whitespace {
            while i < text.endIndex, charClass(at: i, big: big) == cls {
                i = text.index(after: i)
            }
        }
        while i < text.endIndex, charClass(at: i, big: big) == .whitespace {
            i = text.index(after: i)
        }
        return offset(i)
    }

    /// `b`/`B`: start of the previous word.
    public func wordBackward(from o: Int, big: Bool) -> Int {
        var i = index(o)
        guard i > text.startIndex else { return 0 }
        i = text.index(before: i)
        while i > text.startIndex, charClass(at: i, big: big) == .whitespace {
            i = text.index(before: i)
        }
        guard charClass(at: i, big: big) != .whitespace else { return offset(i) }
        let cls = charClass(at: i, big: big)
        while i > text.startIndex {
            let previous = text.index(before: i)
            guard charClass(at: previous, big: big) == cls else { break }
            i = previous
        }
        return offset(i)
    }

    /// `e`/`E`: the offset **of** the last character of the word — the gap
    /// before it. An inclusive span adds one grapheme to cover it.
    public func wordEnd(from o: Int, big: Bool) -> Int {
        var i = index(o)
        guard i < text.endIndex else { return o }
        i = text.index(after: i)
        while i < text.endIndex, charClass(at: i, big: big) == .whitespace {
            i = text.index(after: i)
        }
        guard i < text.endIndex else { return advance(lineEnd(of: lineStart(of: length)), byGraphemes: -1) }
        let cls = charClass(at: i, big: big)
        while true {
            let next = text.index(after: i)
            guard next < text.endIndex, charClass(at: next, big: big) == cls else { break }
            i = next
        }
        return offset(i)
    }

    /// `iw`/`aw`: the run containing the caret (whitespace counts as a run,
    /// as in vim); `around` extends over trailing blanks, or leading ones
    /// when there are none trailing. Newlines never join an `aw`.
    public func wordObject(at o: Int, around: Bool, big: Bool) -> Range<Int> {
        guard length > 0 else { return 0..<0 }
        var i = index(o)
        if i == text.endIndex { i = text.index(before: i) }
        let cls = charClass(at: i, big: big)
        var start = i
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard charClass(at: previous, big: big) == cls, text[previous] != "\n" else { break }
            start = previous
        }
        var end = text.index(after: i)
        while end < text.endIndex, charClass(at: end, big: big) == cls, text[end] != "\n" {
            end = text.index(after: end)
        }
        var lo = offset(start)
        var hi = offset(end)
        if around, cls != .whitespace {
            let trailingStart = hi
            var j = index(hi)
            while j < text.endIndex, text[j] == " " || text[j] == "\t" {
                j = text.index(after: j)
            }
            hi = offset(j)
            if hi == trailingStart {
                var k = index(lo)
                while k > text.startIndex {
                    let previous = text.index(before: k)
                    guard text[previous] == " " || text[previous] == "\t" else { break }
                    k = previous
                }
                lo = offset(k)
            }
        }
        return lo..<hi
    }

    // MARK: - Find and search

    /// `f`/`F`/`t`/`T`, within the caret's line. Returns the destination gap
    /// or nil when the character is not found (vim bells).
    public func findCharacter(_ target: Character, from o: Int, forward: Bool, before till: Bool, count: Int) -> Int? {
        var remaining = count
        if forward {
            var i = index(o)
            let end = index(lineEnd(of: o))
            guard i < end else { return nil }
            i = text.index(after: i)
            while i < end {
                if text[i] == target {
                    remaining -= 1
                    if remaining == 0 {
                        let found = offset(i)
                        return till ? advance(found, byGraphemes: -1) : found
                    }
                }
                i = text.index(after: i)
            }
            return nil
        }
        var i = index(o)
        let start = index(lineStart(of: o))
        while i > start {
            i = text.index(before: i)
            if text[i] == target {
                remaining -= 1
                if remaining == 0 {
                    let found = offset(i)
                    return till ? advance(found, byGraphemes: 1) : found
                }
            }
        }
        return nil
    }

    /// Literal, wrapping search. Returns the match start.
    public func search(_ pattern: String, from o: Int, forward: Bool, count: Int) -> Int? {
        guard !pattern.isEmpty else { return nil }
        let starts = matchStarts(of: pattern)
        guard !starts.isEmpty else { return nil }
        guard count > 0 else { return o }
        // The first step lands on a match and each later one on its neighbour, around the ring.
        let further = (count - 1) % starts.count
        if forward {
            let first = starts.firstIndex(where: { $0 > o }) ?? 0
            return starts[(first + further) % starts.count]
        }
        let first = starts.lastIndex(where: { $0 < o }) ?? starts.count - 1
        return starts[(first - further + starts.count) % starts.count]
    }

    private func matchStarts(of pattern: String) -> [Int] {
        var result: [Int] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i...].hasPrefix(pattern) {
                result.append(offset(i))
            }
            i = text.index(after: i)
        }
        return result
    }

    // MARK: - Marks

    /// How many graphemes of context a mark witness captures on each side.
    private static let witnessRadius = 4

    public func witness(at o: Int) -> String {
        let lo = advance(o, byGraphemes: -Self.witnessRadius)
        let hi = advance(o, byGraphemes: Self.witnessRadius)
        return substring(lo..<hi)
    }

    public func markPoint(at o: Int) -> MarkPoint {
        MarkPoint(offset: clamp(o), textLength: length, context: witness(at: o))
    }

    public func isValid(_ mark: MarkPoint) -> Bool {
        mark.textLength == length && witness(at: mark.offset) == mark.context
    }

    // MARK: - Motion destinations

    /// The gap a motion lands on, or nil when the motion is unsupported here
    /// or finds nothing (both bell). Counts that name lines (`3G`) are not
    /// distinguishable from defaults at this level and are ignored for
    /// `fileStart`/`fileEnd`.
    public func destination(of motion: Motion, from o: Int, count: Int) -> Int? {
        switch motion {
        case .character(.left):
            return max(lineStart(of: o), advance(o, byGraphemes: -count))
        case .character(.right):
            return min(lineEnd(of: o), advance(o, byGraphemes: count))
        case .character:
            return nil
        case .line(let direction, let fnb) where direction == .up || direction == .down:
            return verticalMove(from: o, by: direction == .down ? count : -count, firstNonBlank: fnb)
        case .line:
            return nil
        case .word(let direction, let end, let big):
            var position = o
            for _ in 0..<count {
                let next: Int
                switch (direction, end) {
                case (.forward, false): next = wordForward(from: position, big: big)
                case (.forward, true): next = wordEnd(from: position, big: big)
                case (.backward, false): next = wordBackward(from: position, big: big)
                default: return nil
                }
                // A step that stays put is at the text's edge, where every later one stays too.
                guard next != position else { break }
                position = next
            }
            return position
        case .lineStart(let fnb):
            return fnb ? firstNonBlank(inLineOf: o) : lineStart(of: o)
        case .lineEnd:
            let base = count > 1 ? verticalMove(from: o, by: count - 1, firstNonBlank: false) : o
            return lineEnd(of: base)
        case .lastNonBlank:
            let start = lineStart(of: o)
            var i = index(lineEnd(of: start))
            while i > index(start) {
                i = text.index(before: i)
                if text[i] != " ", text[i] != "\t" { return offset(i) }
            }
            return start
        case .fileStart:
            return firstNonBlank(inLineOf: 0)
        case .fileEnd:
            return firstNonBlank(inLineOf: lineStart(of: length))
        case .find(let character, let direction, let before) where direction == .forward || direction == .backward:
            return findCharacter(character, from: o, forward: direction == .forward, before: before, count: count)
        case .find:
            return nil
        case .search(let search):
            guard let pattern = search.pattern, !pattern.isEmpty else { return nil }
            return self.search(pattern, from: o, forward: search.direction == .forward, count: count)
        default:
            return nil
        }
    }
}
