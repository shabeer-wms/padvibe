# API Endpoint Design for PadVibe

This document outlines the proposed data structure for an API endpoint that exposes the current state of the PadVibe application, including pad details, playback status, and global timing information.

## Endpoint: `GET /api/v1/state`

**Description:** Retrieves the current snapshot of the application state.

### Response Body (JSON)

```json
{
  "global": {
    "remaining_timer_seconds": 120.5,
    "estimated_completion_timestamp": "2025-11-20T20:47:40.500Z",
    "master_volume_levels": {
      "left": 0.45,
      "right": 0.42
    },
    "active_group": {
      "index": 0,
      "id": "default",
      "name": "Main Group"
    }
  },
  "pads": [
    {
      "id": 0,
      "name": "Kick Drum",
      "color": 4294967295, 
      "file_path": "/path/to/kick.mp3",
      "keyboard_shortcut": "A",
      "settings": {
        "is_looping": false
      },
      "playback": {
        "state": "playing", 
        "position_seconds": 1.2,
        "duration_seconds": 2.5,
        "progress_percent": 0.48
      }
    },
    {
      "id": 1,
      "name": "Pad 2",
      "color": 4289769157,
      "file_path": null,
      "keyboard_shortcut": null,
      "settings": {
        "is_looping": false
      },
      "playback": {
        "state": "empty",
        "position_seconds": 0.0,
        "duration_seconds": 0.0,
        "progress_percent": 0.0
      }
    }
    // ... up to 20 pads
  ]
}
```

## Field Descriptions

### Global Object
*   `remaining_timer_seconds`: (Float) The value of the global countdown timer.
*   `estimated_completion_timestamp`: (String) ISO 8601 timestamp calculating when the timer will reach zero (Current Time + Remaining Seconds).
*   `master_volume_levels`: (Object) Current RMS levels for audio visualization.
    *   `left`: (Float) 0.0 to 1.0
    *   `right`: (Float) 0.0 to 1.0
*   `active_group`: (Object) Details about the currently selected pad group/tab.

### Pad Object
*   `id`: (Integer) The index of the pad (0-19).
*   `name`: (String) The display name of the pad.
*   `color`: (Integer) The ARGB integer value of the pad's color.
*   `file_path`: (String|Null) Absolute path to the assigned audio file. Null if empty.
*   `keyboard_shortcut`: (String|Null) The assigned key (e.g., "A", "SPACE").
*   `settings`:
    *   `is_looping`: (Boolean) Whether the pad is set to loop.
*   `playback`:
    *   `state`: (String) One of: `"playing"`, `"paused"`, `"stopped"`, `"empty"`.
    *   `position_seconds`: (Float) Current playback position.
    *   `duration_seconds`: (Float) Total duration of the audio file.
    *   `progress_percent`: (Float) 0.0 to 1.0 representing playback progress.

## Implementation Notes

To implement this, you would map the `HomeController` state to this JSON structure:

1.  **Pads**: Iterate through `controller.pads`.
2.  **Playback State**: Use `audioService.isPlaying(path)`, `isPaused(path)`, `getPosition(path)`, and `getLength(path)`.
3.  **Global Timer**: Read `controller.remainingSeconds.value`.
4.  **Master Levels**: Read `audioService.getMasterLevels()`.
