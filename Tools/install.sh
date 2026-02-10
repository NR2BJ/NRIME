#!/bin/bash
# NRIME Install Script
# Installs NRIME input method to user-level Input Methods directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/Debug"
INSTALL_DIR="$HOME/Library/Input Methods"
APP_NAME="NRIME.app"

echo "=== NRIME Installer ==="

# Build if needed
if [ ! -d "$BUILD_DIR/$APP_NAME" ]; then
    echo "Building NRIME..."
    cd "$PROJECT_DIR"
    xcodebuild -project NRIME.xcodeproj -target NRIME -configuration Debug build
fi

# Kill existing process
echo "Stopping existing NRIME process..."
killall NRIME 2>/dev/null || true
sleep 1

# Install
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$BUILD_DIR/$APP_NAME" "$INSTALL_DIR/"

echo ""
echo "Installation complete!"
echo "Please log out and log back in, then add NRIME in:"
echo "  System Settings > Keyboard > Input Sources > Edit > + > NRIME"
echo ""
