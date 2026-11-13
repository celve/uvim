import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// The fork's Apps window: every app with a setting of its own, its Vim
/// policy and clipboard setting, and the "only these apps" switch.
///
/// A plain NSWindow rather than a SwiftUI `Window` scene: on macOS 14 a
/// scene would open by itself at launch, and uvim is a menu-bar agent.
@MainActor
final class AppsWindow {
    static let shared = AppsWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        model.reloadApps()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AppsView(model: model)))
            window.title = "uvim Apps"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 500))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension ClipboardMode {
    var label: String {
        switch self {
        case .off: "Off"
        case .yank: "Yanks"
        case .unnamed: "Yanks and deletes"
        }
    }
}

extension VimPolicy {
    var label: String {
        switch self {
        case .auto: "Auto"
        case .off: "Off"
        case .forced: "Force"
        }
    }
}

struct AppsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Set<String> = []
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("uvim runs in:", selection: $model.appScope) {
                Text("Every app except those set to Off").tag(AppScope.everywhere)
                Text("Only apps set to Auto or Force").tag(AppScope.onlyAllowed)
            }
            .pickerStyle(.radioGroup)

            Picker("Clipboard default:", selection: $model.clipboardMode) {
                ForEach(ClipboardMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()

            Table(model.apps, selection: $selection) {
                TableColumn("App") { row in
                    HStack(spacing: 6) {
                        Image(nsImage: row.icon).resizable().frame(width: 16, height: 16)
                        Text(row.name)
                        if !row.installed {
                            Text("not installed").foregroundStyle(.secondary)
                        }
                    }
                    .help(row.id)
                }
                TableColumn("Vim") { row in
                    Picker("Vim", selection: Binding(
                        get: { row.policy },
                        set: { model.setPolicy($0, for: row.id) }
                    )) {
                        ForEach(VimPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                .width(min: 90, ideal: 100)
                TableColumn("Clipboard") { row in
                    Picker("Clipboard", selection: Binding(
                        get: { row.clipboard },
                        set: { model.setClipboard($0, for: row.id) }
                    )) {
                        Text("Default (\(model.clipboardMode.label))").tag(ClipboardMode?.none)
                        ForEach(ClipboardMode.allCases, id: \.self) { Text($0.label).tag(ClipboardMode?.some($0)) }
                    }
                    .labelsHidden()
                }
                .width(min: 150, ideal: 190)
            }

            Text(footnote).font(.caption).foregroundStyle(.secondary)

            HStack {
                Menu("Add App") {
                    ForEach(model.runningApps) { app in
                        Button(app.name) { model.addApp(app.id) }
                    }
                    Divider()
                    Button("Choose from Applications…") { model.chooseApps() }
                }
                .fixedSize()
                Button("Remove") {
                    selection.forEach(model.forgetApp)
                    selection = []
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("Reset to Built-in List…") { confirmingReset = true }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .confirmationDialog("Reset every app to uvim's built-in list?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetApps() }
        } message: {
            Text("Your per-app Vim and clipboard settings are removed. The two settings above stay.")
        }
    }

    private var footnote: String {
        var parts: [String] = []
        switch model.appScope {
        case .everywhere: parts.append("Apps not listed are Auto. A new app added here starts Off.")
        case .onlyAllowed: parts.append("Apps not listed are Off. A new app added here starts Auto.")
        }
        if !model.appPrefixes.isEmpty {
            let families = model.appPrefixes.map { "\($0)*" }.joined(separator: ", ")
            parts.append("Apps whose ID starts with \(families) are Off unless listed as Auto or Force.")
        }
        return parts.joined(separator: " ")
    }
}
