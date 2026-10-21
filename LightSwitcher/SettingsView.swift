import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Start on login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                LabeledContent("Switch layout") {
                    HStack {
                        Button(shortcutLabel) {
                            if settings.isRecordingHotkey {
                                settings.cancelRecordingHotkey()
                            } else {
                                settings.beginRecordingHotkey()
                            }
                        }
                        .frame(minWidth: 110)

                        if settings.hotkey != .defaultShortcut {
                            Button("Reset") { settings.hotkey = .defaultShortcut }
                        }
                    }
                }
            } footer: {
                Text("Select text, or place the cursor after text you typed, then press the shortcut. The text is converted to the next keyboard layout and the layout is switched. Press Escape while recording to cancel.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private var shortcutLabel: String {
        settings.isRecordingHotkey ? "Press shortcut…" : settings.hotkey.displayString
    }
}
