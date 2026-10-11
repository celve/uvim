import Foundation

// The argument domain stands in for a stored choice, so no defaults are written.

func normalModeKey(stored value: String?) -> NormalModeKey {
    UserDefaults.standard.setVolatileDomain(
        value.map { [Prefs.normalModeKeyKey: $0] } ?? [:], forName: UserDefaults.argumentDomain
    )
    return Prefs.normalModeKey
}

precondition(normalModeKey(stored: nil) == .escape, "Esc until the user chooses")
precondition(normalModeKey(stored: "controlBracket") == .controlBracket, "a stored ⌃[ outlives the default")
precondition(normalModeKey(stored: "escape") == .escape)
precondition(normalModeKey(stored: "meta") == .escape, "a value no build wrote reads as the default")

print("Prefs tests passed")
