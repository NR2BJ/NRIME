#!/bin/bash
# NRIME Install Script
# Builds and installs NRIME input method to user-level Input Methods directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/Debug"
INSTALL_DIR="$HOME/Library/Input Methods"
APP_NAME="NRIME.app"

echo "=== NRIME Installer ==="

# Always build fresh to avoid stale cache issues
echo "Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "Building NRIME..."
xcodebuild -project NRIME.xcodeproj -scheme NRIME -configuration Debug \
    SYMROOT="$PROJECT_DIR/build" build 2>&1 | tail -3

echo "Building NRIMESettings..."
xcodebuild -project NRIME.xcodeproj -scheme NRIMESettings -configuration Debug \
    SYMROOT="$PROJECT_DIR/build" build 2>&1 | tail -3

# Install FIRST (before kill, so macOS restarts with the NEW binary)
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$BUILD_DIR/$APP_NAME" "$INSTALL_DIR/"

# Install companion app next to input method
SETTINGS_APP="NRIMESettings.app"
rm -rf "$INSTALL_DIR/$SETTINGS_APP"
cp -R "$BUILD_DIR/$SETTINGS_APP" "$INSTALL_DIR/"

# Ensure mozc_server has execute permissions
chmod +x "$INSTALL_DIR/$APP_NAME/Contents/Resources/mozc_server" 2>/dev/null || true

# Kill AFTER install — macOS auto-restarts the IME with the new binary
echo "Restarting NRIME process..."
killall NRIME 2>/dev/null || true
sleep 1

# Register with LaunchServices (ensures macOS knows about the new location)
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
echo "Registering with LaunchServices..."
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME"

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

echo ""
echo "Installation complete!"
echo "NRIME should now appear in your menu bar."
echo ""
echo "If NRIME does not appear, log out and log back in, then add it in:"
echo "  System Settings > Keyboard > Input Sources > Edit > + > NRIME"
echo ""
