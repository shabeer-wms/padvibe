# Quick Fix: Production Build Closing on Other Mac

## TL;DR
The sidecar binary wasn't signed and lacked proper logging. I've added comprehensive logging and automatic code signing.

## What to Do Now

### 1. Rebuild (on your Mac)
```bash
./sidecar/build_sidecar.sh  # Rebuilds and signs the binary
flutter clean
flutter build macos --release
```

### 2. Transfer to Other Mac
Copy `build/macos/Build/Products/Release/padvibe.app` to the other Mac's `/Applications/` folder

### 3. First Run
**Right-click** padvibe.app → **Open** (important!)

### 4. If It Still Closes
```bash
# View the log:
cat ~/Library/Application\ Support/com.example.padvibe/logs/sidecar_*.log

# Send me the log file - it will show exactly what failed
```

### 5. Quick Test
```bash
# Test the sidecar manually:
cd /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/
chmod +x midi_server
./midi_server

# Should see: "WebSocket server started on ws://127.0.0.1:8765"
```

## What Changed
✅ Added file-based logging to `~/Library/Application Support/com.example.padvibe/logs/`
✅ Binary is now code-signed automatically
✅ Added permission checks and verification
✅ Better error messages with log paths
✅ Added JIT and library validation entitlements

## Common Issues

**"Cannot be opened because the developer cannot be verified"**
```bash
xattr -d com.apple.quarantine /Applications/padvibe.app
```

**App closes silently**
→ Check the log file (step 4 above)

**"Bad CPU type"**
→ Architecture mismatch. Check: `uname -m` (should be x86_64 on both Macs)

## Full Documentation
- `TESTING_ON_OTHER_MAC.md` - Detailed testing guide
- `DEBUG_GUIDE.md` - Comprehensive debugging commands
- `CHANGES_SUMMARY.md` - All technical changes

## Contact Points
When testing on the other Mac, send me:
1. Log file from `~/Library/Application Support/com.example.padvibe/logs/`
2. Output from manually running the sidecar (step 5)
3. `sw_vers` and `uname -m` output
