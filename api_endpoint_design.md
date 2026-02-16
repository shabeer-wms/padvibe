# PadVibe Local API Documentation

PadVibe exposes a local HTTP API on port `9696` for external control and state monitoring.

## State Endpoint

### `GET /state`
Retrieves a full snapshot of the application state.

### `GET /levels`
Retrieves real-time master audio levels (RMS and Peak).

### `GET /timer`
Retrieves the current remaining countdown time.

**Response Structure:**
```json
{
  "remaining_seconds": 120.5,
  "estimated_completion_timestamp": "2026-02-16T20:47:40.500Z"
}
```

**Response Structure:**
```json
{
  "rms_l": 0.12,
  "rms_r": 0.11,
  "peak_l": 0.45,
  "peak_r": 0.43
}
```

**Response Structure:**
```json
{
  "global": {
    "remaining_timer_seconds": 120.5,
    "estimated_completion_timestamp": "2026-02-16T20:47:40.500Z",
    "master_volume": 1.0,
    "master_volume_levels": { "left": 0.45, "right": 0.42 },
    "active_group": { "index": 0, "id": "...", "name": "Main" },
    "audio_device": { "id": 1, "name": "Default Output" },
    "midi_device": { "name": "Launchpad MK2" }
  },
  "pads": [
    {
      "id": 0,
      "name": "Kick",
      "color": 4294967295,
      "file_path": "...",
      "playback": { "state": "playing", "position_seconds": 1.2, ... }
    }
  ]
}
```

## Control Endpoints (Simplified)

All control endpoints are accessible via `GET` for ease of use.

### Pad Controls
- `GET /play/<index>`: Toggle Play/Pause for pad at `<index>` (0-19).
- `GET /stop/<index>`: Stop pad at `<index>`.
- `GET /volume/pad/<index>/<value>`: Set pad volume (0.0 to 1.0).
- `GET /seek/<index>/<value>`: Seek pad to position fraction (0.0 to 1.0).

### Global Controls
- `GET /stop_all`: Stop all currently playing pads.
- `GET /volume/master/<value>`: Set master volume (0.0 to 1.0).
- `GET /groups`: List all available pad groups/tabs.
- `GET /groups/<index>/switch`: Switch to the specified group index.
- `GET /faders`: List all volume faders.
- `GET /volume/fader/<index>/<value>`: Set fader volume (0.0 to 1.0).

### Device Management
- `GET /audio/devices`: List available audio output devices.
- `GET /audio/devices/<id>/select`: Select audio output device by ID.
- `GET /midi/devices`: List available MIDI input devices.
- `GET /midi/devices/<name>/connect`: Connect to a MIDI device by name (URL encoded).
- `GET /midi/refresh`: Refresh the MIDI device list.
