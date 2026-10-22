# LightSwitcher

LightSwitcher is a macOS menu bar app that fixes text typed with the wrong keyboard layout. Type `ghbdtn` while the US layout is active, press a shortcut, and it becomes `привет`. It works the other way too.

It never switches layouts or rewrites text on its own. You press the shortcut when you want a conversion.

## Features

- **Convert a selection.** Select text and press the shortcut. The text is converted and stays selected, so pressing the shortcut again converts it back.
- **Convert typed text.** With no selection, the shortcut converts the text you typed since your last click, Enter, Tab, Escape, navigation key, or shortcut. The result is remembered, so pressing the shortcut again converts it back.
- **Switch layout.** After each conversion, the app selects the other keyboard layout.
- **Customizable shortcut.** The default is ⌃⌘ (Control + Command). You can record a different shortcut in Settings, including modifier-only shortcuts.
- **Start on login.** Optional, set in Settings.

Conversion maps the keys of one layout to the keys of the next layout in your enabled input sources. Digits, punctuation that is the same on both layouts, emoji, and Option-key symbols pass through unchanged.

## Requirements

- macOS 14.0 or later
- Xcode, to build from source
- Accessibility permission (the app asks for it at first launch)

LightSwitcher is not sandboxed. The sandbox blocks the global keyboard event tap and posted key events that it needs.

## Install

### Download a build

Build the DMG yourself with `make-dmg.sh` (see below), open it, and drag LightSwitcher into Applications. The build is not notarized, so on another Mac you need to allow it in **System Settings → Privacy & Security** before it opens.

### Build from source

Open `LightSwitcher.xcodeproj` in Xcode and run the `LightSwitcher` scheme, or build from the command line:

```sh
xcodebuild -project LightSwitcher.xcodeproj -scheme LightSwitcher -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ls-build build
open /tmp/ls-build/Build/Products/Debug/LightSwitcher.app
```

To package a release DMG at `dist/LightSwitcher.dmg`:

```sh
./make-dmg.sh
```

## Granting Accessibility permission

LightSwitcher needs Accessibility access to watch keystrokes and insert converted text. On first launch, an alert offers to open System Settings. Enable LightSwitcher under **Privacy & Security → Accessibility**. The app then restarts itself.

Accessibility permission is tied to the app's code signature. After rebuilding, macOS may revoke it, so you may need to enable it again.

## Usage

1. Type text with the wrong layout active, or select it.
2. Press the shortcut (⌃⌘ by default).
3. Press it again to convert back.

The menu bar item shows the app's menu, including Settings and Quit. LightSwitcher has no Dock icon and no window.

## Project layout

| File | Purpose |
| --- | --- |
| `LightSwitcher/AppDelegate.swift` | Menu bar item, permission alert, and conversion flow |
| `LightSwitcher/KeyboardMonitor.swift` | Event tap, shortcut matching, and the typing buffer |
| `LightSwitcher/KeyboardLayout.swift` | Reads layouts through Text Input Sources and builds the converter |
| `LightSwitcher/TextInput.swift` | Types replacement text and reads selections through Accessibility |
| `LightSwitcher/Hotkey.swift` | Shortcut model |
| `LightSwitcher/AppSettings.swift` | Saved preferences, shortcut recording, and launch-at-login |
| `LightSwitcher/SettingsView.swift` | Settings window |
| `make-dmg.sh` | Release build and DMG packaging |

`CLAUDE.md` has more detail on threading and architecture for contributors.

## License

No license has been specified yet.
