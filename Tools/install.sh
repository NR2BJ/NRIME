#!/bin/bash
# NRIME Install Script
# Builds and installs NRIME input method to user-level Input Methods directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/Debug"
INSTALL_DIR="$HOME/Library/Input Methods"
APP_NAME="NRIME.app"
SETTINGS_APP="NRIMESettings.app"
RESTORE_HELPER_APP="NRIMERestoreHelper.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENTS_DIR/com.nrime.inputmethod.loginrestore.plist"

echo "=== NRIME Installer ==="

# Always build fresh to avoid stale cache issues
echo "Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "Building NRIME..."
xcodebuild -project NRIME.xcodeproj -scheme NRIME -configuration Debug \
    SYMROOT="$PROJECT_DIR/build" build

echo "Building NRIMESettings..."
xcodebuild -project NRIME.xcodeproj -scheme NRIMESettings -configuration Debug \
    SYMROOT="$PROJECT_DIR/build" build

echo "Building NRIMERestoreHelper..."
xcodebuild -project NRIME.xcodeproj -scheme NRIMERestoreHelper -configuration Debug \
    SYMROOT="$PROJECT_DIR/build" build

# Install FIRST (before kill, so macOS restarts with the NEW binary)
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$BUILD_DIR/$APP_NAME" "$INSTALL_DIR/"

# Install companion app next to input method
rm -rf "$INSTALL_DIR/$SETTINGS_APP"
cp -R "$BUILD_DIR/$SETTINGS_APP" "$INSTALL_DIR/"
rm -rf "$INSTALL_DIR/$RESTORE_HELPER_APP"
cp -R "$BUILD_DIR/$RESTORE_HELPER_APP" "$INSTALL_DIR/"

# Strip quarantine/provenance xattrs (macOS Sequoia marks cp'd files as untrusted,
# causing the input method to appear grayed-out in the input source menu)
xattr -cr "$INSTALL_DIR/$APP_NAME"
xattr -cr "$INSTALL_DIR/$SETTINGS_APP"
xattr -cr "$INSTALL_DIR/$RESTORE_HELPER_APP"

# Ensure executables have execute permissions
chmod +x "$INSTALL_DIR/$APP_NAME/Contents/MacOS/NRIME"
chmod +x "$INSTALL_DIR/$SETTINGS_APP/Contents/MacOS/NRIMESettings"
chmod +x "$INSTALL_DIR/$RESTORE_HELPER_APP/Contents/MacOS/NRIMERestoreHelper"
chmod +x "$INSTALL_DIR/$APP_NAME/Contents/Resources/mozc_server" 2>/dev/null || true

# Kill AFTER install — macOS auto-restarts the IME with the new binary
echo "Restarting NRIME process..."
killall NRIME 2>/dev/null || true
killall NRIMESettings 2>/dev/null || true
killall NRIMERestoreHelper 2>/dev/null || true
sleep 1

# Register with LaunchServices (ensures macOS knows about the new location)
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
echo "Registering with LaunchServices..."
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME"
"$LSREGISTER" -f "$INSTALL_DIR/$SETTINGS_APP"
"$LSREGISTER" -f "$INSTALL_DIR/$RESTORE_HELPER_APP"

echo "Installing login restore LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nrime.inputmethod.loginrestore</string>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$RESTORE_HELPER_APP/Contents/MacOS/NRIMERestoreHelper</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH" 2>/dev/null || true

# Enable and select NRIME input source via TIS API
echo "Activating NRIME input source..."
swift -e '
import Carbon
import Foundation

let bundleId = "com.nrime.inputmethod.app" as CFString
let sourceId = "com.nrime.inputmethod.app.en" as CFString

// Get all input sources including non-enabled ones
let conditions = [
    kTISPropertyBundleID: bundleId
] as CFDictionary
guard let sources = TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource],
      !sources.isEmpty else {
    print("  Warning: NRIME input source not found. You may need to log out and log back in.")
    exit(0)
}

for source in sources {
    let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    guard let idRef = idRef else { continue }
    let id = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String

    // Enable it if not already enabled
    let enabledRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
    if let enabledRef = enabledRef {
        let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledRef).takeUnretainedValue()
        if !CFBooleanGetValue(enabled) {
            let status = TISEnableInputSource(source)
            if status == noErr {
                print("  Enabled: \(id)")
            }
        }
    }

    // Select the .en mode as active
    if id == sourceId as String {
        let status = TISSelectInputSource(source)
        if status == noErr {
            print("  Selected: \(id)")
        }
    }
}
' 2>&1 || true

# Ensure NRIME is in AppleEnabledInputSources (persists across reboots)
# Only register the .en mode — NRIME switches modes internally via a single input source.
echo "Ensuring NRIME is registered in enabled input sources..."
swift -e '
import Foundation

let domain = "com.apple.HIToolbox"
let key = "AppleEnabledInputSources"
let bundleId = "com.nrime.inputmethod.app"
let keepMode = "com.nrime.inputmethod.app.en"

guard var enabled = UserDefaults.standard.persistentDomain(forName: domain) else {
    print("  Warning: Could not read HIToolbox defaults")
    exit(0)
}

var sources = (enabled[key] as? [[String: Any]]) ?? []
var changed = false

// Remove stale .ko / .ja entries (they cause duplicate input sources in System Settings)
let before = sources.count
sources.removeAll { dict in
    guard (dict["Bundle ID"] as? String) == bundleId,
          let mode = dict["Input Mode"] as? String,
          mode != keepMode else { return false }
    print("  Removed stale: \(mode)")
    return true
}
if sources.count != before { changed = true }

// Add .en if missing
let hasEn = sources.contains { dict in
    (dict["Bundle ID"] as? String) == bundleId &&
    (dict["Input Mode"] as? String) == keepMode
}
if !hasEn {
    sources.append([
        "Bundle ID": bundleId,
        "Input Mode": keepMode,
        "InputSourceKind": "Input Mode"
    ])
    print("  Added: \(keepMode)")
    changed = true
}

if changed {
    enabled[key] = sources
    UserDefaults.standard.setPersistentDomain(enabled, forName: domain)
    UserDefaults.standard.synchronize()
    print("  Saved to defaults")
} else {
    print("  Already registered correctly")
}
' 2>&1 || true

echo ""
echo "Installation complete!"
echo "NRIME should now appear in your menu bar."
echo ""
echo "If NRIME does not appear, log out and log back in, then add it in:"
echo "  System Settings > Keyboard > Input Sources > Edit > + > NRIME"
echo ""
