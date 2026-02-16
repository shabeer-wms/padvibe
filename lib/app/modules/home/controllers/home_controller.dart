import 'dart:async';
import 'dart:io';
import 'package:padvibe/app/data/pad_model.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  // Faders
  final faders = <Fader>[].obs;

  // Grid Settings
  final gridColumns = 5.obs; // Default to 5 columns

  // The pads currently displayed (synced with groups[currentGroupIndex])
  final pads = <Pad>[for (int i = 1; i <= 20; i++) Pad(name: 'Pad $i')].obs;

  final remainingSeconds = 0.0.obs;
  final heartbeat = 0.obs; // Added to trigger UI updates even for background pads
  final masterVolume = 1.0.obs; // Master volume control (0.0 to 1.0)
  Timer? _ticker;

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
    focusNode.requestFocus();
  }

  void cancelRenamingPad() {
    editingPadIndex.value = -1;
    renamePadInputController.clear();
    focusNode.requestFocus();
  }

  @override
  void onInit() {
    super.onInit();

    // Get pre-loaded data from splash screen
    final args = Get.arguments as Map<String, dynamic>?;

    if (args != null) {
      // Load groups from splash
      final loadedGroups = args['groups'] as List<PadGroup>?;
      if (loadedGroups != null && loadedGroups.isNotEmpty) {
        groups.assignAll(loadedGroups);
        pads.assignAll(loadedGroups[0].pads);
        currentGroupIndex.value = 0;
      }

      // Load faders from splash
      final loadedFaders = args['faders'] as List<Fader>?;
      if (loadedFaders != null) {
        faders.assignAll(loadedFaders);
      }

      // Load grid columns from splash
      final loadedGridCols = args['gridColumns'] as int?;
      if (loadedGridCols != null) {
        gridColumns.value = loadedGridCols;
      }

      // Sanitize pads and load waveforms
      _sanitizeCurrentPads();
      _loadAllWaveforms();

      // Restore audio device from splash-provided data
      final savedDeviceName = args['savedAudioDeviceName'] as String?;
      final savedDeviceId = args['savedAudioDeviceId'] as int?;

      if (savedDeviceName != null || savedDeviceId != null) {
        _restoreAudioDevice(savedDeviceName, savedDeviceId);
      }
    }

    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) async {
      heartbeat.value++;
      final v = audioService.getRemainingTime();
      remainingSeconds.value = v;
    });

    // Listen to MIDI events
    midiService.noteStream.listen((event) {
      if (editingPadIndex.value != -1) return; // Ignore MIDI if editing name

      if (event.type == MidiEventType.noteOn) {
        debugPrint(
            'HomeController received MIDI Note Trigger: ID=${event.triggerId}');
        final index = pads.indexWhere((p) => p.midiNote == event.triggerId);
        if (index != -1) playPad(index);
      } else if (event.type == MidiEventType.controlChange) {
        // 1. Check if this CC is a Pad Trigger (Momentary CC)
        final triggerIndex = pads.indexWhere((p) => p.midiNote == event.triggerId);
        if (triggerIndex != -1) {
          if (event.velocity > 0) {
            playPad(triggerIndex);
          }
          return; // Stop processing if handled as trigger
        }

        // 2. Handle Fader CC (Continuous Control)
        for (int i = 0; i < faders.length; i++) {
          if (faders[i].midiCc == event.triggerId) {
            final vol = event.velocity / 127.0;
            updateFaderVolume(i, vol);
          }
        }
      }
    });

    // Reload waveforms when Sidecar reconnects
    ever(sidecarService.wsConnectionStatus, (status) {
      if (status == 'Connected') {
        _loadAllWaveforms();
      }
    });
  }

  Future<void> _restoreAudioDevice(String? deviceName, int? deviceId) async {
    if (deviceName == null && deviceId == null) return;

    // Wait for devices to be enumerated (max 5 seconds)
    int retries = 0;
    while (audioService.outputDevices.isEmpty && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (audioService.outputDevices.isNotEmpty) {
      PlaybackDevice? device;

      // Try matching by name first (most reliable)
      if (deviceName != null) {
        device = audioService.outputDevices.firstWhereOrNull(
          (d) => d.name == deviceName,
        );
      }

      // Fallback to ID
      device ??= audioService.outputDevices.firstWhereOrNull(
        (d) => d.id == deviceId,
      );

      if (device != null) {
        await audioService.selectOutputDevice(device);
      }
    }
  }

  Future<void> _sanitizeCurrentPads() async {
    bool changed = false;
    debugPrint('DEBUG: Starting pad path sanitization...');
    
    final appDir = await getApplicationSupportDirectory();
    final audioLibDir = p.join(appDir.path, 'pads_audio');

    for (var i = 0; i < pads.length; i++) {
      final oldPath = pads[i].path;
      if (oldPath == null) continue;
      
      var exists = kIsWeb ? true : File(oldPath).existsSync();
      debugPrint('DEBUG: Checking pad $i path: $oldPath (Exists: $exists)');
      
      if (!exists && !kIsWeb) {
        // Path broken. Try to relocate in local library
        final fileName = p.basename(oldPath);
        final localPath = p.join(audioLibDir, fileName);
        if (File(localPath).existsSync()) {
          debugPrint('DEBUG: Relocated pad $i to local path: $localPath');
          pads[i] = pads[i].copyWith(path: localPath);
          changed = true;
          continue;
        }
        
        debugPrint('DEBUG: Path missing, clearing pad $i');
        pads[i] = pads[i].copyWith(path: null, clearPath: true);
        changed = true;
        continue;
      }
      if (!kIsWeb) {
        final padPath = pads[i].path;
        if (padPath == null) continue;
        
        final inLib = await storage.isInAudioLibrary(padPath);
        if (!inLib) {
          try {
            final dst = await storage.importAudioFile(padPath);
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
    storage.saveGridColumns(cols);
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
    debugPrint('DEBUG: playPad called for index $index');
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
      volume: pad.volume,
      isBackground: pad.isBackground,
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
    if (keyLabel != null) {
      // Rule: Ensure uniqueness. If this key is already assigned to another pad, remove it from that pad.
      for (int i = 0; i < pads.length; i++) {
        if (i != index && pads[i].keyboardShortcut == keyLabel) {
          pads[i] = pads[i].copyWith(clearKeyboardShortcut: true);
        }
      }
    }

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

  void toggleBackground(int index) {
    final pad = pads[index];
    pads[index] = pad.copyWith(isBackground: !pad.isBackground);
    _updateCurrentGroup();
    _saveGroups();
  }

  void updatePadVolume(int index, double volume) {
    final pad = pads[index];
    final v = volume.clamp(0.0, 1.0);
    pads[index] = pad.copyWith(volume: v);
    _updateCurrentGroup();
    _saveGroups();

    if (pad.path != null && audioService.isPlaying(pad.path!)) {
      audioService.setVolume(pad.path!, v);
    }
  }

  // --- Fader Management ---

  void addFader(String name) {
    faders.add(Fader(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    ));
    _saveFaders();
  }

  void removeFader(int index) {
    final faderId = faders[index].id;
    faders.removeAt(index);
    
    // Unlink pads
    for (int g = 0; g < groups.length; g++) {
      final groupPads = groups[g].pads;
      bool changed = false;
      for (int p = 0; p < groupPads.length; p++) {
        if (groupPads[p].faderId == faderId) {
          groupPads[p] = groupPads[p].copyWith(clearFaderId: true);
          changed = true;
        }
      }
      if (changed) {
        if (g == currentGroupIndex.value) {
          pads.assignAll(groupPads);
        }
        groups[g] = groups[g].copyWith(pads: groupPads);
      }
    }
    _saveGroups();
    _saveFaders();
  }

  void updateFaderVolume(int index, double volume) {
    final fader = faders[index];
    final v = volume.clamp(0.0, 1.0);
    faders[index] = fader.copyWith(volume: v);
    _saveFaders();

    // Update all linked pads across all groups
    for (int g = 0; g < groups.length; g++) {
      final groupPads = groups[g].pads;
      bool changed = false;
      for (int p = 0; p < groupPads.length; p++) {
        if (groupPads[p].faderId == fader.id) {
          groupPads[p] = groupPads[p].copyWith(volume: v);
          changed = true;
          
          // If this pad is in the current group and is playing, update its live volume
          if (g == currentGroupIndex.value && groupPads[p].path != null && audioService.isPlaying(groupPads[p].path!)) {
            audioService.setVolume(groupPads[p].path!, v);
          }
        }
      }
      if (changed) {
        if (g == currentGroupIndex.value) {
          pads.assignAll(groupPads);
        }
        groups[g] = groups[g].copyWith(pads: groupPads);
      }
    }
    _saveGroups();
  }

  void assignFaderMidiCc(int index, int? cc) {
    faders[index] = faders[index].copyWith(midiCc: cc, clearMidiCc: cc == null);
    _saveFaders();
  }

  void assignPadToFader(int padIndex, String? faderId) {
    final fader = faders.firstWhereOrNull((f) => f.id == faderId);
    pads[padIndex] = pads[padIndex].copyWith(
      faderId: faderId,
      clearFaderId: faderId == null,
      volume: fader?.volume ?? pads[padIndex].volume,
    );
    _updateCurrentGroup();
    _saveGroups();
    
    // Update live volume if playing
    if (fader != null && pads[padIndex].path != null && audioService.isPlaying(pads[padIndex].path!)) {
      audioService.setVolume(pads[padIndex].path!, fader.volume);
    }
  }

  Future<void> _saveFaders() async {
    await storage.saveFaders(faders.toList());
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

  // --- Settings ---

  String get remoteEndpointUrl => localApiService.remoteEndpointUrl.value;

  void updateRemoteEndpoint(String url) {
    localApiService.updateRemoteEndpoint(url);
  }

  // --- Master Volume ---
  void updateMasterVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    masterVolume.value = v;
    audioService.setMasterVolume(v);
    // Optionally persist this setting
  }
}
