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

# Use PyInstaller's own target-arch if supported, otherwise build native
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Clean old builds
    rm -rf sidecar/dist build/midi_server
    
    # Just build native for now to ensure a working binary
    echo "Building native binary..."
    pyinstaller --onefile --distpath sidecar/dist --name midi_server --hidden-import='mido.backends.rtmidi' sidecar/midi_server.py
    
    echo "Signing binary..."
    codesign --force --deep --sign - sidecar/dist/midi_server
    codesign --verify --verbose sidecar/dist/midi_server
else
    # Non-macOS build
    pyinstaller --onefile --distpath sidecar/dist --name midi_server --hidden-import='mido.backends.rtmidi' sidecar/midi_server.py
fi

echo "Build complete. Binary is at sidecar/dist/midi_server"
