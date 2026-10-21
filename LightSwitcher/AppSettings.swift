import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement

/// Saved preferences, plus the state of the shortcut recorder in Settings.
@MainActor
final class AppSettings: ObservableObject {
    private static let hotkeyKey = "switchHotkey"

    @Published var hotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: Self.hotkeyKey)
            }
        }
    }
    @Published private(set) var isRecordingHotkey = false

    private var recordingMonitor: Any?
    private var heldModifiers: NSEvent.ModifierFlags = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyKey),
           let saved = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = saved
        } else {
            hotkey = .defaultShortcut
        }
    }

    func beginRecordingHotkey() {
        guard recordingMonitor == nil else { return }
        isRecordingHotkey = true
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.record(event)
        }
    }

    func cancelRecordingHotkey() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        heldModifiers = []
        isRecordingHotkey = false
    }

    /// Escape cancels. A key needs Control, Option or Command. A modifier-only shortcut needs two modifiers (e.g. ⌃⌘).
    private func record(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.shortcutModifiers)

        if event.type == .keyDown {
            if Int(event.keyCode) == kVK_Escape {
                cancelRecordingHotkey()
                return nil
            }
            guard !modifiers.intersection([.command, .control, .option]).isEmpty else {
                NSSound.beep()
                return nil
            }
            let letter = event.charactersIgnoringModifiers?.uppercased() ?? ""
            hotkey = Hotkey(
                keyCode: event.keyCode,
                keyName: letter.isEmpty ? "Key \(event.keyCode)" : letter,
                modifiers: modifiers.rawValue
            )
            cancelRecordingHotkey()
            return nil
        }

        // flagsChanged: collect modifiers while they are held, and commit once all of them are released.
        heldModifiers.formUnion(modifiers)
        if modifiers.isEmpty {
            if heldModifiers.rawValue.nonzeroBitCount >= 2 {
                hotkey = Hotkey(keyCode: nil, keyName: nil, modifiers: heldModifiers.rawValue)
                cancelRecordingHotkey()
            }
            heldModifiers = []
        }
        return nil
    }
}

/// "Start on login" via the system login-item service (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
