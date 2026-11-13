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

// MARK: - Fork settings, on an in-memory store: nothing reaches cfprefsd or ~/Library/Preferences.

final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    private var registered: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] ?? registered[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
    override func register(defaults: [String: Any]) { registered.merge(defaults) { _, new in new } }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    func clear() { values = [:] }
}

let suite = MemoryDefaults(suiteName: nil)!
Prefs.store = suite
var failures: [String] = []
func check(_ condition: Bool, _ message: String = "") {
    if !condition { failures.append(message) }
}

Prefs.registerDefaults()
check(Prefs.policy(for: "com.microsoft.VSCode") == .off, "VS Code starts Off")
check(Prefs.policy(for: "com.vscodium") == .off, "the fork's new seeds start Off")
check(Prefs.policy(for: "com.jetbrains.intellij") == .off, "JetBrains by prefix")
check(Prefs.policy(for: "com.apple.Notes") == .auto, "other apps are Auto")
check(Prefs.clipboardMode == .yank, "yanks reach the clipboard by default")
check(Prefs.appScope == .everywhere)

// Only these apps.
Prefs.appScope = .onlyAllowed
check(Prefs.policy(for: "com.apple.Notes") == .off, "only-allowed: an app never set is Off")
Prefs.setPolicy(.auto, for: "com.apple.Notes")
check(Prefs.policy(for: "com.apple.Notes") == .auto, "only-allowed: an app set to Auto engages")
Prefs.setPolicy(.forced, for: "com.example.Silent")
check(Prefs.policy(for: "com.example.Silent") == .forced, "Force needs no allowing")
Prefs.setPolicy(.off, for: "com.apple.Notes")
check(Prefs.policy(for: "com.apple.Notes") == .off)
Prefs.setPolicy(.auto, for: "com.jetbrains.intellij")
check(Prefs.policy(for: "com.jetbrains.intellij") == .auto, "a prefix app can be allowed")
Prefs.appScope = .everywhere
check(Prefs.policy(for: "com.apple.TextEdit") == .auto, "everywhere: an app never set is Auto again")

// Every set reads back, in both scopes (the menu picker must never show a lie).
for scope in AppScope.allCases {
    Prefs.appScope = scope
    for id in ["com.apple.Notes", "com.microsoft.VSCode", "com.jetbrains.goland", "com.example.New"] {
        for policy in VimPolicy.allCases {
            Prefs.setPolicy(policy, for: id)
            check(Prefs.policy(for: id) == policy, "\(scope): \(id) set \(policy) reads \(Prefs.policy(for: id))")
        }
    }
}
Prefs.appScope = .everywhere

// Clipboard: a global default, per-app overrides.
Prefs.clipboardMode = .unnamed
check(Prefs.clipboardMode(for: "com.apple.Notes") == .unnamed, "an app follows the default")
Prefs.setClipboardOverride(.off, for: "com.apple.Notes")
check(Prefs.clipboardMode(for: "com.apple.Notes") == .off, "an app's own setting wins")
check(Prefs.clipboardOverride(for: "com.apple.Mail") == nil, "no override until one is set")
Prefs.setClipboardOverride(nil, for: "com.apple.Notes")
check(Prefs.clipboardMode(for: "com.apple.Notes") == .unnamed, "clearing it follows the default again")

// The Apps window's list, forget and reset.
Prefs.setClipboardOverride(.yank, for: "com.apple.Mail")
let listed = Prefs.configuredApps()
check(listed.contains("com.apple.Mail") && listed.contains("com.microsoft.VSCode") && listed.contains("com.apple.Notes"),
      "the list holds seeded, chosen and clipboard-only apps: \(listed)")
check(listed == listed.sorted() && Set(listed).count == listed.count, "sorted, no repeats")
Prefs.forget(bundleID: "com.apple.Mail")
check(!Prefs.configuredApps().contains("com.apple.Mail"), "forget drops the row")
Prefs.setPolicy(.auto, for: "com.microsoft.VSCode")
Prefs.forget(bundleID: "com.microsoft.VSCode")
check(Prefs.policy(for: "com.microsoft.VSCode") == .auto, "a forgotten seed follows the scope, not the seed")
Prefs.resetApps()
check(Prefs.policy(for: "com.microsoft.VSCode") == .off, "reset brings the built-in list back")
check(Prefs.policy(for: "com.apple.Notes") == .auto, "reset drops the user's own choices")
check(Prefs.clipboardMode == .unnamed, "reset keeps the global settings")

// A seed added in a later build reaches an install whose user already wrote the list.
suite.clear()
suite.set(["com.apple.Terminal"], forKey: Prefs.disabledIDsKey)   // an upstream user who removed most seeds
suite.set(["com.vscodium"], forKey: Prefs.allowedIDsKey)          // and chose Auto for one new seed
Prefs.registerDefaults()
check(Prefs.policy(for: "com.microsoft.VSCodeInsiders") == .off, "a new seed is added to a written list")
check(Prefs.policy(for: "com.vscodium") == .auto, "a new seed never overrides the user's choice")
check(Prefs.policy(for: "com.microsoft.VSCode") == .auto, "an upstream seed the user removed stays removed")
Prefs.setPolicy(.auto, for: "com.microsoft.VSCodeInsiders")
Prefs.registerDefaults()
check(Prefs.policy(for: "com.microsoft.VSCodeInsiders") == .auto, "each seed is applied once")

Prefs.store = .standard
if !failures.isEmpty {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
print("Prefs tests passed")
