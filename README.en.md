# NRIME

[한국어](README.md) | English | [日本語](README.ja.md)

All-in-one input method for macOS. Handles Korean, English, and Japanese in a **single input source**.

- Instant language switching via shortcuts (no input source switching)
- Fully offline (no network required)
- Full Electron app support (VS Code, Slack, Discord, etc.)
- Japanese conversion powered by [Google Mozc](https://github.com/google/mozc) (BSD license)
- No background processes (no LaunchAgents)

## Installation

Download the latest `.pkg` from the [Releases](https://github.com/NR2BJ/NRIME/releases) page.

After installation, the NRIME icon appears in the menu bar.
If not visible, log out/in and add NRIME via **System Settings > Keyboard > Input Sources > Edit > +**.

## Features

### Language Switching

Two switching modes are supported. All shortcuts can be changed or **disabled** in settings.
Use direct selection only, toggle only, or both.

**Direct selection** — switch to a specific language

| Function | Default Shortcut |
|----------|-----------------|
| Switch to Korean | `Right Shift + 1` |
| Switch to Japanese | `Right Shift + 2` |

**Toggle** — switch between English and non-English

| Function | Default Shortcut |
|----------|-----------------|
| Toggle English / previous language | `Right Shift` tap |
| Toggle non-English mode (KR/JP) | (unset — configure in settings) |

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
| Left / Right | Move between segments |
| Shift + Left / Right | Resize segment |
| F6 | Hiragana |
| F7 | Full-width katakana |
| F8 | Half-width katakana |
| F9 | Full-width romaji |
| F10 | Half-width romaji |
| Tab | Select prediction |

</details>

### Additional Features

- **Shift double-tap > CapsLock toggle**: interval adjustable via slider (0.15-0.6s)
- **Shift+Enter delay**: adjustable delay for Electron app compatibility (default 15ms, 5-50ms)
- **Per-app language memory**: remembers last-used language per app (whitelist/blacklist mode)
- **Inline mode indicator**: shows current input mode near the cursor
- **Auto-update**: check and install updates from GitHub Releases (About tab)
- **Multilingual settings UI**: Korean/English/Japanese (changeable in About tab, restart required)
- **Settings export/import**: JSON backup for transferring settings
- **Developer mode**: diagnostic logging (local only, never uploaded)
- **Prevent ABC input source switching**: prevents the system from switching to ABC
- **Caps Lock for language switching**: works with Karabiner-Elements Caps Lock > F18 mapping

## Settings

Click the NRIME icon in the menu bar to open the settings app.

### General Tab

| Section | Contents |
|---------|----------|
| Shortcuts | English toggle, non-English toggle, Korean switch, Japanese switch, Hanja conversion — each customizable/disableable |
| Tap Threshold | Modifier-only tap recognition time slider (0.1-0.5s) |
| Shift Double-Tap > CapsLock | Double-tap interval adjustment (0.15-0.6s) |
| Shift+Enter Delay | Electron app compatibility delay (5-50ms) |
| Display | Inline mode indicator, prevent ABC switching, candidate font size, conversion trigger keys (Space/Tab/Down) |
| Developer Mode | Diagnostic log ON/OFF, open/reveal in Finder/clear log |
| Backup & Restore | Export settings (JSON) / import settings |

### Japanese Tab

| Section | Contents |
|---------|----------|
| Conversion Keys | Hiragana/full-width katakana/half-width katakana/full-width romaji/half-width romaji key customization |
| Key Behavior | Caps Lock action (default/katakana/romaji), Shift key action (none/katakana/romaji) |
| Space | Half-width/full-width space selection |
| Punctuation | Japanese style (。、) / Western style (．，), `/` > `・` mapping, `¥` key > `¥` mapping |
| Input Features | Live conversion, prediction |
| Conversion History | Clear Mozc conversion history |
| Conversion Shortcuts | In-conversion key reference guide |

### Per-App Tab

| Section | Contents |
|---------|----------|
| Per-app language memory | ON/OFF toggle |
| Mode | Whitelist (remember selected apps only) / Blacklist (exclude selected apps) |
| App list | Add/remove apps (file picker) |

### About Tab

| Section | Contents |
|---------|----------|
| Auto-update | Check latest version from GitHub Releases, download, install |
| Language setting | Change settings app UI language (Korean/English/Japanese) |

## Compatibility

| Environment | Status |
|------------|--------|
| Native macOS apps | ✓ Fully supported |
| Electron apps (VS Code, Slack, Discord, etc.) | ✓ Fully supported |
| Key remappers (Karabiner, BetterTouchTool) | ✓ No conflicts |
| Password fields | ✓ Auto-detected, delegated to system |
| Remote desktop | ✓ Fully supported |
| Background processes | None (no LaunchAgents) |

## Uninstall

```bash
bash Tools/uninstall.sh
```

Log out/in to complete removal.

<details>
<summary>Manual uninstall</summary>

```bash
# 1. Kill processes
killall NRIME NRIMESettings NRIMERestoreHelper mozc_server 2>/dev/null

# 2. Clean up old LaunchAgents
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist 2>/dev/null

# 3. Remove apps
rm -rf ~/Library/Input\ Methods/NRIME.app
rm -rf ~/Library/Input\ Methods/NRIMESettings.app
rm -rf ~/Library/Input\ Methods/NRIMERestoreHelper.app
sudo rm -rf /Library/Input\ Methods/NRIME.app
sudo rm -rf /Library/Input\ Methods/NRIMESettings.app
sudo rm -rf /Library/Input\ Methods/NRIMERestoreHelper.app

# 4. Remove old LaunchAgent files
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
sudo rm -f /Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist
rm -f ~/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist

# 5. Remove preferences
defaults delete com.nrime.inputmethod.app 2>/dev/null
defaults delete com.nrime.settings 2>/dev/null
defaults delete group.com.nrime.inputmethod 2>/dev/null
rm -f ~/Library/Preferences/com.nrime.inputmethod.app.plist
rm -f ~/Library/Preferences/com.nrime.settings.plist
rm -f ~/Library/Preferences/group.com.nrime.inputmethod.plist

# 6. Remove Mozc data and logs
rm -rf ~/Library/Application\ Support/Mozc
rm -rf ~/Library/Application\ Support/NRIME

# 7. Remove caches and containers
rm -rf ~/Library/Caches/com.nrime.inputmethod.app
rm -rf ~/Library/Caches/com.nrime.settings
rm -rf ~/Library/Group\ Containers/group.com.nrime
```

> NRIMERestoreHelper and LaunchAgents were used in older versions and are no longer installed.
> If upgrading from an older version, the commands above will clean up any leftover files.

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

<details>
<summary>Technical note: Electron/Chromium IME workaround</summary>

Explains the root cause and fix for text loss when pressing modifier+key during IME composition in Electron/Chromium apps. This workaround applies equally to native apps with no side effects.

### Root cause

**Shift+Enter**: No Shift+Return binding exists in macOS `StandardKeyBinding.dict`, so when Chromium calls `insertText:"\n"`, its `oldHasMarkedText` tracking logic misidentifies it as an IME composition event and drops the committed text.

**Cmd+key**: Goes through the `performKeyEquivalent:` path, so returning `false` from IMKit cannot pass the event to the app.

### Solution

| Case | Method |
|------|--------|
| **Shift+Enter** | Commit text > configurable delay (default 15ms) > `client.insertText("\n")` + `return true` |
| **Cmd+A/C/V/X/Z** | Commit text > tagged CGEvent repost via `.cghidEventTap` + `return true` |

### Approaches that failed

| Approach | Reason |
|----------|--------|
| `insertText + return false` | Chromium `oldHasMarkedText` misidentification |
| `setMarkedText("") + insertText + return false` | Same cause |
| Synchronous `insertText("\n")` | Ignored due to Chromium IPC batching |
| `CGEvent.post(.cgAnnotatedSessionEventTap)` | Electron ignores events on that tap |
| `CGEventPostToPSN` (deprecated) | Electron ignores direct PSN delivery |
| `NSAppleScript (System Events)` | Automation TCC not available for IMEs |

</details>

<details>
<summary>Technical note: Mozc IPC (Swift Mach IPC > C shim)</summary>

Direct Swift Mach OOL IPC implementation returned empty responses. Root cause unconfirmed (bitfield packing vs. pointer lifetime).
Resolved by using a C shim (`nrime_mozc_ipc.c`) matching the upstream mozc `mach_ipc.cc` structure.
mozc_server runs as an on-demand child process without LaunchAgents.

</details>

## License

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
