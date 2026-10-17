// A double or triple click must send ONE play request, not stack copies.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/service/audio_engine_service.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';

class _RecordingSidecar extends SidecarService {
  final sent = <Map<String, dynamic>>[];
  @override
  void onInit() {} // ignore: must_call_super
  @override
  void onClose() {} // ignore: must_call_super
  @override
  void send(String message) => sent.add(jsonDecode(message) as Map<String, dynamic>);
}

void main() {
  test('rapid repeated clicks on a pad send a single play_audio', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    Get.reset();
    final sidecar = Get.put<SidecarService>(_RecordingSidecar()) as _RecordingSidecar;
    Get.put(AudioEngineService());
    final audio = Get.put(AudioPlayerService());

    await Future.wait([
      audio.playSound('/lib/a.mp3'),
      audio.playSound('/lib/a.mp3'),
      audio.playSound('/lib/a.mp3'),
    ]);
    await audio.playSound('/lib/b.mp3'); // a different pad is unaffected

    final plays = sidecar.sent.where((m) => m['command'] == 'play_audio').toList();
    expect(plays.map((m) => m['file_path']), ['/lib/a.mp3', '/lib/b.mp3']);
    await Get.deleteAll(force: true);
  });
}
