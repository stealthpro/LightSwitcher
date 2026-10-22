import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var monitor = KeyboardMonitor(hotkey: settings.hotkey)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.$hotkey
            .sink { [weak self] in self?.monitor.hotkey = $0 }
            .store(in: &subscriptions)
        settings.$isRecordingHotkey
            .sink { [weak self] in self?.monitor.isSuspended = $0 }
            .store(in: &subscriptions)
        monitor.onHotkey = { [weak self] in self?.switchLayout() }

        setUpStatusItem()
        startMonitoring()
    }

    /// Converts the selection, or the word typed before the cursor, to the other keyboard layout.
    private func switchLayout() {
        guard let source = KeyboardLayout.current(),
              let target = KeyboardLayout.next(after: source) else {
            NSSound.beep()
            return
        }
        let converter = LayoutConverter(from: source, to: target)

        if let selection = SelectionReader.selectedText(), !selection.isEmpty {
            monitor.typedWord = ""
            // Stays selected, so pressing the shortcut again converts it back.
            KeyInjector.replace(deleting: 0, with: converter.convert(selection), keepSelected: true) { target.select() }
        } else if !monitor.typedWord.isEmpty {
            let word = monitor.typedWord
            let converted = converter.convert(word)
            // Keep the converted word, so pressing the shortcut again converts it back.
            monitor.rememberConversion(converted)
            KeyInjector.replace(deleting: word.count, with: converted) { target.select() }
        } else {
            NSSound.beep()
        }
    }

    private func startMonitoring() {
        // Accessibility lets us watch key presses through the event tap, read selections, and type text.
        // No system prompt here: showPermissionAlert explains the step and opens the same settings pane.
        let trusted = AXIsProcessTrusted()
        if !monitor.start() || !trusted {
            if !trusted { relaunchWhenTrusted() }
            showPermissionAlert()
        }
    }

    /// macOS applies an Accessibility grant only to processes started after it, so this one can't use the event tap.
    /// Watch for the grant, then restart the app.
    private func relaunchWhenTrusted() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.relaunch()
            }
        }
        // Common modes, so the watch keeps running while the permission alert is open.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    /// Starts a helper that waits for this process to exit, then opens the app again.
    private func relaunch() {
        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; open \"$2\""
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        try? helper.run()
        NSApp.abortModal() // ends the permission alert if it is still open
        NSApp.terminate(nil)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "LightSwitcher needs permissions"
        alert.informativeText = "Allow LightSwitcher under Accessibility in System Settings → Privacy & Security. The app restarts by itself once it is allowed."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LightSwitcher")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LightSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            // A fixed content size: the hosting controller reported no height, so the window collapsed to its title bar.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.title = "LightSwitcher"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
