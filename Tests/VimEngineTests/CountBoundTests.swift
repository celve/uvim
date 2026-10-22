// MARK: - Count bounds (LIN-1103)

func testCountBounds() {
    do {
        let huge = "99999999999999999999"
        let limit = Count.repeatLimit
        let down = Motion.line(.down, firstNonBlank: false)
        let nextWord = Motion.word(.forward, end: false, bigWord: false)

        for (keys, count) in [("999999999j", Count.max), ("1000000000j", Count.max), (huge + "j", Count.max),
                              ("999999999\"a999999999j", Count.max), ("2\"a3j", 6), ("1\u{663}j", 1)] {
            precondition(RawCommand(keys).count == count, keys)
        }
        precondition(Count.product(.max, 2) == Count.max && Count.product(Count.max, Count.max) == Count.max)
        precondition(RawCommand("d" + huge + "j").intent
            == .operatorCommand(.init(kind: .delete, targetCount: Count.max, target: .motion(down))))
        precondition(plan(huge + "d" + huge + "w").steps.first
            == .select(.span(to: .motion(nextWord, count: Count.max), inclusive: false)))
        precondition(RawCommand("1\u{301}j").intent == .custom(keys: "1\u{301}j"), "a digit under a combining mark is no count")
        precondition(RawCommand("d1\u{301}").intent == .operatorCommand(.init(kind: .delete, target: .custom(keys: "1\u{301}"))))

        // A held key stops growing the buffer: a digit at a full count, a prompt's text at the limit, where ⌫ and ⏎ still work.
        var held = RawMonitor()
        for key in String(repeating: "9", count: 300) + "d" + String(repeating: "7", count: 300) {
            precondition(held.feed(String(key), mode: .normal) == .pending)
        }
        precondition(held.feed("d", mode: .normal) == .command(.init(command: RawCommand("99999999999d77777777777d"))))
        precondition(RawCommand("99999999999d77777777777d").count == Count.max)
        for (typed, kept, count) in [("\"1123456789x", "\"1123456789x", 123_456_789),
                                     ("\"112345678905x", "\"11234567890x", Count.max)] {
            var named = RawMonitor()
            for key in typed.dropLast() { precondition(named.feed(String(key), mode: .normal) == .pending) }
            precondition(named.feed("x", mode: .normal) == .command(.init(command: RawCommand(kept))), typed)
            precondition(RawCommand(kept).count == count && RawCommand(kept).register == Register("1"), typed)
        }
        var prompt = RawMonitor()
        for key in "/" + String(repeating: "7", count: 300) {
            precondition(prompt.feed(String(key), mode: .normal) == .pending)
        }
        precondition(prompt.pendingKeys.utf16.count == RawMonitor.pendingLimit)
        precondition(prompt.feed("<BS>", mode: .normal) == .pending)
        precondition(prompt.feed("<CR>", mode: .normal) == .command(.init(command: RawCommand(
            "/" + String(repeating: "7", count: RawMonitor.pendingLimit - 2) + "<CR>"
        ))))
        var prefixes = RawMonitor()
        for key in String(repeating: "\"a", count: 300) {
            _ = prefixes.feed(String(key), mode: .normal)
            precondition(prefixes.pendingKeys.utf16.count <= RawMonitor.pendingLimit)
        }

        // On text a count costs what the text does: a loop to `Int.max` would never return.
        let model = TextModel("one two three\nfour five six")
        for (motion, from, landing) in [(nextWord, 0, 27), (Motion.word(.forward, end: true, bigWord: false), 0, 26),
                                        (Motion.word(.backward, end: false, bigWord: false), 27, 0)] {
            precondition(model.destination(of: motion, from: from, count: .max) == landing, "\(motion)")
        }
        let ring = TextModel("ab ab ab")
        for from in 0...8 {
            for forward in [true, false] {
                var stepped = from
                for count in 1...7 {
                    stepped = forward ? [0, 3, 6].first { $0 > stepped } ?? 0 : [0, 3, 6].last { $0 < stepped } ?? 6
                    precondition(ring.search("ab", from: from, forward: forward, count: count) == stepped, "\(from) \(count)")
                }
            }
        }
        precondition(ring.search("ab", from: 0, forward: true, count: .max) == 3)

        // With no text to stop it a lane repeats to the limit and no further: the blind lane, the last, then rings.
        func lowered(_ step: LogicalStep, text: String? = nil, profile: CapabilityProfile = blindProfile) -> PhysicalPlan {
            PhysicalPlanner.plan(
                LogicalPlan(step), snapshot: FieldSnapshot(capabilities: profile, text: text, selection: text.map { _ in 0..<0 })
            )
        }
        let twice = RegisterContent(text: "ab", wise: .character)
        let after = PutAction(position: .after)
        precondition(lowered(.moveCaret(.motion(down, count: limit))) == PhysicalPlan(.press(.down, count: limit)))
        precondition(lowered(.moveCaret(.motion(.lineEnd, count: .max))) == PhysicalPlan(.press(.lineEnd, count: 1)))
        precondition(lowered(.select(.lineSpan(to: .motion(down, count: limit), extent: .whole)))
            == PhysicalPlan(.press(.lineStart, count: 1), .press(.selectDown, count: limit + 1)))
        precondition(lowered(.put(.content(twice), after, count: limit), text: "x", profile: axProfile).steps
            .contains(.replaceSelection(String(repeating: "ab", count: limit))))
        for count in [limit + 1, Count.max, Int.max] {
            for step: LogicalStep in [
                .moveCaret(.motion(down, count: count)), .extendSelection(.motion(.character(.right), count: count)),
                .select(.span(to: .motion(nextWord, count: count), inclusive: false)),
                .select(.lines(count: count, extent: .whole)), .select(.lines(count: count, extent: .interior)),
                .select(.lineSpan(to: .motion(down, count: count), extent: .whole)),
                .put(.pasteboard(wise: .character), after, count: count), .put(.content(twice), after, count: count),
            ] {
                precondition(lowered(step) == .rejected, "\(step)")
                if case .put = step { precondition(lowered(step, text: "x", profile: axProfile) == .rejected, "\(step)") }
            }
        }
        precondition(plan("1000rx").steps.contains(.replaceSelection(String(repeating: "x", count: limit))))
        precondition(plan("1001rx").steps == [.bell(.unsupported("1001rx"))])
        precondition(physical("1000}", profile: nativeBlind).steps.first == .press(.paragraphForward, count: limit))
        precondition(physical("1001}", profile: nativeBlind) == .rejected)

        // The native line keys leave an over-limit step to lane B, and the app's keys leave it to vim's words.
        let lined = "one two\nthree four\nfive six"
        let vimWords = removing([.nativeMotions], from: nativeRead)
        for (keys, caret, other) in [("dd", 0, readProfile), ("yy", 0, readProfile), ("J", 0, readProfile), ("dj", 0, readProfile),
                                     ("dk", 20, readProfile), ("d$", 0, readProfile), ("$", 0, readProfile),
                                     ("w", 0, vimWords), ("dw", 0, vimWords)] {
            precondition(physical("1000" + keys, text: lined, caret: caret, profile: nativeRead)
                != physical("1000" + keys, text: lined, caret: caret, profile: other), keys)
            for count in ["1001", huge] {
                precondition(physical(count + keys, text: lined, caret: caret, profile: nativeRead)
                    == physical(count + keys, text: lined, caret: caret, profile: other), count + keys)
            }
        }
        for step: LogicalStep in [
            .moveCaret(.motion(nextWord, count: .max)), .moveCaret(.motion(.lineEnd, count: .max)),
            .select(.lines(count: .max, extent: .whole)), .joinLines(count: .max, keepWhitespace: false),
            .select(.lineSpan(to: .motion(down, count: .max), extent: .whole)),
            .select(.lineSpan(to: .motion(.line(.up, firstNonBlank: false), count: .max), extent: .whole)),
            .select(.span(to: .motion(.lineEnd, count: .max), inclusive: false)),
            .select(.textObject(TextObject(scope: .around, kind: .word(bigWord: false)), count: .max)),
        ] {
            for profile in [axProfile, readProfile, nativeRead] {
                precondition(lowered(step, text: lined, profile: profile) != .rejected, "\(step)")
            }
        }

        // End to end, a count past the text does what a count just past it does, by writes and by keys.
        struct Outcome: Equatable {
            var text: String
            var selection: Range<Int>
            var mode: VimState.Mode
            var registers: VimState.Registers
            var rings: [Int]
        }
        let document = "one two three\nfour five six\nseven eight nine"
        func outcome(_ keys: String, caret: Int, profile: CapabilityProfile) -> Outcome {
            var host = keyedSim(document, caret: caret, profile: profile)
            host.type(keys)
            return Outcome(text: host.text, selection: host.selection, mode: host.state.field.mode,
                           registers: host.state.session.registers, rings: [host.bells, host.settleFailures, host.unsupportedSteps])
        }
        let commands: [(String) -> String] = [
            { $0 + "w" }, { $0 + "e" }, { $0 + "b" }, { $0 + "W" }, { $0 + "j" }, { $0 + "k" }, { $0 + "l" }, { $0 + "h" },
            { $0 + "$" }, { $0 + "x" }, { $0 + "X" }, { $0 + "~" }, { $0 + "J" }, { $0 + "dd" }, { $0 + "yy" }, { $0 + "dw" },
            { "d" + $0 + "b" }, { $0 + "d" + $0 + "e" }, { "d" + $0 + "j" }, { "d" + $0 + "k" }, { "d" + $0 + "$" },
            { "d" + $0 + "iw" }, { "y" + $0 + "aw" }, { "x" + $0 + "." }, { $0 + "fe" },
        ]
        for caret in [0, 5, 14, 22, 43] {
            for command in commands {
                for profile in [axProfile, noCursorProfile, noInsertProfile, readProfile] {
                    precondition(outcome(command(huge), caret: caret, profile: profile)
                        == outcome(command("500"), caret: caret, profile: profile), "\(command("N")) at \(caret)")
                }
                precondition(outcome(command(huge), caret: caret, profile: nativeRead)
                    == outcome(command(huge), caret: caret, profile: readProfile), "native \(command("N")) at \(caret)")
            }
            precondition(outcome("v" + huge + "wd", caret: caret, profile: axProfile)
                == outcome("v500wd", caret: caret, profile: axProfile), "Visual at \(caret)")
        }
        let unread = typed(huge + "j", text: document, caret: 0, profile: blindProfile)
        precondition(unread.bells == 1 && unread.unsupportedSteps == 0 && unread.text == document)
        precondition(typed("v" + huge + "l", text: document, caret: 0, profile: readProfile).bells == 1)
    }
}
