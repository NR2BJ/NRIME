# NRIME

[한국어](README.md) | English | [日本語](README.ja.md)

All-in-one input method for macOS. Handles Korean, English, and Japanese in a **single input source**.

- Switch languages instantly with shortcuts — no input source switching
- Fully offline
- Japanese conversion powered by [Google Mozc](https://github.com/google/mozc) (BSD license)

## Installation

### PKG Install (Recommended)

Download the latest `.pkg` from the [Releases](https://github.com/NR2BJ/NRIME/releases) page and double-click to install.

NRIME will appear in your menu bar after installation.
If it doesn't, log out/in and add it from **System Settings → Keyboard → Input Sources → Edit → +**.

### Build from Source

<details>
<summary>For developers</summary>

**Requirements:**
- macOS 13.0 (Ventura) or later
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/NR2BJ/NRIME.git
cd NRIME
bash Tools/install.sh
```

Build PKG:
```bash
bash Tools/build_pkg.sh
# Output: build/NRIME-<version>.pkg
```

</details>

### Uninstall

Run the uninstall script to completely remove all traces:

```bash
bash Tools/uninstall.sh
```

Log out/in to complete the removal.

To uninstall directly from Terminal without the script:

```bash
killall NRIME NRIMESettings mozc_server 2>/dev/null; sudo rm -rf ~/Library/Input\ Methods/NRIME.app ~/Library/Input\ Methods/NRIMESettings.app /Library/Input\ Methods/NRIME.app /Library/Input\ Methods/NRIMESettings.app; defaults delete com.nrime.inputmethod.app 2>/dev/null; defaults delete com.nrime.settings 2>/dev/null; defaults delete group.com.nrime.inputmethod 2>/dev/null; rm -rf ~/Library/Application\ Support/Mozc ~/Library/Caches/com.nrime.inputmethod.app ~/Library/Caches/com.nrime.settings
```

## Default Shortcuts

| Function | Default Shortcut |
|----------|-----------------|
| Toggle English ↔ previous language | `Right Shift` tap |
| Switch to Korean | `Right Shift + 1` |
| Switch to Japanese | `Right Shift + 2` |
| Hanja conversion | `Option + Enter` |

All shortcuts can be customized in the settings app. Left/Right Shift, Ctrl, Option, and Cmd are distinguished separately.

## Usage

### English

Works identically to the system keyboard (passthrough).

### Korean

Dubeolsik layout. Characters being composed are shown with an underline and are committed automatically when the next character is typed.

**Hanja conversion:**
- Press `Option + Enter` while composing → candidate window appears
- Or select text by dragging, then press `Option + Enter`
- Navigate with `↑↓`, select by number `1-9`, confirm with `Enter`

### Japanese

Romaji input → real-time hiragana conversion → kanji conversion with Space.

```
Input: nihongo → にほんご → Space → 日本語
```

**Conversion flow:**
1. Type romaji → displayed as hiragana in real-time
2. `Space` or `↓` → show conversion candidates
3. `↑↓` to navigate, `1-9` to select directly
4. `Enter` to confirm, `Escape` to cancel

**Shift / Caps Lock behavior (configurable in settings):**

| Setting | Behavior |
|---------|----------|
| Katakana | Hold the key to type in katakana |
| Romaji | Hold the key to type romaji directly |

**Conversion keys (during composition):**

| Key | Function |
|-----|----------|
| F6 | Hiragana |
| F7 | Full-width katakana |
| F8 | Half-width katakana |
| F9 | Full-width romaji |
| F10 | Half-width romaji |

## Settings

Click the NRIME icon in the menu bar to open the settings app.

| Tab | Contents |
|-----|----------|
| General | Shortcut customization, inline mode indicator ON/OFF |
| Japanese | F6-F10 key settings, Caps Lock/Shift behavior, punctuation style |
| Per-App | Remember last language per app (whitelist/blacklist) |
| About | Version info |

## Compatibility

- **Key remapping apps**: No conflicts with Karabiner-Elements, BetterTouchTool, etc. (does not use CGEventTap for key monitoring)
- **Remote desktop**: Works normally
- **Password fields**: Automatically detected and delegated to the system

## License

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
