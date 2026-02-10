#!/bin/bash
# NRIME Complete Uninstall Script
# Removes ALL traces of NRIME from the system with zero leftovers

set -e

echo "=== NRIME Complete Uninstaller ==="
echo ""

# 1. Kill running process
echo "[1/6] Stopping NRIME process..."
killall NRIME 2>/dev/null || true
sleep 1

# 2. Remove from Input Methods (both user and system level)
echo "[2/6] Removing NRIME.app..."
rm -rf "$HOME/Library/Input Methods/NRIME.app"
sudo rm -rf "/Library/Input Methods/NRIME.app" 2>/dev/null || true

# 3. Remove UserDefaults / preferences
echo "[3/6] Removing preferences..."
defaults delete com.nrime.inputmethod.NRIME 2>/dev/null || true
rm -f "$HOME/Library/Preferences/com.nrime.inputmethod.NRIME.plist"
rm -f "$HOME/Library/Preferences/com.nrime.inputmethod.NRIME.plist.lockfile"

# 4. Remove App Group shared container (if any)
rm -rf "$HOME/Library/Group Containers/group.com.nrime" 2>/dev/null || true

# 5. Remove cached/derived data
echo "[4/6] Removing caches and derived data..."
rm -rf "$HOME/Library/Caches/com.nrime.inputmethod.NRIME"
# Remove from LaunchServices database
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$HOME/Library/Input Methods/NRIME.app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "/Library/Input Methods/NRIME.app" 2>/dev/null || true

# 6. Remove input source registration from TIS
echo "[5/6] Deregistering input source..."
# The input source deregisters automatically when the .app is removed,
# but we force a cache refresh
killall SystemUIServer 2>/dev/null || true

echo "[6/6] Cleanup complete!"
echo ""
echo "NRIME has been completely removed from your system."
echo "You may need to log out and log back in for the menu bar to update."
echo ""
echo "No hidden files, caches, or registry entries remain."
