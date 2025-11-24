import 'dart:async';
import 'dart:io';
import 'package:PadVibe/app/data/pad_model.dart';
import 'package:PadVibe/app/service/audio_player_service.dart';
import 'package:PadVibe/app/service/storage_service.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  final audioService = Get.find<AudioPlayerService>();
  final storage = Get.put(StorageService(), permanent: true);

  final count = 0.obs;

  // Tabs / Groups
  final groups = <PadGroup>[].obs;
  final currentGroupIndex = 0.obs;

  // The pads currently displayed (synced with groups[currentGroupIndex])
  final pads = <Pad>[for (int i = 1; i <= 20; i++) Pad(name: 'Pad $i')].obs;

  final remainingSeconds = 0.0.obs;
  Timer? _ticker;

  // Track the created timer window id to push updates
  int? _timerWindowId;

  final FocusNode focusNode = FocusNode();

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
    }();

    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
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

  // --- Tab Management ---

  void switchTab(int index) {
    if (index < 0 || index >= groups.length) return;

    // Stop all sounds when switching tabs
    stopAll();

    currentGroupIndex.value = index;
    pads.assignAll(groups[index].pads);
    _sanitizeCurrentPads(); // Check files for the new tab
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
    await audioService.playSound(path, loop: pad.isLooping);
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
  }

  Future<void> restartPad(int index) async {
    final pad = pads[index];
    if (pad.path == null) return;
    await audioService.seek(pad.path!, Duration.zero);
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
  }

  void assignKeyboardShortcut(int index, String? keyLabel) {
    pads[index] = pads[index].copyWith(keyboardShortcut: keyLabel);
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
  void onReady() {
    super.onReady();
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
}
