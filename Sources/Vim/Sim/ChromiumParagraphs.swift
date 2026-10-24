public extension Sim {
    /// What Linear draws before a line's text, each a block of its own in `AXValue`: a list marker, then text-less leaves.
    struct ListLine: Hashable, Sendable {
        public var marker: String?
        public var leaves: Int
        /// The leaves are a to-do's checkbox, which a write at its line's start lands beside by where the caret was.
        public var checkbox: Bool
        /// The marker starts its item's line, as Chromium draws its own lists' markers.
        public var inline: Bool
        /// The line starts a list, code block or quote right after another, so → ↓ from the line above or ↑ from it stops first.
        public var stop: Bool
        /// The marker is a code block's language label, which its block tells from text, not its shape.
        public var controls: Bool
        /// Rules right before the line, each a text-less block of its own (LIN-1780).
        public var ruled: Int
        /// The stops before the line other than `stop`'s, top first, as discovery reads them beside rules, tables and sections.
        public var before: [ParagraphBreaks.Hidden.Kind]
        /// The line is a table cell's, and starts the table's last row.
        public var cell: Bool
        public var lastRow: Bool

        public init(
            marker: String? = nil, leaves: Int = 0, checkbox: Bool = false, inline: Bool = false, stop: Bool = false,
            controls: Bool = false, ruled: Int = 0, before: [ParagraphBreaks.Hidden.Kind] = [], cell: Bool = false,
            lastRow: Bool = false
        ) {
            self.marker = marker
            self.leaves = leaves
            self.checkbox = checkbox
            self.inline = inline
            self.stop = stop
            self.controls = controls
            self.ruled = ruled
            self.before = before
            self.cell = cell || lastRow
            self.lastRow = lastRow
        }

        /// `lines` once `range` of `text` is `replacement`: the first keeps its own, but a deleted plain line the next's.
        static func carried(
            _ lines: [ListLine], in text: String, replacing range: Range<Int>, with replacement: String
        ) -> [ListLine] {
            let units = Array(text.utf16)
            guard lines.count == units.filter({ $0 == 10 }).count + 1 else { return lines }
            let first = units[..<range.lowerBound].filter { $0 == 10 }.count
            let last = units[..<range.upperBound].filter { $0 == 10 }.count
            var head = lines[first]
            let wholeLines = replacement.isEmpty && !range.isEmpty && units[range.upperBound - 1] == 10
                && (range.lowerBound == 0 || units[range.lowerBound - 1] == 10)
            if wholeLines, head == ListLine() { head = lines[last] }
            let made = replacement.utf16.filter { $0 == 10 }.count
            return Array(lines[..<first]) + [head] + Array(repeating: ListLine(), count: made) + Array(lines[(last + 1)...])
        }
    }
}

public extension EmptyParagraphs {
    /// `AXValue`, the plain marker text and each empty paragraph's `<br>` offset, as Chrome 153 shows `paragraphs`.
    static func chromium(_ paragraphs: [String]) -> (value: String, markers: String, found: [Int]) {
        var value = ""
        var markers = ""
        var found: [Int] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.isEmpty {
                found.append(markers.utf16.count)
                markers += "\n"
                value += "\n"
            } else {
                if index > 0, !paragraphs[index - 1].isEmpty { value += "\n" }
                markers += paragraph
                value += paragraph
            }
        }
        return (value, markers, found)
    }
}

/// The Sim's text as Chrome 153 shows it when every `\n` ends a paragraph (LIN-1612); with `lines`, as Linear does.
struct ChromiumParagraphs {
    static let chip: UInt16 = 0x2060
    static let label = Array("\u{2060}\u{00A0}LIN-1 chip".utf16)

    let text: String
    let paragraphs: [String]
    let lines: [Sim.ListLine]?
    /// `AXValue`, the raw marker text and each empty paragraph's `<br>` offset.
    let shown: (value: String, markers: String, found: [Int])
    let plainMarkers: String
    /// Plain starts of the list markers, and the chips.
    let listMarkers: [Int]
    let chips: [UnreachableLines.Chip]
    /// Plain starts of blocks a stop comes before, the Sim offsets of their first lines, and code blocks' labels.
    let joins: [Int]
    let gaps: Set<Int>
    let controls: [Range<Int>]
    /// The other stops and the tables as discovery reads them, and each line's stops, table lines and last rows in Sim offsets.
    let stops: [UnreachableLines.Stop]
    let tables: [UnreachableLines.Table]
    let keyStops: [Int: [ParagraphBreaks.Hidden.Kind]]
    let cells: Set<Int>
    let lastRows: Set<Int>
    /// The caret Linear draws at a code span's edge, and the paragraph whose end it ends with a `<br>`.
    let drawnCaret: UnreachableLines.Caret?
    let drawnAtEnd: Int?

