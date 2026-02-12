# Testing PadVibe on Another Mac

## What Changed

I've added comprehensive logging and debugging features to help identify why the app closes on the other Mac:

1. **File-based logging** - All sidecar startup activities are logged to disk
2. **Better error messages** - Detailed error messages with log file paths
3. **Code signature verification** - Checks if the binary is properly signed
4. **Permission checks** - Verifies file permissions before execution
5. **Improved entitlements** - Added `com.apple.security.cs.disable-library-validation` and `com.apple.security.cs.allow-jit`

## Steps to Test on the Other Mac

### 1. Build a Fresh Release

On **your development Mac**, build a new release:

```bash
# Clean previous builds
flutter clean

# Rebuild the sidecar with code signing
./sidecar/build_sidecar.sh

# Build the macOS app
flutter build macos --release

# The app will be at: build/macos/Build/Products/Release/padvibe.app
```

### 2. Transfer to Other Mac

Copy the entire `padvibe.app` to the other Mac:

```bash
# Option 1: Using USB drive
# Copy build/macos/Build/Products/Release/padvibe.app to USB

# Option 2: Using AirDrop
# Right-click the padvibe.app and select "Share > AirDrop"

# Option 3: Using scp (if you know the other Mac's IP)
scp -r build/macos/Build/Products/Release/padvibe.app username@other-mac-ip:~/Desktop/
```

### 3. First Run on Other Mac

1. Copy `padvibe.app` to `/Applications/`
2. **Right-click** on `padvibe.app` and select **"Open"** (important for Gatekeeper)
3. If prompted about "unidentified developer", click **"Open"**

### 4. Check the Logs

If the app closes immediately, the logs will tell us why:

```bash
# Open the log directory
open ~/Library/Application\ Support/com.example.padvibe/logs/

# Or view the latest log:
cat ~/Library/Application\ Support/com.example.padvibe/logs/sidecar_*.log
```

The log will contain:
- Platform and OS version
- All paths checked for the sidecar binary
- Whether the binary was found
- File permissions
- Code signature verification results
- Any errors from starting the sidecar process
- All stdout/stderr from the Python sidecar

### 5. Manual Testing

If the app still doesn't start, test the sidecar manually:

```bash
# Navigate to the sidecar location
cd /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/

# Check if binary exists
ls -la midi_server

# Check permissions (should have 'x')
ls -l midi_server

# Make it executable if needed
chmod +x midi_server

# Try running it directly
./midi_server
```

If it runs successfully, you should see:
```
WebSocket server started on ws://127.0.0.1:8765
Audio engine initialized
MIDI engine started
```

If you see an error, that's the problem we need to fix!

### 6. Common Issues and Solutions

#### Issue: "cannot be opened because the developer cannot be verified"

**Solution:**
```bash
# Remove quarantine attribute
xattr -d com.apple.quarantine /Applications/padvibe.app

# Or for just the binary:
xattr -d com.apple.quarantine /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server
```

#### Issue: "Bad CPU type in executable"

This means architecture mismatch. Check:
```bash
# Check the other Mac's architecture
uname -m

# Check the binary architecture
lipo -info /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server
```

If the other Mac is Intel (x86_64), the binary should work.
If the other Mac is ARM (arm64), we need to rebuild on an ARM Mac.

#### Issue: "dyld: Library not loaded"

The binary is missing a system library. Check:
```bash
otool -L /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server
```

#### Issue: Binary not found

Check these locations:
```bash
# Location 1
ls /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server

# Location 2
ls /Applications/padvibe.app/Contents/Frameworks/App.framework/Versions/Current/Resources/flutter_assets/sidecar/dist/midi_server

# Location 3
ls /Applications/padvibe.app/Contents/Resources/flutter_assets/sidecar/dist/midi_server
```

### 7. Check Console for System-Level Errors

On the other Mac:
1. Open **Console.app** (Applications > Utilities > Console)
2. Click **Start** in the toolbar
3. Run PadVibe
4. Look for errors containing "padvibe" or "midi_server"
5. Check for security-related messages from `com.apple.security.syspolicy`

### 8. Report Back

Send me:
1. The contents of the log file: `~/Library/Application Support/com.example.padvibe/logs/sidecar_*.log`
2. The output from running the sidecar manually (step 5)
3. The macOS version: `sw_vers`
4. The architecture: `uname -m`
5. Any error messages from Console.app

This information will help us identify and fix the exact issue!

## Additional Debug Commands

```bash
# Check if port 8765 is already in use
lsof -i :8765

# Check if Python 3 is available (fallback mode)
which python3
python3 --version

# Check system logs for crashes
log show --predicate 'process == "padvibe"' --last 5m

# Check for security violations
log show --predicate 'subsystem == "com.apple.security.syspolicy"' --last 5m | grep padvibe
```

## If All Else Fails: Python Fallback

If the binary doesn't work, install Python and dependencies on the other Mac:

```bash
# Install Python 3
# Download from https://www.python.org/downloads/

# Install dependencies
pip3 install mido python-rtmidi websockets sounddevice soundfile numpy

# The app will automatically fall back to using the Python script
```
