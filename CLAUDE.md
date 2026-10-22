# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Commands

The Xcode project is `LightSwitcher.xcodeproj` (one target, one scheme: `LightSwitcher`). There are no tests or linter.

```sh
# Debug build (Apple Silicon)
xcodebuild -project LightSwitcher.xcodeproj -scheme LightSwitcher -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ls-build build
open /tmp/ls-build/Build/Products/Debug/LightSwitcher.app

# Release DMG at dist/LightSwitcher.dmg (not notarized)
./make-dmg.sh
```

The app is a menu bar app (`LSUIElement`): no Dock icon and no window. Quit it from its menu bar item.

## Constraints

- **Unsandboxed** (`ENABLE_APP_SANDBOX = NO`). The sandbox blocks the global event tap and posted key events.
- **Accessibility only.** The permission is checked at launch (`AppDelegate.startMonitoring`). The event tap does not need Input Monitoring. Permission is tied to the build's signature, so a rebuild can reset it; relaunch after granting.
- **Threading.** Default actor isolation is `MainActor` (Swift 5.0). The event tap callback runs on the main run loop. `KeyInjector` posts events on its own queue, because `CGEvent.post` blocks until the window server accepts the event, and the window server waits on the main-thread tap. Posting from main can freeze all input. Keep any other code that touches the tap or TIS on the main thread.
- **Deployment target macOS 14.0**, required by the two-parameter `onChange` in `SettingsView`.

## Behavior

The app converts text typed on one keyboard layout into what the same physical keys produce on the other (`ghbdtn` → `привет`). It never switches automatically. The user presses the hotkey, which defaults to ⌃⌘. A modifier-only shortcut fires when its first key is released, unless another key or modifier was used while holding it.

A press acts on the selection if there is one, otherwise on typed text:

- **Selected text** is converted and stays selected, so the next press converts it back.
- **Typed text** is the text typed since the last click, Enter, Tab, Escape, navigation key, shortcut, or secure input. It is converted and replaced, and the result is remembered so the next press converts it back. Typing after a conversion starts a new phrase, which leaves the converted text unconverted.
- Otherwise the app beeps.

## Architecture

A press flows through `KeyboardMonitor` (event tap, hotkey match, typing buffer) to `AppDelegate.switchLayout()` (chooses selection or typed text), then through `LayoutConverter` (`KeyboardLayout.swift`), then through `KeyInjector` (`TextInput.swift`), which deletes and retypes the text and then selects the target layout.

- `KeyboardMonitor.swift`: owns the tap. Clears the typing buffer on shortcuts, navigation keys, Enter/Tab/Escape, mouse clicks, and secure input. Ignores its own injected events.
- `KeyboardLayout.swift`: reads layouts through TIS and `UCKeyTranslate`, and builds `LayoutConverter`. The converter maps only unmodified and Shift strokes. Option layers are left out because on Cyrillic layouts they hold Latin letters (Option+ф is `d`), which would convert text in both directions. Characters outside both layouts (digits, emoji, Option symbols) pass through unchanged.
- `TextInput.swift`: `KeyInjector` types text and keeps a selection (Shift+Left) when asked. `SelectionReader` reads the selected text through Accessibility.
- `AppDelegate.swift`: menu bar item, permission alert, and conversion orchestration. `main.swift` creates the delegate and runs the application.
- `Hotkey.swift`: the shortcut model. `AppSettings.swift`: preferences stored as JSON in `UserDefaults` under `switchHotkey`, shortcut recording, and `LaunchAtLogin` (`SMAppService`). `SettingsView.swift`: the Settings window.

**Loop prevention:** `KeyInjector` tags each posted event with `KeyInjector.marker` in `eventSourceUserData`. `KeyboardMonitor` ignores tagged events, so injected text is never treated as typing.
