#!/usr/bin/env bash
# Copies the built sidecar into a macOS .app and re-signs the app (ad-hoc).
# Usage: scripts/bundle_sidecar_macos.sh path/to/padvibe.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: bundle_sidecar_macos.sh path/to/App.app}"
SRC="sidecar/dist/midi_server"
DEST="$APP/Contents/Resources/sidecar"

[ -x "$SRC/midi_server" ] || { echo "Missing $SRC/midi_server - run sidecar/build_sidecar.sh first" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"

# Re-sign after adding files. The entitlements must be passed again: signing
# without them silently drops them, and the file picker then fails with
# ENTITLEMENT_NOT_FOUND. Nested frameworks keep the signatures Flutter gave them.
# codesign's parser rejects "<false />" in the project's plist; plutil rewrites it canonically.
ENTITLEMENTS="$(mktemp -t padvibe-entitlements).plist"
plutil -convert xml1 -o "$ENTITLEMENTS" macos/Runner/Release.entitlements
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"
codesign --verify --deep --strict "$APP"

# Fail the build if the entitlement the file picker needs is missing.
codesign -d --entitlements - "$APP" 2>&1 | grep -q "files.user-selected" \
  || { echo "ERROR: $APP lost its file-access entitlement after signing" >&2; exit 1; }
echo "Sidecar bundled into $APP ($(lipo -archs "$DEST/midi_server"))"