    /// `caret` beside a chip that starts or ends its paragraph brings Linear's image, and `drawn` its drawn caret, each a line.
    init(text: String, lines: [Sim.ListLine]? = nil, caret: Int? = nil, drawn drawnAt: Int? = nil) {
        self.text = text
        paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.lines = lines
        guard let lines else {
            shown = EmptyParagraphs.chromium(paragraphs)
            plainMarkers = shown.markers
            listMarkers = []
            chips = []
            joins = []
            gaps = []
            controls = []
            stops = []
            tables = []
            keyStops = [:]
            cells = []
            lastRows = []
            drawnCaret = nil
            drawnAtEnd = nil
            return
        }
        var drawnCaret: UnreachableLines.Caret?
        var drawnAtEnd: Int?
        var value = ""
        var raw = ""
        var found: [Int] = []
        var markers: [Int] = []
        var chips: [UnreachableLines.Chip] = []
        var joins: [Int] = []
        var gaps: Set<Int> = []
        var controls: [Range<Int>] = []
        var stops: [UnreachableLines.Stop] = []
        var tables: [UnreachableLines.Table] = []
        var keyStops: [Int: [ParagraphBreaks.Hidden.Kind]] = [:]
        var cells: Set<Int> = []
        var lastRows: Set<Int> = []
        var table: (start: Int, lastRow: Int?)?
        var plain = 0
        var start = 0
        var afterBreak = false
        // Chromium breaks the line before each block but the first, a `<br>` alone, or one after a `<br>`.
        func block(_ text: [UInt16], br: Bool = false) {
            if !value.isEmpty || !raw.isEmpty, !br, !afterBreak { value += "\n" }
            value += String(decoding: text, as: UTF16.self)
            afterBreak = br || (text.isEmpty && afterBreak)
        }
        for (index, paragraph) in paragraphs.enumerated() {
            let line = lines.indices.contains(index) ? lines[index] : Sim.ListLine()
            let units = Array(paragraph.utf16)
            let prefix = line.inline ? Array((line.marker ?? "").utf16) : []
            for _ in 0..<line.ruled {
                block([])
                raw += "\u{FFFC}"
            }
            if line.stop {
                joins.append(plain)
                gaps.insert(start)
            }
            stops += line.before.map { UnreachableLines.Stop(at: plain, kind: $0) }
            let own: [ParagraphBreaks.Hidden.Kind] = line.stop ? [line.leaves > 0 ? .boxedGap : .gap] : []
            if !(own + line.before).isEmpty { keyStops[start] = own + line.before }
            // A run of cell lines is a table, which ends where the line after it starts.
            if line.cell {
                cells.insert(start)
                if line.lastRow { lastRows.insert(start) }
                if table == nil { table = (plain, nil) }
                if line.lastRow { table?.lastRow = plain }
            } else if let open = table {
                tables.append(UnreachableLines.Table(range: open.start..<plain, lastRow: open.lastRow))
                table = nil
            }
            if let marker = line.marker {
                if line.controls { controls.append(plain..<(plain + marker.utf16.count)) } else { markers.append(plain) }
                if !line.inline {
                    block(Array(marker.utf16))
                    raw += marker
                }
                plain += marker.utf16.count
            }
            for _ in 0..<line.leaves {
                block([])
                raw += "\u{FFFC}"
            }
            guard !units.isEmpty else {
                // Chromium keeps the line of its own list's empty item, which holds the marker.
                if prefix.isEmpty { found.append(plain) } else { block(prefix) }
                raw += String(decoding: prefix, as: UTF16.self)
                block([10], br: true)
                raw += "\n"
                plain += 1
                start += 1
                continue
            }
            // Each chip is a line of its own, which spaces after it join, and one ending the paragraph is followed by a `<br>`.
            var parts: [[UInt16]] = []
            var pending: [UInt16] = []
            func flush() {
                guard !pending.isEmpty else { return }
                if parts.last == Self.label, pending.allSatisfy({ $0 == 0x20 }) {
                    parts[parts.count - 1] += pending
                } else {
                    parts.append(pending)
                }
                pending = []
            }
            var partsRaw: [UInt16] = []
            var paragraphChips: [Range<Int>] = []
            let paragraphStart = plain
            // Measured, there is none before a chip right after another chip's `<br>`.
            let followsBreak = afterBreak
            let drawn = drawnAt.flatMap { (start...(start + units.count)).contains($0) ? $0 - start : nil }
            for (offset, unit) in units.enumerated() {
                if offset == drawn {
                    flush()
                    // Measured, one starting a paragraph right after a `<br>` has no line of its own.
                    if offset > 0 || !followsBreak { parts.append([]) }
                    partsRaw.append(0xFFFC)
                    drawnCaret = UnreachableLines.Caret(offset: plain, place: offset == 0 ? .start : .middle)
                }
                guard unit == Self.chip else {
                    pending.append(unit)
                    partsRaw.append(unit)
                    plain += 1
                    continue
                }
                flush()
                if offset == 0, caret == start, !followsBreak {
                    parts.append([])
                    partsRaw.append(0xFFFC)
                }
                parts.append(Self.label)
                partsRaw += Self.label
                paragraphChips.append(plain..<(plain + Self.label.count))
                plain += Self.label.count
                if offset == units.count - 1, caret == start + units.count {
                    parts.append([])
                    partsRaw.append(0xFFFC)
                }
            }
            flush()
            if drawn == units.count {
                parts.append([])
                partsRaw.append(0xFFFC)
                drawnCaret = UnreachableLines.Caret(offset: plain, place: .end)
                drawnAtEnd = index
            }
            block(prefix + parts[0])
            raw += String(decoding: prefix, as: UTF16.self)
            for part in parts.dropFirst() { value += "\n" + String(decoding: part, as: UTF16.self) }
            raw += String(decoding: partsRaw, as: UTF16.self)
            if units.last == Self.chip || drawn == units.count {
                value += "\n"
                raw += "\n"
                plain += 1
                afterBreak = true
            } else if parts.count > 1 {
                afterBreak = false
            }
            chips += paragraphChips.map { UnreachableLines.Chip(range: $0, paragraph: paragraphStart..<plain) }
            start += units.count + 1
        }
        shown = (value, raw, found)
        plainMarkers = FieldReads.withoutAttachments(raw)
        listMarkers = markers
        self.chips = chips
        if let open = table { tables.append(UnreachableLines.Table(range: open.start..<plain, lastRow: open.lastRow)) }
        self.joins = joins
        self.gaps = gaps
        self.controls = controls
        self.stops = stops
        self.tables = tables
        self.keyStops = keyStops
        self.cells = cells
        self.lastRows = lastRows
        self.drawnCaret = drawnCaret
        self.drawnAtEnd = drawnAtEnd
    }

