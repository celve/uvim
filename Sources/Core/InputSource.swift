import Carbon.HIToolbox
import CoreGraphics

/// The keyboard input source macOS has selected, which an input method can hold letters back in (LIN-2053).
public enum InputSource {
    /// The selected input method's ID, such as `com.apple.inputmethod.SCIM.Shuangpin`; nil under a layout such as U.S.
    public static func selectedMethod() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = property(source, kTISPropertyInputSourceType),
              type != kTISTypeKeyboardLayout as String else { return nil }
        return property(source, kTISPropertyInputSourceID)
    }

    /// The current keyboard layout's text for the key under the event's own flags; main thread only, as TIS requires.
    public static func text(forKey keyCode: Int, flags: CGEventFlags) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var carbon = 0
        if flags.contains(.maskShift) { carbon |= shiftKey }
        if flags.contains(.maskAlphaShift) { carbon |= alphaLock }
        if flags.contains(.maskAlternate) { carbon |= optionKey }
        if flags.contains(.maskCommand) { carbon |= cmdKey }
        var deadKeys: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDown), UInt32((carbon >> 8) & 0xFF), UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, 4, &length, &buffer
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
