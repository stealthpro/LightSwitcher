import ApplicationServices
import Carbon.HIToolbox

/// Types on the user's behalf. Events are tagged so `KeyboardMonitor` doesn't record them as typing.
enum KeyInjector {
    static let marker: Int64 = 0x4C53 // "LS"

    static func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            post(virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
            post(virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
        }
    }

    /// Types text, replacing the current selection if there is one.
    static func type(_ text: String) {
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
    }

    private static func postText(_ text: String) {
        let units = Array(text.utf16)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
    }

    private static func post(virtualKey: CGKeyCode, keyDown: Bool) {
        post(CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown))
    }

    private static func post(_ event: CGEvent?) {
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
