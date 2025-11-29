#!/bin/bash

# Install PyInstaller if not present
if ! command -v pyinstaller &> /dev/null; then
    echo "PyInstaller not found. Installing..."
    pip3 install pyinstaller
fi

# Install requirements
echo "Installing requirements..."
pip3 install -r sidecar/requirements.txt

# Build the sidecar
echo "Building sidecar binary..."
# --onefile: Create a single executable
# --noconsole: Don't show a console window (optional, maybe good for debugging to keep it for now, but for prod we might want it hidden. Let's keep console for now to see logs in Flutter)
# --distpath: Output directory
# --name: Name of the executable
pyinstaller --onefile --distpath sidecar/dist --name midi_server --hidden-import='mido.backends.rtmidi' sidecar/midi_server.py

echo "Build complete. Binary is at sidecar/dist/midi_server"
