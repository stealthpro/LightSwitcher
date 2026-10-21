import AppKit
import Carbon.HIToolbox

/// Watches every key press and mouse click system-wide. It remembers the word being typed so it can be
/// converted later, and calls `onHotkey` when the switch shortcut is pressed.
@MainActor
final class KeyboardMonitor {
    var hotkey: Hotkey
    /// Ignores the shortcut while it is being re-recorded in Settings.
    var isSuspended = false
    /// Text typed since the last click or navigation key, as it appears on screen.
    var typedWord = ""
    /// True right after a conversion, when `typedWord` holds the converted text rather than typing.
    private var typedWordIsConverted = false
    var onHotkey: (() -> Void)?

    private var tap: CFMachPort?
    private var modifierComboHeld = false
    private var modifierComboUsedByKey = false

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Returns false if the system refused the event tap, which means permissions are missing.
    func start() -> Bool {
        let events: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { monitor.handle(type, event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .tapDisabledByUserInput:
            // Taps are disabled this way when permission is revoked. Re-enabling a revoked tap repeats the cycle and stalls input.
            if AXIsProcessTrusted(), let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .keyDown where event.getIntegerValueField(.eventSourceUserData) != KeyInjector.marker:
            if modifierComboHeld { modifierComboUsedByKey = true }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = NSEvent.ModifierFlags(cgFlags: event.flags)
            if !isSuspended, let key = hotkey.keyCode, key == keyCode, modifiers == hotkey.flags {
                fireHotkey()
                return nil // swallow the shortcut so the app underneath doesn't receive it
            }
            trackTyping(keyCode: keyCode, modifiers: modifiers, event: event)

        case .flagsChanged:
            if hotkey.keyCode == nil, updateModifierCombo(NSEvent.ModifierFlags(cgFlags: event.flags)) {
                fireHotkey()
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // The click may have moved the cursor, so the remembered word is no longer before it.
            typedWord = ""

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    /// Modifier-only shortcuts fire when the last of their keys is released, as long as no other key was pressed
    /// or extra modifier added while holding them. Returns true when the shortcut has just completed.
    private func updateModifierCombo(_ held: NSEvent.ModifierFlags) -> Bool {
        let target = hotkey.flags
        if modifierComboHeld {
            if !held.subtracting(target).isEmpty {
                modifierComboUsedByKey = true
            } else if held != target {
                modifierComboHeld = false
                return !modifierComboUsedByKey && !isSuspended
            }
        } else if held == target {
            modifierComboHeld = true
            modifierComboUsedByKey = false
        }
        return false
    }

    /// Remembers converted text, so pressing the shortcut again right away converts it back.
    func rememberConversion(_ converted: String) {
        typedWord = converted
        typedWordIsConverted = true
    }

    private func fireHotkey() {
        // Run after the event callback returns, so the tap never waits on the work below.
        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?()
        }
    }

    private func trackTyping(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, event: CGEvent) {
        // Shortcuts and secure input (passwords) are never remembered.
        if !modifiers.isDisjoint(with: [.command, .control]) || IsSecureEventInputEnabled() {
            typedWord = ""
            return
        }
        switch Int(keyCode) {
        case kVK_Delete:
            if !typedWord.isEmpty { typedWord.removeLast() }
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape, kVK_ForwardDelete,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            typedWord = ""
        default:
            let text = event.unicodeString
            guard !text.isEmpty else { return } // dead keys produce nothing until the next key
            // Spaces stay in the text so a whole phrase can be converted; control characters (such as Return) end it.
            if text.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                typedWord = ""
            } else {
                // Typing after a conversion starts a new phrase, so the converted text is left out of it.
                if typedWordIsConverted { typedWord = "" }
                typedWordIsConverted = false
                typedWord = String((typedWord + text).suffix(1000))
            }
        }
    }
}

private extension CGEvent {
    /// The text this key press produces with the current layout and modifiers.
    var unicodeString: String {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        return String(utf16CodeUnits: characters, count: length)
    }
}
