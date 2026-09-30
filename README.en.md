# NRIME

[한국어](README.md) | English | [日本語](README.ja.md)

All-in-one input method for macOS. Handles Korean, English, and Japanese in a **single input source**.

- Instant language switching via shortcuts (no input source switching)
- Typing and conversion stay on this Mac (nothing you type leaves it; the network is used only to check GitHub for updates)
- Full Electron app support (VS Code, Slack, Discord, etc.)
- Japanese conversion powered by [Google Mozc](https://github.com/google/mozc) (BSD license)
- No background processes (no LaunchAgents)

## Installation

Download the latest `.pkg` from the [Releases](https://github.com/NR2BJ/NRIME/releases) page.

After installation, the NRIME icon appears in the menu bar.
If not visible, log out/in and add NRIME via **System Settings > Keyboard > Input Sources > Edit > +**.

## Features

### Language Switching

Two shortcuts switch languages. Both can be changed or **disabled** in settings.

| Function | Default Shortcut |
|----------|-----------------|
| Toggle English (between English and the previous language) | `Right Shift` tap |
| Toggle Non-English Mode (between Korean and Japanese) | `Shift + Space` |

### Korean

Dubeolsik layout. Hanja conversion: `Option + Enter` while composing (or after selecting text).

### Japanese

Romaji input > hiragana composition > `Space` for kanji conversion.

```
nihongo > にほんご > Space > 日本語
```

During conversion: `Up/Down` to navigate, `1-9` for direct selection, `Enter` to confirm, `Escape` to cancel.

<details>
<summary>Conversion key details</summary>

| Key | Function |
|-----|----------|
| Space / Tab | Start conversion (while composing — each toggleable in settings) |
| Up / Down | Navigate candidates |
| Left / Right | Move between segments (pages the list when there is one) |
| Shift + Left / Right | Resize segment |
| 1 – 9 | Pick a candidate by number |
| Tab | Expand / collapse candidates (while the candidate window is open) |
| Enter | Confirm conversion |
| Escape | Cancel conversion |

</details>

### Additional Features

- **Inline mode indicator**: shows the current input mode near the text cursor (or mouse cursor) when the mode changes
- **Japanese user dictionary**: register your own words (reading, word, part of speech) as conversion candidates (Japanese tab > User Dictionary)
- **Auto-update**: check and install updates from GitHub Releases (About tab, Stable/Beta channel)
- **Multilingual settings UI**: Korean/English/Japanese (changeable in About tab, applies immediately)
- **Settings export/import**: JSON backup for transferring settings
- **Developer mode**: diagnostic logging (local only, never uploaded)
- **Prevent ABC input source switching**: prevents the system from switching to ABC
- **Switch to ABC while typing passwords**: while macOS secure input is on (password fields), hands the keyboard to the ABC layout and switches back afterwards (on by default)
- **Fast tap-switch correction (experimental)**: fixes stray capitals/double consonants when typing too quickly after a Shift tap (off by default)
- **Caps Lock for language switching**: works with Karabiner-Elements Caps Lock > F18 mapping

## Settings

Click the NRIME icon in the menu bar to open the settings app.

### General Tab

| Section | Contents |
|---------|----------|
| Shortcuts | Toggle English, Toggle Non-English Mode, Hanja Conversion — each can be recorded (Record) or disabled (Clear) |
| Tap Threshold | Modifier-only tap recognition time slider (0.1-0.5s) |
| Fast tap-switch correction (experimental) | Fixes stray capitals/double consonants when typing right after a Shift tap (off by default). Keys where Shift means nothing always switch; double consonants and capitals only when Shift comes up within 30 ms; a double consonant mid-word never does |
| Display | Show inline indicator on mode switch (Indicator Position: Text Cursor/Mouse Cursor), Prevent switching to ABC, Switch to ABC while typing passwords, Candidate Font Size (12-24pt) |
| Shift+Enter newline wait | Newline insert and ⌘ shortcuts (0-100 ms, default 20 ms: the newline in apps built on web technology, and ⌘ shortcuts re-sent in any app), Shift+Enter re-send (0-100 ms, default 50 ms), the list of apps that get Shift+Enter re-sent (apps that send the message on an inserted newline, Codex by default — add/remove apps). The waits are kept per Mac |
| Input method permissions | Device Control and Data Access (Accessibility on macOS 26 and earlier) status, Check again / Request, Open System Settings — needed to re-send ⌘+key or Codex Shift+Enter to the app after committing |
| Developer | Enable Developer Mode (diagnostic log), Open Log/Reveal in Finder/Clear Log |
| Backup & Restore | Export Settings (JSON) / Import Settings |

### Japanese Tab

Switch between the **Settings** and **User Dictionary** pages at the top.

**Settings**

| Section | Contents |
|---------|----------|
| Conversion Trigger Keys | Space, Tab — keys that start conversion while composing (each ON/OFF) |
| Key Behavior | Caps Lock Action — Caps Lock (Default)/Convert to Katakana/Convert to Romaji |
| Space | Space Width — Half-width (U+0020)/Full-width (U+3000), applies when not composing |
| Punctuation & Symbols | Punctuation Style — Japanese (。、)/Full-width Western (．，)/Half-width Western (.,), output preview, `/` key > `・` (Nakaguro), `\` key > `¥` (Yen Sign) |
| Conversion Engine (Mozc) | Mozc version in use; check for a newer one and apply it at once |
| Conversion History | Clear Mozc conversion history |
| Conversion Shortcuts | In-conversion key reference guide |

**User Dictionary**

| Item | Contents |
|------|----------|
| Word list | Reading (hiragana), word, part of speech, comment; search |
| Editing | `+` to add, double-click to edit, `−` to delete |
| Auto-learning | Auto-learned conversions are not listed — clear them with Clear Conversion History on the Settings page |

### About Tab

| Section | Contents |
|---------|----------|
| Version | Current version, GitHub link |
| Auto-update | Check latest version from GitHub Releases, download, install |
| Update Channel | Stable/Beta (beta receives test builds first) |
| Language | Change settings app UI language (Korean/English/Japanese) |

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

**Requirements:** macOS 13.0+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen), [bazelisk](https://github.com/bazelbuild/bazelisk) (`brew install bazelisk` — builds the Mozc conversion engine from source; the first build takes a few minutes)

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
| **Shift+Enter** | Commit text > `client.insertText("\n")` 20 ms later + `return true` (apps that send the message when `\n` is inserted, like Codex, get the Shift+Enter key press again 50 ms later instead; without the wait a slower Mac loses the syllable being composed) |
| **Cmd+A/C/V/X/Z** | Commit text > CGEvent repost via `.cghidEventTap` + `return true` |

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
<summary>Technical note: Mozc embedded</summary>

The Mozc conversion engine runs inside the input method: Mozc is built as a library (`libnrime_mozc.dylib`, `Tools/mozc`) that the input method loads at run time, and conversion commands pass Mozc's own protocol (protobuf) through function calls. A conversion takes about a millisecond.
NRIME used to launch `mozc_server` as a separate process and talk to it over Mach IPC; typing waited whenever the server hung or restarted, so it was embedded in 2026-09.
The Mozc commit is pinned in `Tools/mozc/MOZC_COMMIT` and moved to the latest upstream commit for every beta release (`Tools/mozc/update.sh`, which keeps the update only if it builds and the tests pass).
Mozc also updates without a new NRIME. GitHub Actions (`.github/workflows/mozc-component.yml`) checks upstream every week for a new version or data, builds and tests it, and publishes it as a `mozc-<abi>-<date>-<commit>` prerelease. The input method checks daily, downloads it (verified by SHA-256) and uses it from its next start (Settings > Japanese can apply it at once), falling back to the engine in the app if the new one fails.

</details>

## License

- NRIME: MIT License
- [Google Mozc](https://github.com/google/mozc): BSD 3-Clause License
