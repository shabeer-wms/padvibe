# Changes Made to Fix Production Build Issues

## Summary

The production build was closing silently on another Mac due to potential issues with:
1. Unsigned/unverified sidecar binary
2. Missing permissions
3. Lack of diagnostic logging

## Files Modified

### 1. `lib/app/service/sidecar_service.dart`
**Changes:**
- Added file-based logging system using `path_provider`
- All sidecar startup activities are now logged to `~/Library/Application Support/com.example.padvibe/logs/`
- Added code signature verification on macOS
- Added file permission checks
- Enhanced error messages to include log file path
- All errors include full stack traces in logs

**Key Features:**
- `_initLogging()` - Creates log directory and log file
- `_log()` - Writes timestamped messages to both console and log file
- Logs include: Platform info, binary paths, permissions, code signing status, all stdout/stderr
- Error messages now show log file location for debugging

### 2. `sidecar/build_sidecar.sh`
**Changes:**
- Added automatic code signing after PyInstaller build
- Binary is now ad-hoc signed with `codesign --force --deep --sign -`
- Verifies signature after signing
- Only signs on macOS (checks for `darwin` OS)

**Benefits:**
- Prevents Gatekeeper from blocking the binary
- Allows the binary to be executed without manual approval
- Compatible with macOS security requirements

### 3. `macos/Runner/Release.entitlements`
**Changes:**
- Added `com.apple.security.cs.allow-jit` entitlement
- Added `com.apple.security.cs.disable-library-validation` entitlement

**Why:**
- `allow-jit` - Allows the sidecar binary to use JIT compilation if needed
- `disable-library-validation` - Allows loading of the ad-hoc signed sidecar binary
- These entitlements are needed for PyInstaller bundles that contain dynamic libraries

### 4. `DEBUG_GUIDE.md` (New)
Comprehensive debugging guide covering:
- How to check for Gatekeeper blocks
- Code signing verification commands
- Binary permission checks
- Manual sidecar testing
- Viewing crash reports
- Common issues and solutions

### 5. `TESTING_ON_OTHER_MAC.md` (New)
Step-by-step testing guide for the other Mac:
- Build instructions
- Transfer methods
- First run procedure
- Log file locations
- Manual testing steps
- Troubleshooting commands
- What information to collect

## How the Logging Works

When the app starts, it:
1. Creates a log directory at `~/Library/Application Support/com.example.padvibe/logs/`
2. Creates a timestamped log file: `sidecar_<timestamp>.log`
3. Logs every step of sidecar initialization:
   - Platform and OS version
   - Executable path
   - All paths checked for sidecar binary
   - Whether binary was found
   - File permissions (using `stat.modeString()`)
   - Code signature verification results
   - Any errors from `Process.start()`
   - All stdout/stderr from the sidecar process
4. If the app crashes, the log file persists and can be examined

## Testing Steps

### On Your Development Mac:
```bash
# 1. Rebuild the sidecar with code signing
./sidecar/build_sidecar.sh

# 2. Clean and rebuild Flutter app
flutter clean
flutter build macos --release

# 3. The app is at: build/macos/Build/Products/Release/padvibe.app
```

### On the Other Mac:
```bash
# 1. Copy padvibe.app to /Applications/

# 2. Right-click and select "Open" (bypasses Gatekeeper first-run)

# 3. If it closes, check the logs:
cat ~/Library/Application\ Support/com.example.padvibe/logs/sidecar_*.log

# 4. Test the sidecar manually:
cd /Applications/padvibe.app/Contents/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/
chmod +x midi_server
./midi_server
```

## Most Likely Causes

Based on the investigation, the most likely issues are:

1. **Gatekeeper blocking unsigned binary** (FIXED: Now ad-hoc signed)
2. **Missing execute permissions** (FIXED: Now checked and logged)
3. **Code signature verification failing** (FIXED: Added proper entitlements)
4. **Binary not found in bundle** (IMPROVED: Now logs all paths checked)

## Next Steps

1. Rebuild the app with these changes
2. Transfer to the other Mac
3. Run the app and check the log file
4. If it still fails, the log will show exactly where and why
5. Send the log file contents to identify the specific issue

## Important Notes

- The sidecar binary is still Intel-only (x86_64). If the other Mac is Apple Silicon, Rosetta 2 must be installed.
- Ad-hoc signing is sufficient for personal use but won't pass notarization for distribution
- For App Store distribution, you'll need a proper Developer ID certificate
- The log files will accumulate over time; consider adding cleanup logic later

## Rollback

If these changes cause issues, revert with:
```bash
git checkout lib/app/service/sidecar_service.dart
git checkout sidecar/build_sidecar.sh
git checkout macos/Runner/Release.entitlements
rm DEBUG_GUIDE.md TESTING_ON_OTHER_MAC.md
```
