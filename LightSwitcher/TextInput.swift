import ApplicationServices
import Carbon.HIToolbox

/// Types on the user's behalf. Events are tagged so `KeyboardMonitor` doesn't record them as typing.
enum KeyInjector {
    nonisolated static let marker: Int64 = 0x4C53 // "LS"

    /// Posting blocks until the window server accepts the event, and the window server waits for our event tap, which
    /// runs on the main thread. Posting from the main thread could therefore deadlock and freeze all input, so events
    /// are posted on this queue instead.
    private nonisolated static let queue = DispatchQueue(label: "LightSwitcher.KeyInjector")

    /// Deletes `count` characters before the cursor, then types `text`, replacing the current selection if there is one.
    /// With `keepSelected`, the typed text is selected afterwards so the next switch can convert it back.
    /// `done` runs on the main thread after the events have been posted.
    static func replace(deleting count: Int, with text: String, keepSelected: Bool = false, then done: @escaping @MainActor () -> Void) {
        queue.async {
            for _ in 0..<count {
                postKey(CGKeyCode(kVK_Delete))
            }
            // Keyboard events carry at most a short run of UTF-16 units, so send the text in pieces.
            var chunk = ""
            for character in text {
                if chunk.utf16.count + character.utf16.count > 16 {
                    postText(chunk)
                    chunk = ""
                }
                chunk.append(character)
            }
            if !chunk.isEmpty {
                postText(chunk)
            }
            if keepSelected {
                // The cursor is at the end of the typed text, and each Shift+Left extends the selection back by one character.
                for _ in 0..<text.count {
                    postKey(CGKeyCode(kVK_LeftArrow), flags: .maskShift)
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    private nonisolated static func postText(_ text: String) {
        let units = Array(text.utf16)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event, flags: [])
        }
    }

    private nonisolated static func postKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for keyDown in [true, false] {
            post(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: keyDown), flags: flags)
        }
    }

    private nonisolated static func post(_ event: CGEvent?, flags: CGEventFlags) {
        guard let event else { return }
        // The shortcut's Control and Command may still be physically held; `flags` replaces them so the app sees only what we intend.
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }
}

/// Reads the text selected in the focused control, using the Accessibility API.
enum SelectionReader {
    /// Seconds to wait for an app before giving up. Without a limit, a hung app would stall the main thread, and with it the event tap.
    private static let messagingTimeout: Float = 1

    static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue else { return nil }

        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success else {
            return nil
        }
        return selectedValue as? String
    }
}
