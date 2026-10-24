// MARK: - Put

extension PhysicalPlanner {
    static func lowerPut(
        _ source: LogicalStep.PutSource,
        _ action: PutAction,
        count: Int,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        guard repeats(count) else { return nil }
        switch source {
        case .pasteboard(let wise):
            // Content lives in macOS and is consumed ONLY via a synthesized
            // ⌘V — the event queue orders it behind the ⌘X that filled the
            // pasteboard; a direct engine read would race it. All lanes
            // paste this way; a readable field still positions exactly.
            var steps: [PhysicalStep] = []
            switch wise {
            case .character, .block:   // block degrades to characterwise
                if let model = context.model, let position = context.position {
                    let target = putTarget(action, at: position, model: model)
                    guard let moved = moveSteps(to: target, context: &context, profile: profile) else { return nil }
                    steps += moved
                } else if action.position == .after {
                    steps.append(.press(.right, count: 1))
                }
            case .line:
                // Linewise cuts carry their own trailing newline and ⌘V is
                // verbatim, so the target must be a line START. Finding the
                // next line's start is document geography — a scoped field
                // drops to the blind branch below.
                if let model = context.linewiseModel(profile), let position = context.position {
                    let end = model.lineBreak(of: position)
                    let target = action.position == .after
                        ? (end >= model.length ? model.visibleOffset(end) : end + 1)
                        : model.lineStart(of: position)
                    guard let moved = moveSteps(to: target, as: lineTarget(action, end: end, model: model),
                                                context: &context, profile: profile) else { return nil }
                    steps += moved
                } else if action.position == .after {
                    // Next line start. On the last line .down no-ops and the
                    // paste lands above — a well-formed line misplaced beats
                    // a malformed merge.
                    steps.append(.press(.down, count: 1))
                    steps.append(.press(.lineStart, count: 1))
                } else {
                    steps.append(.press(.lineStart, count: 1))
                }
            }
            steps += Array(repeating: PhysicalStep.clipboardInsert(nil), count: max(1, count))
            context.invalidate()
            return steps

        case .content(let content):
            guard !content.text.isEmpty else { return [] }
            let payload = String(repeating: content.text, count: max(1, count))
            switch content.wise {
            case .character, .block:   // block degrades to characterwise, v1
                return putCharacterwise(payload, action: action, context: &context, profile: profile)
            case .line:
                // Each copy is a whole line: a last line or `cc` leaves its register without the newline.
                let line = content.text.hasSuffix("\n") ? content.text : content.text + "\n"
                return putLinewise(String(repeating: line, count: max(1, count)), action: action,
                                   context: &context, profile: profile)
            }
        }
    }

    private static func putCharacterwise(
        _ payload: String,
        action: PutAction,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        if let model = context.model, let position = context.position {
            let target = putTarget(action, at: position, model: model)
            guard var steps = moveSteps(to: target, context: &context, profile: profile) else { return nil }
            steps += insertSteps(payload, after: steps, context: &context, profile: profile)
            return steps
        }
        var steps: [PhysicalStep] = []
        if action.position == .after {
            steps.append(.press(.right, count: 1))
        }
        steps.append(.clipboardInsert(payload))
        context.invalidate()
        return steps
    }

    /// After the character at the caret, or at the caret, and never among the invisible characters ending a line.
    private static func putTarget(_ action: PutAction, at caret: Int, model: TextModel) -> Int {
        let position = model.visibleOffset(caret)
        return action.position == .after ? min(model.advance(position, byGraphemes: 1), model.lineEnd(of: position)) : position
    }

    private static func putLinewise(
        _ text: String,
        action: PutAction,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        // "Is this the last line?" is document geography: in a scoped field
        // `model.length` is the block's end, not the page's.
        if let model = context.linewiseModel(profile), let position = context.position {
            var insertion = text
            let target: Int
            let end = model.lineBreak(of: position)
            if action.position == .after {
                if end >= model.length {
                    // Last line without a terminator: lead with the newline.
                    target = model.visibleOffset(end)
                    insertion = "\n" + String(text.dropLast())
                } else {
                    target = end + 1
                }
            } else {
                target = model.lineStart(of: position)
            }
            guard var steps = moveSteps(to: target, as: lineTarget(action, end: end, model: model),
                                        context: &context, profile: profile) else { return nil }
            steps += insertSteps(insertion, after: steps, context: &context, profile: profile)
            return steps
        }
        context.invalidate()
        if action.position == .after {
            return [.press(.lineEnd, count: 1), .clipboardInsert("\n" + String(text.dropLast()))]
        }
        return [.press(.lineStart, count: 1), .clipboardInsert(text)]
    }

    /// What a linewise put's target is to the native keys; nil for the next line's start, which is a hop.
    private static func lineTarget(_ action: PutAction, end: Int, model: TextModel) -> LogicalStep.Destination? {
        guard action.position == .after else { return .motion(.lineStart(firstNonBlank: false), count: 1) }
        return end >= model.length ? .motion(.lineEnd, count: 1) : nil
    }

    private static func moveSteps(
        to target: Int,
        as destination: LogicalStep.Destination? = nil,
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep]? {
        let steps: [PhysicalStep]
        if profile.has(.writeSelection) {
            steps = write(target..<target, context: context)
        } else if let model = context.model, let selection = context.selection {
            switch nativeMove(destination, to: target, model: model, context: &context, profile: profile) {
            case .steps(let keys): return keys
            case .next: steps = keyPath(from: selection, to: target, model: model, context: context)
            case .reject: return nil
            }
        } else {
            steps = []
        }
        context.selection = target..<target
        return steps
    }

    /// Bulk insertion at the predicted caret: AX when possible, paste
    /// otherwise (typing long content is slow and lossy).
    private static func insertSteps(
        _ text: String,
        after positioning: [PhysicalStep],
        context: inout Context,
        profile: CapabilityProfile
    ) -> [PhysicalStep] {
        let action: PhysicalStep = profile.has(.insertText)
            ? .replaceSelection(text)
            : .clipboardInsert(text)
        if let selection = context.selection, context.text != nil {
            // An AX insertion can overtake queued keys; a paste cannot, and native keys already settled.
            let pressed = positioning.last.map { if case .press = $0 { return true }; return false } ?? false
            let barrier = pressed && profile.has(.insertText) ? settle(context, profile: profile) : []
            context.applyEdit(range: selection, replacement: text)
            // Blind (paste) insert is async: soft, so it never aborts what follows.
            return barrier + [action] + settle(context, profile: profile, hard: profile.has(.insertText))
        }
        context.invalidate()
        return [action]
    }
}
