# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

The Xcode project is `LightSwitcher.xcodeproj` (one target, one scheme: `LightSwitcher`). There is no test target, linter, or package manager configuration.

```sh
# Debug build for Apple Silicon (matches the verified build)
xcodebuild -project LightSwitcher.xcodeproj -scheme LightSwitcher -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ls-build build

# Run the built app
open /tmp/ls-build/Build/Products/Debug/LightSwitcher.app
```

Running from Xcode (Cmd+R) also works. The app is a menu bar app with `LSUIElement`, so it has no Dock icon or main window. Quit it from its menu bar item.

## Things that are easy to get wrong

- **The app must stay unsandboxed** (`ENABLE_APP_SANDBOX = NO`). The global event tap and posted key events are blocked otherwise.
- **Permissions are per build.** Accessibility and Input Monitoring are checked at launch (`AppDelegate.startMonitoring`). Rebuilds with changing signatures can reset them, and the app must be relaunched after granting them.
- **Default actor isolation is `MainActor`** (`SWIFT_DEFAULT_ACTOR_ISOLATION`), and the Swift language version is 5.0. The event-tap callback runs on the main run loop and enters the main actor with `MainActor.assumeIsolated`. Keep new code that touches the tap or TIS on the main thread.
- **Deployment target is macOS 14.0**, which is required for the two-parameter `onChange` in `SettingsView` and for `SMAppService` in `AppSettings.swift`.

## Architecture

The app converts text typed on one keyboard layout into what the same physical keys produce on another (for example `ghbdtn` → `привет`). There is no automatic switching; the user presses the hotkey.

**Flow of a hotkey press:**

1. `KeyboardMonitor` owns a `CGEvent` tap (`.cgSessionEventTap`, `.defaultTap`) that sees every key press and mouse click. It keeps `typedWord`, the recent characters before the cursor, and clears it on shortcuts, navigation keys, Enter/Tab/Escape, mouse clicks, and secure input.
2. When the configured `Hotkey` is matched, the tap swallows the event and `fireHotkey` calls `onHotkey` on the next main-queue turn. A modifier-only hotkey (the default ⌃⌘) fires when its last modifier is released, unless a key or extra modifier was used while holding it.
3. `AppDelegate.switchLayout()` reads the current layout and the next enabled layout (`KeyboardLayout`), builds a `LayoutConverter` for them, and converts either the selected text (`SelectionReader`, via Accessibility) or the remembered word.
4. Output goes through `KeyInjector`: it deletes the typed word with backspaces and retypes the converted text with `keyboardSetUnicodeString`. It then calls `target.select()` to switch the input source.

**Loop prevention:** `KeyInjector` tags every posted event with `eventSourceUserData = 0x4C53`. `KeyboardMonitor` skips tagged keys when matching the hotkey or tracking typing, so injected text is never treated as user input.

**Layout conversion** (`KeyboardLayout.swift`): `LayoutConverter` builds a map from characters in the source layout to characters in the target layout by matching "strokes" (key code plus modifier state, none or Shift only). Option layers are deliberately excluded: on Cyrillic layouts they hold Latin letters (Option+ф is `d`), which made conversions cross-map and turn `фывфыв` into `asåaså` and then `фыdфыd`. The layouts are read through `UCKeyTranslate` on `kTISPropertyUnicodeKeyLayoutData`. Input methods without layout data are skipped. Characters that aren't in the map (digits, emoji, Option-only symbols such as `å`) are left as they are.

**Repeated switches:** after a word is converted, `AppDelegate` calls `KeyboardMonitor.rememberConversion`, so pressing the shortcut again converts it back. Typing after a conversion starts a new phrase, so the converted text is not converted again along with the new text.

**Settings:** `AppSettings` (an `ObservableObject`) stores the `Hotkey` as JSON in `UserDefaults` under `switchHotkey`. It also records a new shortcut through a local `NSEvent` monitor, and `AppDelegate` subscribes to its publishers to keep `KeyboardMonitor` in sync. While a shortcut is being recorded, `isSuspended` stops the monitor from firing it. `SettingsView` is a SwiftUI form hosted in an `NSWindow` created by `AppDelegate`. `LaunchAtLogin` wraps `SMAppService.mainApp`.

**Files:** `main.swift` (entry point; creates `AppDelegate` and runs `NSApplication`, since `@main` on the delegate did not install it), `AppDelegate.swift` (menu bar item, permissions, orchestration), `KeyboardMonitor.swift` (event tap and typing buffer), `KeyboardLayout.swift` (TIS and `UCKeyTranslate` layout access and converter), `TextInput.swift` (`KeyInjector` and `SelectionReader`), `Hotkey.swift` (hotkey model and `NSEvent.ModifierFlags` helpers), `AppSettings.swift`, `SettingsView.swift`.
