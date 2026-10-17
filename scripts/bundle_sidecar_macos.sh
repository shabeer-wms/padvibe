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

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Sidecar bundled into $APP ($(lipo -archs "$DEST/midi_server"))"
