// MARK: - Mutation

extension PhysicalPlanner {
    /// Register wise-ness from selection kind. No blockwise selection is
    /// planned yet, so the width is never real.
    private static func registerWise(_ kind: VisualKind?) -> Wise {
        switch kind ?? .character {
        case .character: return .character
        case .line: return .line
        case .block: return .block(width: 0)
        }
    }

    static func lowerDelete(
        into register: Register?,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        let wise = registerWise(context.selectionWise)
        let blackhole = register?.name == "_"
        if let model = context.model, let selection = context.selection {
            let breakAbove = context.breakAbove
            let ending = breakAbove != nil
            guard !selection.isEmpty || ending else { return [] }
            let text = model.substring(selection)
            // The register holds lines that ended the text as it holds any: the newline after them.
            let content = context.content(selection, text) + (ending ? "\n" : "")
            var steps: [PhysicalStep] = []
            if !selection.isEmpty {
                let writes = breakAbove == nil && profile.has(.insertText)
                steps += checkSelectedText(text, context: context, profile: profile)
                let held = context.expectation(.exact(selection), profile: profile)
                steps.append(writes ? .replaceSelection("") : .press(.deleteBack, count: 1))
                context.applyEdit(range: selection, replacement: "")
                // A rich editor's ⌫ lands inexactly, so its settle is soft, unless the field reads as if ⌫ were ignored.
                steps += settle(context, profile: profile, hard: writes, deleting: writes ? nil : held)
            }
            if let above = breakAbove {
                // The line break above goes last, by one ⌫ from a caret on the emptied lines, so nothing above them is ever selected;
                // Chrome makes a further ⌫ over an invisible character its own undo step.
                steps.append(.press(.deleteBack, count: 1))
                context.applyEdit(range: above, replacement: "")
                // Rich editors differ on whether invisible characters ending the line above go with its newline (Lark's do).
                if context.breaks != nil, above.count > 1 { context.unknown.insert(.length) }
                steps += settle(context, profile: profile, hard: context.breaks == nil)
            }
            if !blackhole {
                steps.append(.commit(.deleted(into: register, content: .literal(content), wise: wise)))
            }
            guard ending else { return steps }
            context.breakAbove = nil
            // Nothing reads whether Chromium's line break went, so the caret moves from wherever it is.
            guard context.breaks == nil else { return steps + relativeLanding(context: &context, profile: profile) }
            return lowerMove(.motion(.lineStart(firstNonBlank: true), count: 1), context: &context, profile: profile)
                .map { steps + $0 }
        }
        guard context.selectionOpaque else { return nil }
        context.selectionOpaque = false
        context.invalidate()
        if blackhole {
            return [.press(.deleteBack, count: 1)]
        }
        // Blind delete IS the cut: the pasteboard becomes the register
        // (clipboard=unnamed), nothing is read back, silence on failure.
        return [
            .clipboardCut,
            .commit(.deleted(into: register, content: .pasteboard, wise: wise)),
        ]
    }

    /// Keys to the first non-blank from where the unconfirmed delete left the caret, → first collapsing lines it left selected to their end.
    private static func relativeLanding(context: inout Context, profile: CapabilityProfile) -> [PhysicalStep] {
        var steps: [PhysicalStep] = [.press(.right, count: 1)]
        steps += settle(context, profile: profile, hard: false)
        guard profile.has(.lineStartKey), let model = context.model, let caret = context.caret else { return steps }
        let target = model.firstNonBlank(inLineOf: caret)
        let column = model.graphemes(in: model.lineStart(of: caret)..<target)
        context.selection = target..<target
        steps.append(.press(.paragraphStart, count: 1))
        if column > 0 {
            steps += run(.right, count: column, selecting: context.arrowsSelect, normalizing: context.normalizes(target))
        }
        return steps + settle(context, profile: profile)
    }

    static func lowerYank(
        into register: Register?,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        guard register?.name != "_" else { return [] }
        let wise = registerWise(context.selectionWise)
        if let model = context.model, let selection = context.selection {
            guard !selection.isEmpty else { return [] }
            let content = context.content(selection, model.substring(selection))
            guard registersFromField(content, profile) else {
                return [.commit(.yanked(into: register, content: .literal(content), wise: wise))]
            }
            let slot = context.takeSlot()
            return [.captureSelectedText(into: slot), .commit(.yanked(into: register, content: .captured(slot), wise: wise))]
        }
        guard context.selectionOpaque else { return nil }
        // An opaque selection was built by presses, which are QUEUED at the
        // window server; an AX read is synchronous and would beat them,
        // capturing the selection as it was before. Channels must not cross:
        // ⌘C rides the same queue as the presses and therefore sees them.
        // (This is why the tempting `readSelectedText` fast path — instant,
        // and literal text instead of a pasteboard marker — is wrong here.)
        return [.clipboardCopy, .commit(.yanked(into: register, content: .pasteboard, wise: wise))]
    }

