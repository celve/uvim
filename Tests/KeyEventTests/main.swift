import CoreGraphics

// Builds a key-down the way the tap receives it: `text` is what macOS resolved, `flags` what the poster set.
func keyEvent(_ keyCode: CGKeyCode, _ flags: CGEventFlags, _ text: String) -> KeyEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = flags
    let units = Array(text.utf16)
    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    return KeyEvent(cgType: .keyDown, cgEvent: event)!
}

func expect(_ event: KeyEvent, _ characters: String, line: UInt = #line) {
    precondition(
        event.characters == characters,
        "line \(line): got \(event.characters.unicodeScalars.map { String($0.value, radix: 16) }) want \(characters.debugDescription)"
    )
}

// Recorded on the Mac mini in Slack (LIN-3292): the `h` after a posted ⌃[ arrived bare with ⌃h's text.
expect(keyEvent(4, [], "\u{8}"), "h")
expect(keyEvent(4, .maskShift, "\u{8}"), "H")
expect(keyEvent(49, [], "\u{0}"), " ")

expect(keyEvent(4, [], "h"), "h")
expect(keyEvent(4, .maskControl, "\u{8}"), "\u{8}")
expect(keyEvent(33, .maskControl, "["), "[")
expect(keyEvent(36, [], "\r"), "\r")
expect(keyEvent(48, [], "\t"), "\t")
expect(keyEvent(53, [], "\u{1B}"), "\u{1B}")
expect(keyEvent(123, [], "\u{1C}"), "\u{1C}")
expect(keyEvent(115, [], "\u{1}"), "\u{1}")
expect(keyEvent(122, [], "\u{10}"), "\u{10}")

print("KeyEvent tests passed")
