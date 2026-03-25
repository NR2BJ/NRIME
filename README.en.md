# NRIME

[한국어](README.md) | English | [日本語](README.ja.md)

All-in-one input method for macOS. Handles Korean, English, and Japanese in a **single input source**.

- Instant language switching via shortcuts (no input source switching)
- Fully offline (no network required)
- Full Electron app support (VS Code, Slack, Discord, etc.)
- Japanese conversion powered by [Google Mozc](https://github.com/google/mozc) (BSD license)

## Installation

Download the latest `.pkg` from the [Releases](https://github.com/NR2BJ/NRIME/releases) page.

After installation, the NRIME icon appears in the menu bar.
If not visible, log out/in and add NRIME via **System Settings > Keyboard > Input Sources > Edit > +**.

## Usage

### Language Switching

Two switching modes are supported:

**Direct selection** — switch to a specific language
| Function | Default Shortcut |
|----------|-----------------|
| Switch to Korean | `Right Shift + 1` |
| Switch to Japanese | `Right Shift + 2` |

**Toggle** — switch between English and non-English
| Function | Default Shortcut |
|----------|-----------------|
| Toggle English / previous language | `Right Shift` tap |
| Toggle non-English mode | (unset — configure in settings) |

All shortcuts can be changed or **disabled** in settings. Use direct selection only, toggle only, or both.

### Korean

Dubeolsik layout. Hanja conversion: `Option + Enter` while composing (or after selecting text).

### Japanese

Romaji input > live hiragana conversion > `Space` for kanji conversion.

```
nihongo > にほんご > Space > 日本語
```

During conversion: `Up/Down` to navigate, `1-9` for direct selection, `Enter` to confirm, `Escape` to cancel.

<details>
<summary>Conversion key details</summary>

| Key | Function |
|-----|----------|
| Space / Tab / Down | Show candidates (each toggleable in settings) |
| F6 | Hiragana |
| F7 | Full-width katakana |
| F8 | Half-width katakana |
| F9 | Full-width romaji |
| F10 | Half-width romaji |

</details>

## Settings

Click the NRIME icon in the menu bar to open the settings app.

| Tab | Contents |
|-----|----------|
| General | Shortcut customization, inline indicator, conversion trigger selection |
| Japanese | Caps Lock/Shift behavior, punctuation style, live conversion, full-width space |
| Per-App | Remember last-used language per app |
| Developer | Diagnostic logs (local only, never uploaded) |

## Compatibility

| Environment | Status |
|------------|--------|
| Native macOS apps | Fully supported |
| Electron apps (VS Code, Slack, Discord, etc.) | Fully supported |
| Key remappers (Karabiner, BetterTouchTool) | No conflicts |
| Password fields | Auto-detected, delegated to system |
| Background processes | None (no LaunchAgents) |

## Uninstall

```bash
bash Tools/uninstall.sh
```

Log out/in to complete removal.

<details>
<summary>Manual uninstall</summary>

```bash
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# Clean up old LaunchAgents
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# Remove apps
rm -rf ~/Library/Input\ Methods/NRIME.app ~/Library/Input\ Methods/NRIMESettings.app ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app /Library/Input\ Methods/NRIMESettings.app /Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# Remove settings/data
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -rf ~/Library/Application\ Support/Mozc ~/Library/Caches/com.nrime.inputmethod.app ~/Library/Caches/com.nrime.settings ~/Library/Group\ Containers/group.com.nrime
```

</details>

<details>
<summary>Build from source (developers)</summary>

**Requirements:** macOS 13.0+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/build_pkg.sh
# Output: build/NRIME-<version>.pkg
```

</details>

## License

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