    /// `insertText` and `replaceSelection` are the same lowering: AX
    /// replacement replaces whatever is selected, and a caret is an empty
    /// selection; typed text replaces a selection too.
    static func lowerTypeOver(
        _ replacement: String,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        if let selection = context.selection, context.retypesStructure(selection) { return nil }
        let action = profile.has(.insertText) ? .replaceSelection(replacement) : blindText(replacement, context: context)
        if let selection = context.selection, let model = context.model {
            let check = checkSelectedText(model.substring(selection), context: context, profile: profile)
            context.applyEdit(range: selection, replacement: replacement)
            // Blind (typeText) over-type: soft, so a mismatch does not abort
            // the `setMode(.insert)` behind an `o`/`O`/`i`.
            let steps = check + [action] + settle(context, profile: profile, hard: profile.has(.insertText))
            // Chromium leaves a new empty paragraph out of `AXValue` until it holds text, so later settles stop checking the length.
            if !profile.has(.insertText), context.breaks != nil, replacement.contains("\n") {
                context.unknown.insert(.length)
            }
            return steps
        }
        context.invalidate()
        // Blind keys may still be queued, and typing or pasting rides the same queue.
        return [context.keysQueued ? blindText(replacement, context: context) : action]
    }

    /// A typed `\n` makes no paragraph in Chromium's rich text, and ⏎ would send a chat message, so web content pastes it.
    private static func blindText(_ text: String, context: Context) -> PhysicalStep {
        context.webContent && text.contains("\n") ? .clipboardInsert(text) : .typeText(text)
    }

    static func lowerTransform(
        _ transform: LogicalStep.SelectionTransform,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        guard let model = context.model, let selection = context.selection, !selection.isEmpty,
              !context.retypesStructure(selection) else {
            return nil   // content must be readable to rewrite it
        }
        let original = model.substring(selection)
        let transformed: String
        switch transform {
        case .toggleCase:
            transformed = original.reduce(into: "") { result, character in
                if character.isUppercase {
                    result += character.lowercased()
                } else if character.isLowercase {
                    result += character.uppercased()
                } else {
                    result.append(character)
                }
            }
        case .lowercase:
            transformed = original.lowercased()
        case .uppercase:
            transformed = original.uppercased()
        case .shiftRight:
            transformed = mapLines(of: original) { Self.indentUnit + $0 }
        case .shiftLeft:
            transformed = mapLines(of: original) { line in
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                var trimmed = line[...]
                for _ in 0..<Self.indentUnit.count where trimmed.first == " " {
                    trimmed = trimmed.dropFirst()
                }
                return String(trimmed)
            }
        }
        let action = profile.has(.insertText) ? .replaceSelection(transformed) : blindText(transformed, context: context)
        let check = checkSelectedText(original, context: context, profile: profile)
        context.applyEdit(range: selection, replacement: transformed)
        // Blind (typeText) transform: soft. The poll still lets the following
        // `collapseSelection` land its caret on a settled field.
        return check + [action] + settle(context, profile: profile, hard: profile.has(.insertText))
    }

    private static let indentUnit = "    "

    private static func mapLines(of text: String, _ transform: (String) -> String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { transform(String($0)) }
            .joined(separator: "\n")
    }

    static func lowerJoin(
        count: Int,
        keepWhitespace: Bool,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        // Definitionally cross-line, and there is no blind spelling: the
        // whitespace rules below are the whole point of the function, and a
        // chord approximation cannot compute them. Scoped fields ring.
        guard let model = context.linewiseModel(profile), let selection = context.selection else { return nil }
        let position = selection.lowerBound
        let range = model.lines(from: position, count: count, extent: .interior)
        guard !context.retypesStructure(range) else { return nil }
        let lines = model.visibleText(in: range)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.count > 1 else { return [] }
        var joined = lines[0]
        for line in lines.dropFirst() {
            if keepWhitespace {
                joined += line
            } else {
                let stripped = line.drop { $0 == " " || $0 == "\t" }
                joined += joined.isEmpty || joined.hasSuffix(" ") ? String(stripped) : " " + stripped
            }
        }
        var steps: [PhysicalStep] = []
        var settled = false
        if profile.has(.writeSelection) {
            steps += write(range, from: selection.isEmpty ? selection.lowerBound : nil, context: context)
        } else {
            switch nativeSelect(.lines(count: count, extent: .interior), range: range,
                                context: &context, profile: profile) {
            case .steps(let keys):
                steps += keys
                settled = true
            case .next:
                steps += keyPath(from: selection, to: range.lowerBound, model: model, context: context)
                steps.append(.press(.selectRight, count: model.graphemes(in: range)))
            case .reject:
                return nil
            }
        }
        context.selection = range
        // Settled, so the AX replacement cannot overtake the selecting keys.
        var barrier = checkSelectedText(model.substring(range), context: context, profile: profile)
        if barrier.isEmpty, !settled, presses(steps), profile.has(.insertText) {
            barrier = settle(context, profile: profile)
        }
        steps += barrier
        steps.append(profile.has(.insertText) ? .replaceSelection(joined) : .typeText(joined))
        context.applyEdit(range: range, replacement: joined)
        // Settle follows the edit; blind (typeText) join is soft.
        return steps + settle(context, profile: profile, hard: profile.has(.insertText))
    }
}
