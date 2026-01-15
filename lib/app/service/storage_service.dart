import 'dart:convert';
import 'dart:io';

import 'package:padvibe/app/data/pad_model.dart';
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

  Future<void> _updateSettings(Map<String, dynamic> newSettings) async {
    if (kIsWeb) return;
    final file = await _ensureFile();
    Map<String, dynamic> data = {};

    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        try {
          data = jsonDecode(content) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    data.addAll(newSettings);
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> savePads(List<Pad> pads) async {
    await _updateSettings({'pads': pads.map((p) => p.toJson()).toList()});
  }

  Future<void> savePadGroups(List<PadGroup> groups) async {
    await _updateSettings({'groups': groups.map((g) => g.toJson()).toList()});
  }

  Future<void> saveSelectedAudioDevice(int deviceId, String deviceName) async {
    await _updateSettings({
      'selectedAudioDeviceId': deviceId,
      'selectedAudioDeviceName': deviceName,
    });
  }

  Future<int?> getSavedAudioDeviceId() async {
    final data = await _loadRawData();
    return data?['selectedAudioDeviceId'] as int?;
  }

  Future<String?> getSavedAudioDeviceName() async {
    final data = await _loadRawData();
    return data?['selectedAudioDeviceName'] as String?;
  }

  Future<void> saveRemoteEndpointUrl(String url) async {
    await _updateSettings({'remoteEndpointUrl': url});
  }

  Future<void> saveWebhookInterval(int intervalMs) async {
    await _updateSettings({'webhookIntervalMs': intervalMs});
  }

  Future<Map<String, dynamic>?> _loadRawData() async {
    if (kIsWeb) return null;
    final file = await _ensureFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.isEmpty) return null;
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<Pad>> loadPads({int? ensureCount}) async {
    final jsonMap = await _loadRawData();
    if (jsonMap == null) return [];
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

  Future<List<PadGroup>> loadPadGroups() async {
    final jsonMap = await _loadRawData();
    if (jsonMap == null) return [];

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

  Future<String?> getRemoteEndpointUrl() async {
    final data = await _loadRawData();
    return data?['remoteEndpointUrl'] as String?;
  }

  Future<int?> getWebhookInterval() async {
    final data = await _loadRawData();
    return data?['webhookIntervalMs'] as int?;
  }

  Future<void> saveGridColumns(int columns) async {
    await _updateSettings({'gridColumns': columns});
  }

  Future<int?> getGridColumns() async {
    final data = await _loadRawData();
    return data?['gridColumns'] as int?;
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

  // --- end added ---
}
