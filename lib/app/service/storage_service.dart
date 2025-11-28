import 'dart:convert';
import 'dart:io';

import 'package:PadVibe/app/data/pad_model.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class StorageService extends GetxService {
  File? _file;

  // Ensure app-managed audio directory (ApplicationSupport/pads_audio)
  Future<Directory> _ensureAudioDir() async {
    if (kIsWeb) {
      // Not used on web, but return a dummy dir-like structure if needed later.
      throw UnsupportedError('Audio library is not supported on web.');
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'pads_audio'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // Copy a source audio file into the app audio library and return the new path.
  Future<String> importAudioFile(String sourcePath) async {
    if (kIsWeb) return sourcePath;
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }
    final libDir = await _ensureAudioDir();

    final baseName = p.basename(sourcePath);
    var dstPath = p.join(libDir.path, baseName);

    // Avoid clobbering an existing different file name; append a suffix if needed.
    if (await File(dstPath).exists()) {
      final name = p.basenameWithoutExtension(baseName);
      final ext = p.extension(baseName);
      dstPath = p.join(
        libDir.path,
        '${name}_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
    }

    await src.copy(dstPath);
    return dstPath;
  }

  // Check if a path already points inside the app audio library.
  Future<bool> isInAudioLibrary(String? maybePath) async {
    if (kIsWeb || maybePath == null) return false;
    try {
      final libDir = await _ensureAudioDir();
      final libPath = p.normalize(libDir.path);
      final target = p.normalize(maybePath);
      return p.isWithin(libPath, target) || target == libPath;
    } catch (_) {
      return false;
    }
  }

  // Delete all files inside the app audio library.
  Future<void> clearAudioLibrary() async {
    if (kIsWeb) return;
    final libDir = await _ensureAudioDir();
    if (await libDir.exists()) {
      await for (final entity in libDir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<StorageService> init() async {
    if (kIsWeb) return this;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/pads.json');
    // Optionally ensure the audio dir exists early.
    await _ensureAudioDir();
    return this;
  }

  Future<void> savePads(List<Pad> pads) async {
    if (kIsWeb) return;
    final file = await _ensureFile();
    final data = jsonEncode({'pads': pads.map((p) => p.toJson()).toList()});
    await file.writeAsString(data);
  }

  Future<List<Pad>> loadPads({int? ensureCount}) async {
    if (kIsWeb) return [];
    final file = await _ensureFile();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final list = (jsonMap['pads'] as List? ?? []);
    final loaded = list
        .map((e) => Pad.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (ensureCount != null && loaded.length < ensureCount) {
      for (int i = loaded.length; i < ensureCount; i++) {
        loaded.add(Pad(name: 'Pad ${i + 1}'));
      }
    }
    return loaded;
  }

  Future<void> savePadGroups(List<PadGroup> groups) async {
    if (kIsWeb) return;
    final file = await _ensureFile();
    final data = jsonEncode({'groups': groups.map((g) => g.toJson()).toList()});
    await file.writeAsString(data);
  }

  Future<List<PadGroup>> loadPadGroups() async {
    if (kIsWeb) return [];
    final file = await _ensureFile();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;

    // Check if we have groups
    if (jsonMap.containsKey('groups')) {
      final list = (jsonMap['groups'] as List? ?? []);
      return list
          .map((e) => PadGroup.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    // Migration: If no groups but 'pads' exist, wrap them in a Default group
    if (jsonMap.containsKey('pads')) {
      final list = (jsonMap['pads'] as List? ?? []);
      final pads = list
          .map((e) => Pad.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Ensure 20 pads
      if (pads.length < 20) {
        for (int i = pads.length; i < 20; i++) {
          pads.add(Pad(name: 'Pad ${i + 1}'));
        }
      }

      return [PadGroup(id: 'default', name: 'Default', pads: pads)];
    }

    return [];
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    final file = await _ensureFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/pads.json');
    return _file!;
  }

  // --- added: audio device preference persistence ---

  /// Save the selected audio device ID
  Future<void> saveSelectedAudioDevice(int deviceId) async {
    if (kIsWeb) return;
    final file = await _ensureFile();
    Map<String, dynamic> data = {};

    // Load existing data
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        data = jsonDecode(content) as Map<String, dynamic>;
      }
    }

    // Update audio device preference
    data['selectedAudioDeviceId'] = deviceId;

    // Save back
    await file.writeAsString(jsonEncode(data));
  }

  /// Get the saved audio device ID
  Future<int?> getSavedAudioDeviceId() async {
    if (kIsWeb) return null;
    final file = await _ensureFile();
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    if (content.isEmpty) return null;

    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    return jsonMap['selectedAudioDeviceId'] as int?;
  }

  // --- end added ---
}
