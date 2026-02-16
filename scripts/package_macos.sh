#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting PadVibe macOS Packaging Process..."

# 1. Build Sidecar
echo "🏗️ Building Python Sidecar..."
./sidecar/build_sidecar.sh

# 2. Build Flutter App
echo "🏗️ Building Flutter macOS App (Release)..."
fvm flutter build macos --release

# 3. Identify the built app
APP_PATH=$(find build/macos/Build/Products/Release -name "*.app" -maxdepth 1)
APP_NAME=$(basename "$APP_PATH")

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: Could not find the built .app file."
    exit 1
fi

echo "✅ Found built app: $APP_NAME at $APP_PATH"

# 4. Define Version
VERSION=$(grep 'version: ' pubspec.yaml | sed 's/version: //')
CLEAN_VERSION=$(echo $VERSION | cut -d'+' -f1)

DMG_NAME="PadVibe-${CLEAN_VERSION}-Installer.dmg"
OUTPUT_DIR="build/macos/installer"
mkdir -p "$OUTPUT_DIR"

# 5. Package as DMG
echo "📦 Packaging into DMG: $DMG_NAME..."

# Create a temporary staging directory
STAGING_DIR="build/macos/staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "$APP_PATH" "$STAGING_DIR/"

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "⚠️ create-dmg not found. Falling back to simple hdiutil disk image."
    hdiutil create -volname "PadVibe" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME"
else
    # Remove existing DMG if it exists
    rm -f "$OUTPUT_DIR/$DMG_NAME"
    
    create-dmg \
      --volname "PadVibe Installer" \
      --volicon "assets/logo/512-mac.png" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "$APP_NAME" 150 190 \
      --hide-extension "$APP_NAME" \
      --app-drop-link 450 185 \
      "$OUTPUT_DIR/$DMG_NAME" \
      "$STAGING_DIR"
fi

# Cleanup staging
rm -rf "$STAGING_DIR"

echo "--------------------------------------------------"
echo "✅ SUCCESS! Installer created at:"
echo "$OUTPUT_DIR/$DMG_NAME"
echo "--------------------------------------------------"
