import AppKit

/// A global keyboard shortcut. Modifier-only shortcuts (such as ⌃⌘) have no key.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt16?
    var keyName: String?
    /// `NSEvent.ModifierFlags.rawValue`, limited to the shortcut modifiers.
    var modifiers: UInt

    static let defaultShortcut = Hotkey(
        keyCode: nil,
        keyName: nil,
        modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue
    )

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (keyName ?? "")
    }
}

extension NSEvent.ModifierFlags {
    static let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// Keeps only the shortcut modifiers from event-tap flags (drops caps lock, fn and device bits).
    init(cgFlags: CGEventFlags) {
        self = []
        if cgFlags.contains(.maskCommand) { insert(.command) }
        if cgFlags.contains(.maskControl) { insert(.control) }
        if cgFlags.contains(.maskAlternate) { insert(.option) }
        if cgFlags.contains(.maskShift) { insert(.shift) }
    }
}
