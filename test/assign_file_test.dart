// ignore_for_file: depend_on_referenced_packages
// Exercises assigning a file to a pad with the real StorageService and a temp
// library: the file must be copied into the library, the pad must point at the
// copy, and clearing the pad must delete the copy (never the original).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/modules/home/controllers/home_controller.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

class _Sidecar extends SidecarService {
  @override
  void onInit() {} // ignore: must_call_super
  @override
  void onClose() {} // ignore: must_call_super
}

class _Audio extends AudioPlayerService {
  final unloaded = <String>[];
  @override
  void onInit() {} // ignore: must_call_super
  @override
  Future<void> loadWaveform(String path) async {}
  @override
  void unload(String path) => unloaded.add(path);
}

class _Midi extends MidiInterfaceService {
  @override
  void onInit() {} // ignore: must_call_super
}

class _Api extends LocalApiService {
  @override
  void onInit() {} // ignore: must_call_super
}

void main() {
  late Directory tmp;
  late HomeController c;
  late _Audio audio;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('padvibe_assign');
    PathProviderPlatform.instance = _Paths(tmp.path);
    Get.testMode = true;
    Get.reset();
    Get.put<SidecarService>(_Sidecar());
    Get.put<StorageService>(await StorageService().init());
    audio = Get.put<AudioPlayerService>(_Audio()) as _Audio;
    Get.put<MidiInterfaceService>(_Midi());
    Get.put<LocalApiService>(_Api());
    c = Get.put(HomeController());
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
    await tmp.delete(recursive: true);
  });

  test('assigning a file copies it into the library and clearing deletes the copy', () async {
    final original = File(p.join(tmp.path, 'Downloads', 'clip.mp3'))..createSync(recursive: true);
    original.writeAsBytesSync(List.filled(2048, 7));

    await c.assignFilePathToPad(0, original.path);

    final path = c.pads[0].path!;
    expect(path, isNot(original.path), reason: 'pad should point at the library copy');
    expect(p.isWithin(p.join(tmp.path, 'pads_audio'), path), isTrue);
    expect(File(path).existsSync(), isTrue);
    expect(c.pads[0].isLoading, isFalse);

    // Replacing with another file releases the previous library copy.
    final second = File(p.join(tmp.path, 'Downloads', 'other.wav'))..writeAsBytesSync(List.filled(512, 1));
    await c.assignFilePathToPad(0, second.path);
    expect(File(path).existsSync(), isFalse, reason: 'replaced copy should be deleted');
    expect(audio.unloaded, contains(path));

    final replacement = c.pads[0].path!;
    await c.clearPad(0);
    expect(c.pads[0].path, isNull);
    expect(File(replacement).existsSync(), isFalse, reason: 'cleared pad copy should be deleted');
    expect(original.existsSync(), isTrue, reason: 'the original must never be deleted');
    expect(second.existsSync(), isTrue);
  });
}
