# Debugging PadVibe Production Build Issues

## Common Issues on Other Macs

### 1. Check if the app is being blocked by Gatekeeper

Open Terminal on the **other Mac** and run:

```bash
# Check system logs for security blocks
log show --predicate 'subsystem == "com.apple.security.syspolicy"' --last 5m | grep -i padvibe

# Or check Console.app:
# Applications > Utilities > Console.app
# Search for "padvibe" or "midi_server"
```

### 2. Code Sign the Sidecar Binary

The PyInstaller binary might not be signed. On **your development Mac**, run:

```bash
# Check if binary is signed
codesign -dv sidecar/dist/midi_server

# If not signed, sign it:
codesign --force --deep --sign - sidecar/dist/midi_server

# Verify:
codesign --verify --verbose sidecar/dist/midi_server
```

### 3. Check Binary Permissions

On the **other Mac**, check if the binary has execute permissions:

```bash
# Navigate to the app bundle
cd /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/

# Check permissions
ls -la midi_server

# If not executable, make it executable:
chmod +x midi_server

# Try running it manually:
./midi_server
```

### 4. Check for Missing Dependencies

```bash
# Check what libraries the binary needs:
otool -L /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server

# Check if PortAudio is available (needed for sounddevice):
ls /usr/local/lib/libportaudio*
```

### 5. View App Logs

On the **other Mac**, check crash reports:

```bash
# Check crash logs
open ~/Library/Logs/DiagnosticReports/

# Or use Console.app to see live logs:
# Open Console.app
# Select your Mac under Devices
# Click "Start" and run PadVibe
# Look for errors with "padvibe" or "midi_server"
```

### 6. Test Sidecar Manually

On the **other Mac**, try running the sidecar manually:

```bash
# Extract the binary from the app bundle
cd /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/

# Make it executable
chmod +x midi_server

# Run it
./midi_server

# You should see output about WebSocket server starting on port 8765
# If you see errors, that's the issue!
```

### 7. Check macOS Version Compatibility

```bash
# Check macOS version on the other Mac:
sw_vers

# The binary was built on your Mac's OS version
# If the other Mac has an older macOS, there might be compatibility issues
```

## Solutions

### Solution 1: Ad-hoc Sign the Binary

```bash
codesign --force --deep --sign - sidecar/dist/midi_server
```

Then rebuild the Flutter app:
```bash
flutter clean
flutter build macos --release
```

### Solution 2: Disable Library Validation (Development Only)

Add to `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

### Solution 3: Use Universal Binary

Build the sidecar on both Intel and ARM, then combine:

```bash
# Build on Intel Mac
pyinstaller --onefile --distpath sidecar/dist/intel --name midi_server sidecar/midi_server.py

# Build on ARM Mac  
pyinstaller --onefile --distpath sidecar/dist/arm --name midi_server sidecar/midi_server.py

# Create universal binary
lipo -create sidecar/dist/intel/midi_server sidecar/dist/arm/midi_server -output sidecar/dist/midi_server
```

### Solution 4: Fall Back to Python Script

If the binary fails, the app tries to run the Python script. Ensure Python 3 is installed on the other Mac:

```bash
# Check Python installation
which python3
python3 --version

# Install dependencies
pip3 install -r sidecar/requirements.txt
```
