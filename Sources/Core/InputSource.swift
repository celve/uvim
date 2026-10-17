import Carbon.HIToolbox

/// The keyboard input source macOS has selected, which an input method can hold letters back in (LIN-2053).
public enum InputSource {
    /// The selected input method's ID, such as `com.apple.inputmethod.SCIM.Shuangpin`; nil under a layout such as U.S.
    public static func selectedMethod() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = property(source, kTISPropertyInputSourceType),
              type != kTISTypeKeyboardLayout as String else { return nil }
        return property(source, kTISPropertyInputSourceID)
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
