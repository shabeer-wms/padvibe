#!/usr/bin/env bash
# Builds the Python sidecar as a one-dir PyInstaller bundle at sidecar/dist/midi_server/.
# Works on macOS, Linux and Windows (Git Bash). Override the interpreter with PYTHON=...
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3}"

echo "Installing build requirements..."
"$PYTHON" -m pip install --quiet pyinstaller -r sidecar/requirements.txt

echo "Building sidecar (one-dir)..."
rm -rf sidecar/dist build/sidecar
"$PYTHON" -m PyInstaller --noconfirm --distpath sidecar/dist --workpath build/sidecar sidecar/midi_server.spec

echo "Build complete. Bundle is at sidecar/dist/midi_server/"
