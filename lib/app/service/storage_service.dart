import 'dart:convert';
import 'dart:io';

import 'package:padvibe/app/data/pad_model.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class StorageService extends GetxService {
  Database? _db;

  // Ensure app-managed audio directory (ApplicationSupport/pads_audio)
  Future<Directory> _ensureAudioDir() async {
    if (kIsWeb) {
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
    final dbPath = p.join(dir.path, 'padvibe.db');
    
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pad_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id TEXT NOT NULL,
            idx INTEGER NOT NULL,
            name TEXT NOT NULL,
            color INTEGER,
            path TEXT,
            is_looping INTEGER DEFAULT 0,
            keyboard_shortcut TEXT,
            midi_note INTEGER,
            volume REAL DEFAULT 1.0,
            is_background INTEGER DEFAULT 0,
            fader_id TEXT,
            device_id INTEGER,
            output_channels TEXT,
            filter_type TEXT DEFAULT 'none',
            filter_frequency REAL DEFAULT 20000.0,
            FOREIGN KEY (group_id) REFERENCES pad_groups (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE faders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            volume REAL DEFAULT 1.0,
            midi_cc INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );

    await _ensureAudioDir();
    await _migrateJsonToSqlite();
    return this;
  }

  Future<void> _migrateJsonToSqlite() async {
    final appDir = await getApplicationSupportDirectory();
    final jsonFile = File(p.join(appDir.path, 'pads.json'));
    
    if (!await jsonFile.exists()) return;
    
    // Check if we already have data in SQLite
    final count = Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM pad_groups'));
    if (count != null && count > 0) return; // Already migrated
    
    try {
      debugPrint('Migrating JSON data to SQLite...');
      final content = await jsonFile.readAsString();
      if (content.isEmpty) return;
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      // 1. Migrate Settings
      if (data.containsKey('selectedAudioDeviceId')) await _saveSetting('selectedAudioDeviceId', data['selectedAudioDeviceId']);
      if (data.containsKey('selectedAudioDeviceName')) await _saveSetting('selectedAudioDeviceName', data['selectedAudioDeviceName']);
      if (data.containsKey('remoteEndpointUrl')) await _saveSetting('remoteEndpointUrl', data['remoteEndpointUrl']);
      if (data.containsKey('webhookIntervalMs')) await _saveSetting('webhookIntervalMs', data['webhookIntervalMs']);
      if (data.containsKey('gridColumns')) await _saveSetting('gridColumns', data['gridColumns']);
      
      // 2. Migrate Groups and Pads
      List<PadGroup> groups = [];
      if (data.containsKey('groups')) {
        final list = (data['groups'] as List? ?? []);
        groups = list.map((e) => PadGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } else if (data.containsKey('pads')) {
        final list = (data['pads'] as List? ?? []);
        final pads = list.map((e) => Pad.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        groups = [PadGroup(id: 'default', name: 'Default', pads: pads)];
      }
      
      if (groups.isNotEmpty) {
        await savePadGroups(groups);
      }
      
      debugPrint('Migration complete.');
    } catch (e) {
      debugPrint('Migration error: $e');
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    await _db?.insert(
      'settings',
      {'key': key, 'value': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getSetting(String key) async {
    final res = await _db?.query('settings', where: 'key = ?', whereArgs: [key]);
    if (res != null && res.isNotEmpty) {
      return res.first['value'] as String?;
    }
    return null;
  }

  Future<void> savePadGroups(List<PadGroup> groups) async {
    await _db?.transaction((txn) async {
      await txn.delete('pad_groups');
      await txn.delete('pads');
      
      for (final group in groups) {
        await txn.insert('pad_groups', {'id': group.id, 'name': group.name});
        for (int i = 0; i < group.pads.length; i++) {
          final pad = group.pads[i];
          await txn.insert('pads', {
            'group_id': group.id,
            'idx': i,
            'name': pad.name,
            'color': pad.color,
            'path': pad.path,
            'is_looping': pad.isLooping ? 1 : 0,
            'keyboard_shortcut': pad.keyboardShortcut,
            'midi_note': pad.midiNote,
            'volume': pad.volume,
            'is_background': pad.isBackground ? 1 : 0,
            'fader_id': pad.faderId,
            'device_id': pad.deviceId,
            'output_channels': pad.outputChannels != null ? jsonEncode(pad.outputChannels) : null,
            'filter_type': pad.filterType,
            'filter_frequency': pad.filterFrequency,
          });
        }
      }
    });
  }

  Future<List<PadGroup>> loadPadGroups() async {
    final groupsData = await _db?.query('pad_groups');
    if (groupsData == null || groupsData.isEmpty) {
      return [];
    }

    final List<PadGroup> groups = [];
    for (final gRow in groupsData) {
      final gId = gRow['id'] as String;
      final padsData = await _db?.query(
        'pads',
        where: 'group_id = ?',
        whereArgs: [gId],
        orderBy: 'idx ASC',
      );
      
      final pads = (padsData ?? []).map((pRow) {
        return Pad(
          name: pRow['name'] as String,
          color: pRow['color'] as int?,
          path: pRow['path'] as String?,
          isLooping: (pRow['is_looping'] as int) == 1,
          keyboardShortcut: pRow['keyboard_shortcut'] as String?,
          midiNote: pRow['midi_note'] as int?,
          volume: (pRow['volume'] as num).toDouble(),
          isBackground: (pRow['is_background'] as int) == 1,
          faderId: pRow['fader_id'] as String?,
          deviceId: pRow['device_id'] as int?,
          outputChannels: pRow['output_channels'] != null 
              ? (jsonDecode(pRow['output_channels'] as String) as List).cast<int>() 
              : null,
          filterType: pRow['filter_type'] as String,
          filterFrequency: (pRow['filter_frequency'] as num).toDouble(),
        );
      }).toList();

      groups.add(PadGroup(id: gId, name: gRow['name'] as String, pads: pads));
    }
    return groups;
  }

  Future<void> saveFaders(List<Fader> faders) async {
    await _db?.transaction((txn) async {
      await txn.delete('faders');
      for (final f in faders) {
        await txn.insert('faders', {
          'id': f.id,
          'name': f.name,
          'volume': f.volume,
          'midi_cc': f.midiCc,
        });
      }
    });
  }

  Future<List<Fader>> loadFaders() async {
    final res = await _db?.query('faders');
    return (res ?? []).map((r) => Fader(
      id: r['id'] as String,
      name: r['name'] as String,
      volume: (r['volume'] as num).toDouble(),
      midiCc: r['midi_cc'] as int?,
    )).toList();
  }

  Future<void> saveSelectedAudioDevice(int deviceId, String deviceName) async {
    await _saveSetting('selectedAudioDeviceId', deviceId);
    await _saveSetting('selectedAudioDeviceName', deviceName);
  }

  Future<int?> getSavedAudioDeviceId() async {
    final val = await _getSetting('selectedAudioDeviceId');
    return val != null ? int.tryParse(val) : null;
  }

  Future<String?> getSavedAudioDeviceName() async {
    return await _getSetting('selectedAudioDeviceName');
  }

  Future<void> saveRemoteEndpointUrl(String url) async {
    await _saveSetting('remoteEndpointUrl', url);
  }

  Future<String?> getRemoteEndpointUrl() async {
    return await _getSetting('remoteEndpointUrl');
  }

  Future<void> saveWebhookInterval(int intervalMs) async {
    await _saveSetting('webhookIntervalMs', intervalMs);
  }

  Future<int?> getWebhookInterval() async {
    final val = await _getSetting('webhookIntervalMs');
    return val != null ? int.tryParse(val) : null;
  }

  Future<void> saveGridColumns(int columns) async {
    await _saveSetting('gridColumns', columns);
  }

  Future<int?> getGridColumns() async {
    final val = await _getSetting('gridColumns');
    return val != null ? int.tryParse(val) : null;
  }

  Future<void> saveThemeMode(String mode) async {
    await _saveSetting('themeMode', mode);
  }

  Future<String?> getThemeMode() async {
    return await _getSetting('themeMode');
  }

  Future<void> clear() async {
    await _db?.delete('pad_groups');
    await _db?.delete('pads');
    await _db?.delete('faders');
    await _db?.delete('settings');
  }
}
