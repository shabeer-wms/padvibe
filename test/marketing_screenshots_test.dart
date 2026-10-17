// Renders the website's screenshots from the real UI with realistic data.
// Skipped unless SHOWCASE_DIR is set:
//   SHOWCASE_DIR=/tmp/shots flutter test test/marketing_screenshots_test.dart
// then: python3 padvibe-web/tools/make_assets.py /tmp/shots <flutter>/bin/cache/artifacts/material_fonts
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/core/theme/app_theme.dart';
import 'package:padvibe/app/data/pad_model.dart';
import 'package:padvibe/app/modules/home/controllers/home_controller.dart';
import 'package:padvibe/app/modules/home/views/home_view.dart';
import 'package:padvibe/app/modules/home/views/pad_settings/pad_settings_dialog.dart';
import 'package:padvibe/app/modules/home/views/settings/settings_dialog.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';

class _Sidecar extends SidecarService {
  @override
  void onInit() {} // ignore: must_call_super
  @override
  void onClose() {} // ignore: must_call_super
}

class _Storage extends StorageService {}

class _Audio extends AudioPlayerService {
  @override
  void onInit() {} // ignore: must_call_super
  @override
  bool isPlaying(String path) => path.endsWith('rimshot.wav') || path.endsWith('bed-lofi.mp3');
  @override
  bool isPaused(String path) => false;
  @override
  Duration getLength(String path) => const Duration(seconds: 204);
  @override
  Duration getPosition(String path) => path.endsWith('bed-lofi.mp3') ? const Duration(seconds: 71) : const Duration(seconds: 1);
  @override
  double getRemainingTime() => 133.0;
  @override
  List<double>? getWaveform(String path) {
    final r = math.Random(path.hashCode);
    return List.generate(100, (i) => (0.25 + 0.75 * r.nextDouble()) * (0.55 + 0.45 * math.sin(i / 9)).abs());
  }
  @override
  int getDeviceChannels(int? deviceId) => deviceId == 1 ? 16 : 2;
}

class _Midi extends MidiInterfaceService {
  @override
  void onInit() {} // ignore: must_call_super
}

class _Api extends LocalApiService {
  @override
  void onInit() {} // ignore: must_call_super
}

final _skip = Platform.environment['SHOWCASE_DIR'] == null;
final _shot = GlobalKey();
ThemeMode _mode = ThemeMode.dark;

Future<void> _fonts() async {
  final exe = Platform.resolvedExecutable;
  final dir = '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, String file) async {
    final bytes = await File('$dir/$file').readAsBytes();
    final l = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await l.load();
  }
  await load('Roboto', 'Roboto-Regular.ttf');
  await load('Menlo', 'Roboto-Regular.ttf');
  await load('MaterialIcons', 'MaterialIcons-Regular.otf');
}

const _names = [
  'Intro', 'Outro', 'Applause', 'Airhorn', 'Rimshot', 'Drumroll', 'Sting', 'Whoosh',
  'Cheer', 'Ding', 'Buzzer', 'Bumper', 'Crowd', 'Thunder', 'Bed (lo-fi)', 'Laugh',
];
const _files = [
  'intro.mp3', 'outro.mp3', 'applause.wav', 'airhorn.wav', 'rimshot.wav', 'drumroll.wav', 'sting.wav', 'whoosh.wav',
  'cheer.wav', 'ding.wav', 'buzzer.wav', 'bumper.mp3', 'crowd.wav', 'thunder.wav', 'bed-lofi.mp3', 'laugh.wav',
];

HomeController _setUp() {
  Get.testMode = true;
  Get.reset();
  final sidecar = Get.put<SidecarService>(_Sidecar());
  sidecar.wsConnectionStatus.value = 'Connected';
  sidecar.sidecarStatus.value = 'Running';
  Get.put<StorageService>(_Storage());
  final audio = Get.put<AudioPlayerService>(_Audio());
  audio.outputDevices.assignAll([
    PlaybackDevice(id: 0, name: 'Studio Monitors', isDefault: true),
    PlaybackDevice(id: 1, name: 'USB Audio Interface (16 ch)'),
    PlaybackDevice(id: 2, name: 'Headphones'),
  ]);
  audio.selectedDevice.value = audio.outputDevices.first;
  audio.masterPeakL.value = 0.74;
  audio.masterPeakR.value = 0.68;
  audio.masterRmsL = 0.5;
  audio.masterRmsR = 0.46;
  final midi = Get.put<MidiInterfaceService>(_Midi());
  midi.devices.assignAll([MidiDevice('RODECaster Pro II', '1', 'input', true), MidiDevice('Launchpad Mini', '2', 'input', false)]);
  midi.connectedDevice.value = midi.devices.first;
  Get.put<LocalApiService>(_Api());
  final c = Get.put(HomeController());
  final pads = <Pad>[
    for (var i = 0; i < 20; i++)
      i < _names.length
          ? Pad(name: _names[i], path: '/library/${_files[i]}', isLooping: i == 14 || i == 12, midiNote: i < 8 ? 36 + i : null)
          : Pad(name: 'Pad ${i + 1}'),
  ];
  c.pads.assignAll(pads);
  c.groups.assignAll([
    PadGroup(id: '1', name: 'Podcast', pads: pads),
    PadGroup(id: '2', name: 'Live Show', pads: pads),
    PadGroup(id: '3', name: 'Stream', pads: pads),
  ]);
  c.faders.assignAll([
    const Fader(id: 'music', name: 'Music', volume: 0.62, midiCc: 21),
    const Fader(id: 'fx', name: 'Effects', volume: 0.85, midiCc: 22),
    const Fader(id: 'voice', name: 'Voice', volume: 0.9),
  ]);
  return c;
}

Future<void> _pump(WidgetTester t, Size size, Widget home) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(
    key: _shot,
    child: GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light, fontFamily: 'Roboto'),
      darkTheme: AppTheme.build(Brightness.dark, fontFamily: 'Roboto'),
      themeMode: _mode,
      home: home,
    ),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _save(WidgetTester t, String name) async {
  final dir = Platform.environment['SHOWCASE_DIR']!;
  await t.runAsync(() async {
    final b = _shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (_skip) return;
    await _fonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), (_) async => null);
  });
  tearDown(Get.reset);

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    final tag = mode.name;
    testWidgets('home $tag', skip: _skip, (t) async {
      _mode = mode;
      _setUp();
      await _pump(t, const Size(1440, 900), const HomeView());
      await _save(t, 'home-$tag');
      await t.pumpWidget(const SizedBox());
      await Get.deleteAll(force: true);
    });
    testWidgets('pad settings $tag', skip: _skip, (t) async {
      _mode = mode;
      final c = _setUp();
      c.pads[3] = c.pads[3].copyWith(keyboardShortcut: 'A', midiNote: 39);
      await _pump(t, const Size(1440, 900), Scaffold(body: Center(child: PadSettingsDialog(controller: c, padIndex: 3, initialTab: PadSettingsTab.triggers))));
      await _save(t, 'pad-settings-$tag');
      await t.pumpWidget(const SizedBox());
      await Get.deleteAll(force: true);
    });
    testWidgets('settings $tag', skip: _skip, (t) async {
      _mode = mode;
      final c = _setUp();
      await _pump(t, const Size(1100, 760), Scaffold(body: SettingsDialog(controller: c, initialSection: SettingsSection.midi)));
      await _save(t, 'settings-midi-$tag');
      await t.pumpWidget(const SizedBox());
      await Get.deleteAll(force: true);
    });
  }
}
