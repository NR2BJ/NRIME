#!/bin/bash
# NRIME Complete Uninstaller
# Removes ALL traces of NRIME from the system

set -e

echo "=== NRIME Complete Uninstaller ==="
echo ""

# 1. Kill running processes
echo "[1/7] Stopping processes..."
killall NRIME 2>/dev/null || true
killall NRIMESettings 2>/dev/null || true
killall NRIMERestoreHelper 2>/dev/null || true
killall mozc_server 2>/dev/null || true
sleep 1

# 2. Remove apps (user-level and system-level)
echo "[2/7] Removing NRIME apps..."
rm -rf "$HOME/Library/Input Methods/NRIME.app"
rm -rf "$HOME/Library/Input Methods/NRIMESettings.app"
rm -rf "$HOME/Library/Input Methods/NRIMERestoreHelper.app"
sudo rm -rf "/Library/Input Methods/NRIME.app" 2>/dev/null || true
sudo rm -rf "/Library/Input Methods/NRIMESettings.app" 2>/dev/null || true
sudo rm -rf "/Library/Input Methods/NRIMERestoreHelper.app" 2>/dev/null || true

# 3. Remove all preferences and UserDefaults
echo "[3/7] Removing preferences..."
defaults delete com.nrime.inputmethod.app 2>/dev/null || true
defaults delete com.nrime.settings 2>/dev/null || true
defaults delete group.com.nrime.inputmethod 2>/dev/null || true
rm -f "$HOME/Library/Preferences/com.nrime.inputmethod.app.plist"
rm -f "$HOME/Library/Preferences/com.nrime.inputmethod.app.plist.lockfile"
rm -f "$HOME/Library/Preferences/com.nrime.settings.plist"
rm -f "$HOME/Library/Preferences/com.nrime.settings.plist.lockfile"
rm -f "$HOME/Library/Preferences/group.com.nrime.inputmethod.plist"
rm -f "$HOME/Library/Preferences/group.com.nrime.inputmethod.plist.lockfile"

# 4. Remove Mozc engine data and NRIME logs
echo "[4/7] Removing Mozc data and logs..."
rm -rf "$HOME/Library/Application Support/Mozc"
rm -rf "$HOME/Library/Application Support/NRIME"

# 5. Remove caches and containers
echo "[5/7] Removing caches..."
rm -rf "$HOME/Library/Caches/com.nrime.inputmethod.app"
rm -rf "$HOME/Library/Caches/com.nrime.settings"
rm -rf "$HOME/Library/Group Containers/group.com.nrime" 2>/dev/null || true

# 6. Unregister from LaunchServices
echo "[6/7] Unregistering from LaunchServices..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -u "$HOME/Library/Input Methods/NRIME.app" 2>/dev/null || true
"$LSREGISTER" -u "$HOME/Library/Input Methods/NRIMESettings.app" 2>/dev/null || true
"$LSREGISTER" -u "$HOME/Library/Input Methods/NRIMERestoreHelper.app" 2>/dev/null || true
"$LSREGISTER" -u "/Library/Input Methods/NRIME.app" 2>/dev/null || true
"$LSREGISTER" -u "/Library/Input Methods/NRIMESettings.app" 2>/dev/null || true
"$LSREGISTER" -u "/Library/Input Methods/NRIMERestoreHelper.app" 2>/dev/null || true

LAUNCH_AGENT_LABEL="com.nrime.inputmethod.loginrestore"
LAUNCH_AGENT_USER="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
LAUNCH_AGENT_SYSTEM="/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_USER" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_USER"
sudo launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_SYSTEM" 2>/dev/null || true
sudo rm -f "$LAUNCH_AGENT_SYSTEM"

MOZC_LAUNCH_AGENT_LABEL="com.nrime.inputmethod.mozcserver"
MOZC_LAUNCH_AGENT_USER="$HOME/Library/LaunchAgents/$MOZC_LAUNCH_AGENT_LABEL.plist"
MOZC_LAUNCH_AGENT_SYSTEM="/Library/LaunchAgents/$MOZC_LAUNCH_AGENT_LABEL.plist"
launchctl bootout "gui/$(id -u)" "$MOZC_LAUNCH_AGENT_USER" 2>/dev/null || true
rm -f "$MOZC_LAUNCH_AGENT_USER"
sudo launchctl bootout "gui/$(id -u)" "$MOZC_LAUNCH_AGENT_SYSTEM" 2>/dev/null || true
sudo rm -f "$MOZC_LAUNCH_AGENT_SYSTEM"

# 7. Remove NRIME from AppleEnabledInputSources
echo "[7/7] Removing input source registration..."
swift -e '
import Foundation

let domain = "com.apple.HIToolbox"
let key = "AppleEnabledInputSources"

guard var enabled = UserDefaults.standard.persistentDomain(forName: domain) else { exit(0) }
guard var sources = enabled[key] as? [[String: Any]] else { exit(0) }

let before = sources.count
sources.removeAll { dict in
    (dict["Bundle ID"] as? String) == "com.nrime.inputmethod.app"
}

if sources.count != before {
    enabled[key] = sources
    UserDefaults.standard.setPersistentDomain(enabled, forName: domain)
    UserDefaults.standard.synchronize()
}
' 2>&1 || true

# Refresh menu bar
killall SystemUIServer 2>/dev/null || true

echo ""
echo "=== NRIME has been completely removed ==="
echo "Log out and log back in for the menu bar to fully update."
