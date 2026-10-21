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
    /// `done` runs on the main thread after the events have been posted.
    static func replace(deleting count: Int, with text: String, then done: @escaping @MainActor () -> Void) {
        queue.async {
            for _ in 0..<count {
                post(virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
                post(virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
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
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    private nonisolated static func postText(_ text: String) {
        let units = Array(text.utf16)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
    }

    private nonisolated static func post(virtualKey: CGKeyCode, keyDown: Bool) {
        post(CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown))
    }

    private nonisolated static func post(_ event: CGEvent?) {
        guard let event else { return }
        // The shortcut's Control and Command may still be physically held; clear them so the app sees plain keys.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }
}

/// Reads the text selected in the focused control, using the Accessibility API.
enum SelectionReader {
    static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue else { return nil }

        var selectedValue: CFTypeRef?
        let element = focused as! AXUIElement
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success else {
            return nil
        }
        return selectedValue as? String
    }
}
