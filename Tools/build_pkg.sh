#!/bin/bash
# Build NRIME installer PKG
# Usage: bash Tools/build_pkg.sh
#
# Output: build/NRIME-<version>.pkg

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
PKG_DIR="$BUILD_DIR/pkg"
SCRIPTS_DIR="$PROJECT_DIR/Tools/pkg"
VERSION=""

echo "=== NRIME PKG Builder ==="

# 1. Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"

# 2. Build Release
echo "Building NRIME (Release)..."
xcodebuild -project "$PROJECT_DIR/NRIME.xcodeproj" \
    -scheme NRIME -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build

echo "Building NRIMESettings (Release)..."
xcodebuild -project "$PROJECT_DIR/NRIME.xcodeproj" \
    -scheme NRIMESettings -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build

echo "Building NRIMERestoreHelper (Release)..."
xcodebuild -project "$PROJECT_DIR/NRIME.xcodeproj" \
    -scheme NRIMERestoreHelper -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build

# Verify build products exist
NRIME_APP="$BUILD_DIR/Release/NRIME.app"
SETTINGS_APP="$BUILD_DIR/Release/NRIMESettings.app"
RESTORE_HELPER_APP="$BUILD_DIR/Release/NRIMERestoreHelper.app"
LAUNCH_AGENT_PLIST="$SCRIPTS_DIR/com.nrime.inputmethod.loginrestore.plist"
MOZC_LAUNCH_AGENT_PLIST="$SCRIPTS_DIR/com.nrime.inputmethod.mozcserver.plist"

if [ ! -d "$NRIME_APP" ]; then
    echo "ERROR: NRIME.app not found at $NRIME_APP"
    exit 1
fi

if [ ! -d "$RESTORE_HELPER_APP" ]; then
    echo "ERROR: NRIMERestoreHelper.app not found at $RESTORE_HELPER_APP"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NRIME_APP/Contents/Info.plist")
echo "Resolved app version: $VERSION"

# 3. Prepare payload
echo "Preparing PKG payload..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/payload/Library/Input Methods"
mkdir -p "$PKG_DIR/payload/Library/LaunchAgents"
mkdir -p "$PKG_DIR/scripts"

# Use ditto to avoid ._* resource fork files in payload
ditto "$NRIME_APP" "$PKG_DIR/payload/Library/Input Methods/NRIME.app"
if [ -d "$SETTINGS_APP" ]; then
    ditto "$SETTINGS_APP" "$PKG_DIR/payload/Library/Input Methods/NRIMESettings.app"
fi
ditto "$RESTORE_HELPER_APP" "$PKG_DIR/payload/Library/Input Methods/NRIMERestoreHelper.app"
cp "$LAUNCH_AGENT_PLIST" "$PKG_DIR/payload/Library/LaunchAgents/com.nrime.inputmethod.loginrestore.plist"
cp "$MOZC_LAUNCH_AGENT_PLIST" "$PKG_DIR/payload/Library/LaunchAgents/com.nrime.inputmethod.mozcserver.plist"

# Ad-hoc code sign (inside-out to avoid broken nested signatures)
echo "Ad-hoc signing apps..."
find "$PKG_DIR/payload" -name "*.bundle" -exec codesign -s - --force {} \;
codesign -s - --force "$PKG_DIR/payload/Library/Input Methods/NRIME.app"
codesign -s - --force "$PKG_DIR/payload/Library/Input Methods/NRIMESettings.app" 2>/dev/null || true
codesign -s - --force "$PKG_DIR/payload/Library/Input Methods/NRIMERestoreHelper.app"
echo "Verifying signatures..."
codesign -v "$PKG_DIR/payload/Library/Input Methods/NRIME.app" && echo "  NRIME.app: OK" || echo "  NRIME.app: FAILED"
codesign -v "$PKG_DIR/payload/Library/Input Methods/NRIMESettings.app" && echo "  NRIMESettings.app: OK" || echo "  NRIMESettings.app: FAILED"
codesign -v "$PKG_DIR/payload/Library/Input Methods/NRIMERestoreHelper.app" && echo "  NRIMERestoreHelper.app: OK" || echo "  NRIMERestoreHelper.app: FAILED"

# Copy postinstall script
cp "$SCRIPTS_DIR/postinstall" "$PKG_DIR/scripts/postinstall"
chmod +x "$PKG_DIR/scripts/postinstall"

# 4. Generate component plist and disable relocation
#    Without this, the installer searches the entire filesystem for existing
#    copies of the bundles, triggering TCC prompts (e.g., Documents folder access).
echo "Generating component plist..."
pkgbuild --analyze --root "$PKG_DIR/payload" "$PKG_DIR/component.plist"
# Set BundleIsRelocatable=false for all components
/usr/libexec/PlistBuddy -c "Print" "$PKG_DIR/component.plist" > /dev/null 2>&1
INDEX=0
while /usr/libexec/PlistBuddy -c "Print :${INDEX}:BundleIsRelocatable" "$PKG_DIR/component.plist" > /dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Set :${INDEX}:BundleIsRelocatable false" "$PKG_DIR/component.plist"
    INDEX=$((INDEX + 1))
done
echo "  Disabled relocation for $INDEX components"

# 5. Build component PKG
echo "Building component package..."
pkgbuild \
    --root "$PKG_DIR/payload" \
    --scripts "$PKG_DIR/scripts" \
    --component-plist "$PKG_DIR/component.plist" \
    --identifier "com.nrime.inputmethod.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_DIR/NRIME-component.pkg"

# 6. Build distribution PKG (final installer)
echo "Building distribution package..."
sed "s/__VERSION__/$VERSION/g" "$SCRIPTS_DIR/distribution.xml" > "$PKG_DIR/distribution.xml"
productbuild \
    --distribution "$PKG_DIR/distribution.xml" \
    --package-path "$PKG_DIR" \
    "$BUILD_DIR/NRIME-$VERSION.pkg"

# Cleanup intermediate files
rm -rf "$PKG_DIR"

echo ""
echo "=== Done ==="
echo "Installer: $BUILD_DIR/NRIME-$VERSION.pkg"
echo "Size: $(du -h "$BUILD_DIR/NRIME-$VERSION.pkg" | cut -f1)"
