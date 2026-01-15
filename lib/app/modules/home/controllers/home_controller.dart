import 'dart:async';
import 'dart:io';
import 'package:padvibe/app/data/pad_model.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  final audioService = Get.find<AudioPlayerService>();
  final midiService = Get.find<MidiInterfaceService>();
  final sidecarService = Get.find<SidecarService>();
  final storage = Get.find<StorageService>();
  final localApiService = Get.find<LocalApiService>();

  final count = 0.obs;
  // Signal to force UI updates (e.g. when seeking while paused)
  final forceUpdate = 0.obs;

  // Tabs / Groups
  final groups = <PadGroup>[].obs;
  final currentGroupIndex = 0.obs;

  // Grid Settings
  final gridColumns = 5.obs; // Default to 5 columns

  // The pads currently displayed (synced with groups[currentGroupIndex])
  final pads = <Pad>[for (int i = 1; i <= 20; i++) Pad(name: 'Pad $i')].obs;

  final remainingSeconds = 0.0.obs;
  Timer? _ticker;

  // Track the created timer window id to push updates
  int? _timerWindowId;
  Timer? _deviceSwitchDebounce;
  final Map<int, Timer> _padUpdateDebounce = {};

  final FocusNode focusNode = FocusNode();

  // --- Inline Renaming ---
  final editingPadIndex = (-1).obs;
  final TextEditingController renamePadInputController =
      TextEditingController();

  void startRenamingPad(int index) {
    if (index < 0 || index >= pads.length) return;
    editingPadIndex.value = index;
    renamePadInputController.text = pads[index].name;
  }

  // ... (keep existing methods)

  Future<void> selectAudioDevice(PlaybackDevice device) async {
    _deviceSwitchDebounce?.cancel();
    _deviceSwitchDebounce = Timer(const Duration(milliseconds: 400), () async {
      await audioService.selectOutputDevice(device);
      await storage.saveSelectedAudioDevice(device.id, device.name);

      // Migrate currently playing pads that are using the Global Default (deviceId == null)
      for (final pad in pads) {
        if (pad.path != null &&
            pad.deviceId == null &&
            audioService.isPlaying(pad.path!)) {
          // Restart on new device
          final currentPos = audioService.getPosition(pad.path!);
          // Stop without resetting active handle immediately to avoid UI flicker?
          // Actually stopPath will clear handle.
          await audioService.stopPath(pad.path!);
          await Future.delayed(const Duration(milliseconds: 50));
          await audioService.playSound(
            pad.path!,
            loop: pad.isLooping,
            deviceId: null, // Will use new default
            outputChannels: pad.outputChannels,
          );
          await audioService.seek(pad.path!, currentPos);
        }
      }
    });
  }

  void savePadName(int index, String name) {
    if (index < 0 || index >= pads.length) return;
    pads[index] = pads[index].copyWith(name: name);
    _updateCurrentGroup();
    _saveGroups();
    editingPadIndex.value = -1;
    renamePadInputController.clear();
  }

  void cancelRenamingPad() {
    editingPadIndex.value = -1;
    renamePadInputController.clear();
  }

  @override
  void onInit() {
    super.onInit();
    // Load persisted groups
    () async {
      await storage.init();
      final loadedGroups = await storage.loadPadGroups();

      if (loadedGroups.isNotEmpty) {
        groups.assignAll(loadedGroups);
      } else {
        // Initial default group if nothing loaded (should be handled by storage migration, but safe fallback)
        groups.add(
          PadGroup(
            id: 'default',
            name: 'Default',
            pads: List.generate(20, (i) => Pad(name: 'Pad ${i + 1}')),
          ),
        );
      }

      // Initialize pads from the first group
      if (groups.isNotEmpty) {
        pads.assignAll(groups[0].pads);
        currentGroupIndex.value = 0;
      }

      // Sanitize missing files (check current group only for now, or all?)
      // Ideally check all, but for performance let's check current on load, or lazy load.
      // For now, let's just stick to the existing logic but apply it to the active pads
      // and maybe iterate all groups if needed.
      // To avoid complexity, we'll just sanitize the active pads when they are loaded.
      await _sanitizeCurrentPads();
      _loadAllWaveforms();
    }();

    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) async {
      final v = audioService.getRemainingTime();
      remainingSeconds.value = v;

      // Push updates to the secondary window if it exists
      final id = _timerWindowId;
      if (id != null) {
        try {
          await DesktopMultiWindow.invokeMethod(id, 'update_secs', v);
        } catch (_) {
          // Ignore if window was closed or not ready
        }
      }
    });

    // Listen to MIDI events
    midiService.noteStream.listen((event) {
      if (editingPadIndex.value != -1) return; // Ignore MIDI if editing name

      if (event.type == MidiEventType.noteOn) {
        debugPrint('HomeController received MIDI Note On: ${event.note}');
        final index = pads.indexWhere((p) => p.midiNote == event.note);
        debugPrint('Matching pad index: $index');
        if (index != -1) {
          playPad(index);
        }
      }
    });

    // Restore saved audio output device
    () async {
      final savedDeviceName = await storage.getSavedAudioDeviceName();
      final savedDeviceId = await storage.getSavedAudioDeviceId();

      if (savedDeviceName != null || savedDeviceId != null) {
        // Wait for devices to be enumerated (max 5 seconds)
        int retries = 0;
        while (audioService.outputDevices.isEmpty && retries < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          retries++;
        }

        if (audioService.outputDevices.isNotEmpty) {
          PlaybackDevice? device;

          // Try matching by name first (most reliable)
          if (savedDeviceName != null) {
            device = audioService.outputDevices.firstWhereOrNull(
              (d) => d.name == savedDeviceName,
            );
          }

          // Fallback to ID
          device ??= audioService.outputDevices.firstWhereOrNull(
            (d) => d.id == savedDeviceId,
          );

          if (device != null) {
            await audioService.selectOutputDevice(device);
          }
        }
      }
    }();
  }

  Future<void> _sanitizeCurrentPads() async {
    bool changed = false;
    for (var i = 0; i < pads.length; i++) {
      final p = pads[i].path;
      if (p == null) continue;
      final exists = kIsWeb ? true : File(p).existsSync();
      if (!exists) {
        pads[i] = pads[i].copyWith(path: null);
        changed = true;
        continue;
      }
      if (!kIsWeb) {
        final inLib = await storage.isInAudioLibrary(p);
        if (!inLib) {
          try {
            final dst = await storage.importAudioFile(p);
            pads[i] = pads[i].copyWith(path: dst);
            changed = true;
          } catch (_) {
            pads[i] = pads[i].copyWith(path: null);
            changed = true;
          }
        }
      }
    }
    if (changed) {
      _updateCurrentGroup();
      await _saveGroups();
    }
  }

  void _loadAllWaveforms() {
    for (final pad in pads) {
      if (pad.path != null) {
        audioService.loadWaveform(pad.path!);
      }
    }
  }

  void updateGridColumns(int cols) {
    gridColumns.value = cols;
    // Persist later
  }

  // --- Tab Management ---

  void switchTab(int index) {
    if (index < 0 || index >= groups.length) return;

    // Stop all sounds when switching tabs
    stopAll();

    currentGroupIndex.value = index;
    pads.assignAll(groups[index].pads);
    _sanitizeCurrentPads(); // Check files for the new tab
    _loadAllWaveforms();
  }

  void addTab(String name) {
    final newGroup = PadGroup(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      pads: List.generate(20, (i) => Pad(name: 'Pad ${i + 1}')),
    );
    groups.add(newGroup);
    _saveGroups();
    // Switch to new tab
    switchTab(groups.length - 1);
  }

  void renameTab(int index, String newName) {
    if (index < 0 || index >= groups.length) return;
    groups[index] = groups[index].copyWith(name: newName);
    _saveGroups();
  }

  void deleteTab(int index) {
    if (groups.length <= 1) return; // Don't delete the last tab

    groups.removeAt(index);

    // Adjust index
    if (currentGroupIndex.value >= groups.length) {
      currentGroupIndex.value = groups.length - 1;
    } else if (currentGroupIndex.value == index) {
      // If we deleted the current tab, stay at the same index (which is now the next tab)
      // or go back if we were at the end.
      // Actually if we deleted index 1 and we were at 1, now index 1 is the old index 2.
      // So we just need to refresh pads.
    }

    // Force refresh of pads
    switchTab(currentGroupIndex.value);
    _saveGroups();
  }

  // --- Pad Actions ---

  Future<void> playPad(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    final path = pad.path!;
    // Guard against stale paths
    if (!kIsWeb && !File(path).existsSync()) {
      pads[index] = pads[index].copyWith(path: null);
      _updateCurrentGroup();
      await _saveGroups();
      return;
    }

    if (audioService.isPlaying(path)) {
      if (audioService.isPaused(path)) {
        await audioService.resumePath(path);
      } else {
        await audioService.pausePath(path);
      }
      return;
    }
    await audioService.playSound(
      path,
      loop: pad.isLooping,
      deviceId: pad.deviceId,
      outputChannels: pad.outputChannels,
      filterType: pad.filterType,
      filterFrequency: pad.filterFrequency,
    );
  }

  void updateFilterForPad(int index, String type, double freq) async {
    final pad = pads[index];
    pads[index] = pad.copyWith(filterType: type, filterFrequency: freq);
    _updateCurrentGroup();
    _saveGroups();

    if (pad.path != null && audioService.isPlaying(pad.path!)) {
      await audioService.setFilter(pad.path!, type, freq);
    }
  }

  void assignDeviceIdToPad(int index, int? deviceId) async {
    _padUpdateDebounce[index]?.cancel();
    _padUpdateDebounce[index] = Timer(
      const Duration(milliseconds: 300),
      () async {
        final pad = pads[index];
        final oldPath = pad.path;

        // When switching device, reset channels to avoid invalid routing
        pads[index] = pads[index].copyWith(
          deviceId: deviceId,
          clearDeviceId: deviceId == null,
          clearOutputChannels: true,
        );
        _updateCurrentGroup();
        _saveGroups();

        // Instant routing update if playing
        if (oldPath != null && audioService.isPlaying(oldPath)) {
          final currentPos = audioService.getPosition(oldPath);
          final activeDeviceId = audioService.getDeviceIdForPath(oldPath);
          final effectiveNewDeviceId =
              deviceId ?? audioService.selectedDevice.value?.id;

          if (activeDeviceId == effectiveNewDeviceId) {
            // Same device, just reset channels to default
            await audioService.setRouting(oldPath, null);
          } else {
            // Different device, must restart
            await audioService.stopPath(oldPath);
            await audioService.playSound(
              oldPath,
              loop: pad.isLooping,
              deviceId: deviceId,
            );
            await audioService.seek(oldPath, currentPos);
          }
        }
      },
    );
  }

  void assignOutputChannelsToPad(int index, List<int>? channels) async {
    final pad = pads[index];
    pads[index] = pad.copyWith(
      outputChannels: channels,
      clearOutputChannels: channels == null,
    );
    _updateCurrentGroup();
    _saveGroups();

    // Instant routing update if playing
    if (pad.path != null && audioService.isPlaying(pad.path!)) {
      await audioService.setRouting(pad.path!, channels);
    }
  }

  Future<void> stopPad(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    await audioService.stopPath(pad.path!);
  }

  Future<void> clearPad(int index) async {
    final pad = pads[index];
    if (pad.path != null) {
      await audioService.stopPath(pad.path!);
    }
    // Reset pad but keep name and color
    pads[index] = Pad(name: pad.name, color: pad.color);
    _updateCurrentGroup();
    await _saveGroups();
  }

  void toggleLoop(int index) {
    final pad = pads[index];
    final newLooping = !pad.isLooping;
    pads[index] = pad.copyWith(isLooping: newLooping);

    if (pad.path != null) {
      // If playing, update the active handle immediately
      audioService.setLooping(pad.path!, newLooping);
    }

    _updateCurrentGroup();
    _saveGroups();
  }

  Future<void> seekPad(int index, double value) async {
    final pad = pads[index];
    if (pad.path == null) return;
    final path = pad.path!;
    final length = audioService.getLength(path);
    final position = length * value;
    await audioService.seek(path, position);
    forceUpdate.value++;
  }

  Future<void> restartPad(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    await audioService.seek(pad.path!, Duration.zero);
    forceUpdate.value++;
  }

  Future<void> skipForward(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    final path = pad.path!;
    final current = audioService.getPosition(path);
    final length = audioService.getLength(path);
    final newPos = current + const Duration(seconds: 5);
    if (newPos < length) {
      await audioService.seek(path, newPos);
    } else {
      // optional: stop or seek to end
      await audioService.seek(path, length);
    }
    forceUpdate.value++;
  }

  Future<void> skipBackward(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    final path = pad.path!;
    final current = audioService.getPosition(path);
    final newPos = current - const Duration(seconds: 5);
    if (newPos > Duration.zero) {
      await audioService.seek(path, newPos);
    } else {
      await audioService.seek(path, Duration.zero);
    }
    forceUpdate.value++;
  }

  void assignKeyboardShortcut(int index, String? keyLabel) {
    pads[index] = pads[index].copyWith(
      keyboardShortcut: keyLabel,
      clearKeyboardShortcut: keyLabel == null,
    );
    _updateCurrentGroup();
    _saveGroups();
  }

  void assignMidiNote(int index, int? note) {
    pads[index] = pads[index].copyWith(
      midiNote: note,
      clearMidiNote: note == null,
    );
    _updateCurrentGroup();
    _saveGroups();
  }

  Future<void> assignFileToPad(int index) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    String finalPath = path;
    if (!kIsWeb) {
      try {
        finalPath = await storage.importAudioFile(path);
      } catch (_) {
        return;
      }
    }
    pads[index] = pads[index].copyWith(path: finalPath);
    _updateCurrentGroup();
    await _saveGroups();
  }

  Future<void> addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a'],
    );
    if (result == null) return;

    final available = <int>[];
    for (var i = 0; i < pads.length; i++) {
      if (pads[i].path == null) available.add(i);
    }

    int idx = 0;
    for (final f in result.files) {
      if (idx >= available.length) break;
      if (f.path == null) continue;

      String finalPath = f.path!;
      if (!kIsWeb) {
        try {
          finalPath = await storage.importAudioFile(f.path!);
        } catch (_) {
          continue;
        }
      }
      final slot = available[idx++];
      pads[slot] = pads[slot].copyWith(path: finalPath);
    }
    _updateCurrentGroup();
    await _saveGroups();
  }

  Future<void> stopAll() async {
    await audioService.stopAllSounds();
  }

  Future<void> clearAll() async {
    await audioService.clearAll();

    // Clear current pads
    pads.clear();
    pads.addAll(<Pad>[for (int i = 1; i <= 20; i++) Pad(name: 'Pad $i')].obs);

    // Update group
    _updateCurrentGroup();
    await _saveGroups();

    // Note: We are NOT clearing the entire storage library or all groups,
    // just the current tab's pads as per "Clear All" semantics usually applying to view.
    // If user wants to factory reset everything, that's different.
    // But the original code did `storage.clear()` which deleted the file.
    // I should probably respect that if "Clear All" means "Reset App".
    // However, with tabs, "Clear All" might mean "Clear this tab".
    // I will assume "Clear This Tab" for safety.
  }

  void _updateCurrentGroup() {
    if (currentGroupIndex.value < groups.length) {
      groups[currentGroupIndex.value] = groups[currentGroupIndex.value]
          .copyWith(pads: pads.toList());
    }
  }

  Future<void> _saveGroups() async {
    await storage.savePadGroups(groups.toList());
  }

  @override
  void onClose() {
    _ticker?.cancel();
    focusNode.dispose();
    super.onClose();
  }

  void increment() => count.value++;

  void assignFilePathToPad(int index, String data) async {
    // drag-and-drop path assignment; copy to app library
    String finalPath = data;
    if (!kIsWeb) {
      try {
        finalPath = await storage.importAudioFile(data);
      } catch (_) {
        return;
      }
    }
    pads[index] = pads[index].copyWith(path: finalPath);
    _updateCurrentGroup();
    await _saveGroups();
  }

  Future<void> showOverlay(BuildContext context) async {
    // Create secondary window and remember its id
    final window = await DesktopMultiWindow.createWindow('timer');
    _timerWindowId = window.windowId;
    // Pass a simple non-empty string; main.dart only checks args.isNotEmpty
    window
      ..setFrame(const Offset(100, 100) & const Size(800, 600))
      ..center()
      ..show();

    // Send an initial value so the overlay starts immediately
    final id = _timerWindowId;
    if (id != null) {
      // Allow a short delay for handler registration in the secondary window
      Future.delayed(const Duration(milliseconds: 150), () {
        final v = audioService.getRemainingTime();
        DesktopMultiWindow.invokeMethod(
          id,
          'update_secs',
          v,
        ).catchError((_) {});
      });
    }
  }
  // --- Settings ---

  String get remoteEndpointUrl => localApiService.remoteEndpointUrl.value;

  void updateRemoteEndpoint(String url) {
    localApiService.updateRemoteEndpoint(url);
  }
}
