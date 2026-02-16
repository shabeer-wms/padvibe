# Changes Summary & Version History

## [v1.7.0] - 2026-02-17
### Added
- **Dark Mode Support:** Modern Material 3 themes with system, light, and dark mode toggles in Settings.
- **Visual Loading Indicators:** Real-time feedback via circular progress indicators on pads during file loading, importing, and waveform generation.
- **Improved Pause/Resume:** Reliable playback resumption from the exact paused position across all audio files.
### Fixed
- **Audio Engine Latency:** Optimized sidecar event loop with non-blocking threaded operations for file loading and stream management.
- **Startup Clicks:** Added a 10ms soft fade-in to every playback to eliminate audible DC offset pops/clicks.
- **Tab Switching Stability:** Implemented state synchronization to prevent race conditions when rapid-switching between pad groups.
- **Hardware Query Cache:** Drastically reduced delay when starting playback by caching audio device hardware information.

## [v1.6.3] - 2026-02-16
### Fixed
- **Audio Engine Stability:** Removed unstable PortAudio re-initialization calls that caused hangs on some macOS machines.
- **Spectrum/Progress Bars:** Fixed a bug where background pads wouldn't animate their progress due to the UI being tied strictly to the master timer.
### Added
- **Deep Logging:** Added WebSocket communication logging to the sidecar log file to help diagnose playback issues on remote machines.

## [v1.6.2] - 2026-02-16
### Added
- **Dynamic Port Discovery:** The sidecar now tries multiple ports (8765-8775) and automatically handshakes with Flutter. This fixes "Connection Refused" issues.
- **Port Fallback:** Automated retry logic if the default port is busy.

## [v1.6.1] - 2026-02-16
### Added
- **Sidecar Diagnostics:** New section in Settings to view engine status, last error, and copy log file paths.
- **Improved Logging:** Enhanced stdout/stderr capture from the sidecar.

## [v1.6.0] - 2026-02-16
### Added
- **RODECaster Pro Support:** New MIDI Trigger ID system that handles channel-specific messages.
- **Mixer Panel:** New multi-fader mixer UI to group pads and control volumes via hardware MIDI faders.
- **Background Pads:** Ability to mark pads as "Background," excluding them from the Master Timer and Local API.
- **SQLite Storage:** Migrated from JSON to SQLite (sqflite) for robust data management.
- **Heartbeat System:** 60FPS UI refresh independent of audio playback.

---

## Technical Details (Prior Build Fixes)

### 1. `lib/app/service/sidecar_service.dart`
- Added file-based logging system using `path_provider`.
- All sidecar startup activities are now logged to `~/Library/Application Support/com.example.padvibe/logs/`.
- Added code signature verification on macOS.

### 2. `sidecar/build_sidecar.sh`
- Added automatic code signing after PyInstaller build.
- Binary is now ad-hoc signed with `codesign --force --deep --sign -`.

### 3. `macos/Runner/Release.entitlements`
- Added `com.apple.security.cs.allow-jit`.
- Added `com.apple.security.cs.disable-library-validation`.

---

## Testing on Remote Macs
If the app fails to start or play audio:
1. Open **Settings > Sidecar Diagnostics**.
2. Click **Copy Logs Path**.
3. Share the content of that log file.
4. Verify architecture: Built for Intel (x86_64), requires Rosetta 2 on M1/M2/M3.
