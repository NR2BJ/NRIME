#!/bin/bash
# Build NRIME installer PKG
# Usage: bash Tools/build_pkg.sh
#
# Output: build/NRIME-<version>.pkg

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
PKG_DIR="$BUILD_DIR/pkg"
SCRIPTS_DIR="$PROJECT_DIR/Tools/pkg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/NRIME/Resources/Info.plist")

echo "=== NRIME PKG Builder (v$VERSION) ==="

# 1. Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"

# 2. Build Release
echo "Building NRIME (Release)..."
xcodebuild -project "$PROJECT_DIR/NRIME.xcodeproj" \
    -scheme NRIME -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build 2>&1 | grep -E "(BUILD|error:)" || true

echo "Building NRIMESettings (Release)..."
xcodebuild -project "$PROJECT_DIR/NRIME.xcodeproj" \
    -scheme NRIMESettings -configuration Release \
    SYMROOT="$BUILD_DIR" \
    build 2>&1 | grep -E "(BUILD|error:)" || true

# Verify build products exist
NRIME_APP="$BUILD_DIR/Release/NRIME.app"
SETTINGS_APP="$BUILD_DIR/Release/NRIMESettings.app"

if [ ! -d "$NRIME_APP" ]; then
    echo "ERROR: NRIME.app not found at $NRIME_APP"
    exit 1
fi

# 3. Prepare payload
echo "Preparing PKG payload..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/payload/Library/Input Methods"
mkdir -p "$PKG_DIR/scripts"

cp -R "$NRIME_APP" "$PKG_DIR/payload/Library/Input Methods/"
if [ -d "$SETTINGS_APP" ]; then
    cp -R "$SETTINGS_APP" "$PKG_DIR/payload/Library/Input Methods/"
fi

# Copy postinstall script
cp "$SCRIPTS_DIR/postinstall" "$PKG_DIR/scripts/postinstall"
chmod +x "$PKG_DIR/scripts/postinstall"

# 4. Build component PKG
echo "Building component package..."
pkgbuild \
    --root "$PKG_DIR/payload" \
    --scripts "$PKG_DIR/scripts" \
    --identifier "com.nrime.inputmethod.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_DIR/NRIME-component.pkg"

# 5. Build distribution PKG (final installer)
echo "Building distribution package..."
productbuild \
    --distribution "$SCRIPTS_DIR/distribution.xml" \
    --package-path "$PKG_DIR" \
    --resources "$SCRIPTS_DIR" \
    "$BUILD_DIR/NRIME-$VERSION.pkg"

# Cleanup intermediate files
rm -rf "$PKG_DIR"

echo ""
echo "=== Done ==="
echo "Installer: $BUILD_DIR/NRIME-$VERSION.pkg"
echo "Size: $(du -h "$BUILD_DIR/NRIME-$VERSION.pkg" | cut -f1)"