    /// The plain offset of each Sim offset; a caret after a chip ending its paragraph reads past the `<br>` after it.
    func field(_ offset: Int, caret: Bool = true) -> Int {
        var start = 0
        var plain = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let line = lines.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? Sim.ListLine()
            plain += line.marker?.utf16.count ?? 0
            let units = Array(paragraph.utf16)
            let chips = lines == nil ? 0 : units.filter { $0 == Self.chip }.count
            let trailing = lines != nil && units.last == Self.chip || drawnAtEnd == index ? 1 : 0
            if offset <= start + units.count {
                let local = offset - start
                let before = lines == nil ? 0 : units[..<local].filter { $0 == Self.chip }.count
                let past = caret && local == units.count && drawnAtEnd != index ? trailing : 0
                return plain + local + before * (Self.label.count - 1) + past
            }
            plain += max(units.count + chips * (Self.label.count - 1), 1) + trailing
            start += units.count + 1
        }
        return plain
    }

    func field(_ range: Range<Int>) -> Range<Int> {
        guard !range.isEmpty else { return field(range.lowerBound)..<field(range.lowerBound) }
        let (a, b) = (field(range.lowerBound, caret: false), field(range.upperBound, caret: false))
        return min(a, b)..<max(a, b)
    }

    /// Where a write lands: the last caret before `offset`, or at a marker or checkbox, the side `caret` comes from.
    func landing(_ offset: Int, from caret: Int) -> Int {
        let last = (0...text.utf16.count).last { field($0, caret: false) <= offset } ?? 0
        let units = Array(text.utf16)
        guard let lines else { return last }
        func prefix(_ start: Int) -> Sim.ListLine {
            let line = units[..<start].filter { $0 == 10 }.count
            return lines.indices.contains(line) ? lines[line] : Sim.ListLine()
        }
        if last > 0, units[last - 1] == 10, caret > last, prefix(last).checkbox, field(last - 1) == field(last) {
            return last - 1
        }
        guard last < units.count, units[last] == 10 else { return last }
        let next = prefix(last + 1)
        let marker = next.marker?.utf16.count ?? 0
        // Chromium's own list lands a write in its marker after it, whichever way the caret came.
        return marker > 0 && offset >= field(last + 1) - marker && (caret <= last || next.inline) ? last + 1 : last
    }

    /// Offsets of the chips, which keys cross in one step.
    var atoms: Set<Int> {
        guard lines != nil else { return [] }
        return Set(text.utf16.enumerated().filter { $0.element == Self.chip }.map(\.offset))
    }

    /// `Snapshotter.paragraphSide`: a paragraph's start, empty or not, reads as the start.
    static func side(_ offset: Int, in text: String) -> ParagraphBreaks.Side {
        offset == 0 || Array(text.utf16)[offset - 1] == 10 ? .start(skipping: 0) : .end
    }

    func side(_ offset: Int) -> ParagraphBreaks.Side {
        Self.side(offset, in: text)
    }

    func inEmptyParagraph(_ selection: Range<Int>) -> Bool {
        guard selection.isEmpty else { return false }
        let model = TextModel(text)
        return model.lineStart(of: selection.lowerBound) == model.lineBreak(of: selection.lowerBound)
    }
}
