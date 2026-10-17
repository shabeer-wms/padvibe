// Renders the main screen and every Settings section at several window sizes
// and fails on any layout overflow. Set UI_PREVIEW_DIR to also save PNGs:
//   UI_PREVIEW_DIR=build/ui_preview flutter test test/ui_responsive_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/core/theme/app_theme.dart';
import 'package:padvibe/app/core/widgets/panels.dart';
import 'package:padvibe/app/data/pad_model.dart';
import 'package:padvibe/app/modules/home/controllers/home_controller.dart';
import 'package:padvibe/app/modules/home/views/mixer/fader_dialog.dart';
import 'package:padvibe/app/modules/home/views/pad_settings/pad_settings_dialog.dart';
import 'package:padvibe/app/modules/home/views/home_view.dart';
import 'package:padvibe/app/modules/home/views/settings/settings_dialog.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';

// Services with their startup side effects (processes, sockets, DB) removed.
class _FakeSidecar extends SidecarService {
  @override
  void onInit() {} // ignore: must_call_super
  @override
  void onClose() {} // ignore: must_call_super
}

class _FakeStorage extends StorageService {}

class _FakeAudio extends AudioPlayerService {
  @override
  void onInit() {} // ignore: must_call_super

  // Device 1 is a multi-channel interface, so the Channels group is shown.
  @override
  int getDeviceChannels(int? deviceId) => deviceId == 1 ? 16 : 2;
}

class _FakeMidi extends MidiInterfaceService {
  @override
  void onInit() {} // ignore: must_call_super
}

class _FakeApi extends LocalApiService {
  @override
  void onInit() {} // ignore: must_call_super
}

const _sizes = <String, Size>{
  'compact': Size(400, 780),
  'medium': Size(720, 800),
  'expanded': Size(1100, 760),
  'wide': Size(1500, 900),
};

final _shot = GlobalKey();
ThemeMode _themeMode = ThemeMode.light;

/// Loads Roboto + Material Icons from the Flutter SDK so previews are readable.
Future<void> _loadFonts() async {
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf('/bin/cache/');
  if (i < 0) return;
  final dir = '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  Future<void> load(String family, String file) async {
    final bytes = await File('$dir/$file').readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Roboto', 'Roboto-Regular.ttf');
  await load(
    'Menlo',
    'Roboto-Regular.ttf',
  ); // stand-in for the monospace family
  await load('MaterialIcons', 'MaterialIcons-Regular.otf');
}

HomeController _setUpApp() {
  Get.testMode = true;
  Get.reset();
  final sidecar = Get.put<SidecarService>(_FakeSidecar());
  sidecar.wsConnectionStatus.value = 'Connected';
  sidecar.sidecarStatus.value = 'Running';
  Get.put<StorageService>(_FakeStorage());
  final audio = Get.put<AudioPlayerService>(_FakeAudio());
  audio.outputDevices.assignAll([
    PlaybackDevice(id: 0, name: 'MacBook Pro Speakers', isDefault: true),
    PlaybackDevice(id: 1, name: 'External Headphones'),
    PlaybackDevice(id: 2, name: 'Studio Display Speakers'),
  ]);
  audio.selectedDevice.value = audio.outputDevices.first;
  final midi = Get.put<MidiInterfaceService>(_FakeMidi());
  midi.devices.assignAll([
    MidiDevice('Launchpad Mini MK3', '1', 'input', false),
    MidiDevice('Akai MPK Mini', '2', 'input', false),
  ]);
  Get.put<LocalApiService>(_FakeApi());
  return Get.put(HomeController());
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget home) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light, fontFamily: 'Roboto'),
        darkTheme: AppTheme.build(Brightness.dark, fontFamily: 'Roboto'),
        themeMode: _themeMode,
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Unmounts the UI and disposes controllers so their timers are cancelled
/// before the test framework checks for pending timers.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await Get.deleteAll(force: true);
}

Future<void> _savePreview(WidgetTester tester, String name) async {
  final dir = Platform.environment['UI_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    // desktop_drop registers a platform channel that does not exist in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (_) async => null,
        );
  });

  tearDown(Get.reset);

  for (final entry in _sizes.entries) {
    testWidgets('home screen has no overflow (${entry.key})', (tester) async {
      _setUpApp();
      await _pumpAt(tester, entry.value, const HomeView());
      await _savePreview(tester, 'home_${entry.key}');
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });
  }

  testWidgets('mixer opens as a drawer below the expanded breakpoint', (
    tester,
  ) async {
    _setUpApp();
    await _pumpAt(tester, _sizes['medium']!, const HomeView());
    await tester.tap(find.byTooltip('Mixer'));
    await tester.pumpAndSettle();
    await _savePreview(tester, 'home_medium_mixer_drawer');
    expect(tester.takeException(), isNull);
    await _finish(tester);
  });

  testWidgets('dark theme renders home and settings', (tester) async {
    _themeMode = ThemeMode.dark;
    addTearDown(() => _themeMode = ThemeMode.light);
    final c = _setUpApp();
    await _pumpAt(tester, _sizes['expanded']!, const HomeView());
    await _savePreview(tester, 'dark_home_expanded');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _pumpAt(
      tester,
      _sizes['expanded']!,
      Scaffold(
        body: SettingsDialog(
          controller: c,
          initialSection: SettingsSection.midi,
        ),
      ),
    );
    await _savePreview(tester, 'dark_settings_midi_expanded');
    expect(tester.takeException(), isNull);
    await _finish(tester);
  });

  // A pad with everything set, so the dialogs render their filled-in states.
  HomeController setUpFilledPad() {
    final c = _setUpApp();
    c.faders.assignAll([
      const Fader(id: 'f1', name: 'Music', midiCc: 21),
      const Fader(id: 'f2', name: 'Effects'),
    ]);
    c.pads[0] = c.pads[0].copyWith(
      path: '/library/intro-theme.mp3',
      keyboardShortcut: 'K',
      midiNote: 36,
      faderId: 'f1',
      isLooping: true,
      deviceId: 1,
      outputChannels: [0, 1],
    );
    return c;
  }

  for (final tab in PadSettingsTab.values) {
    for (final size in ['compact', 'expanded']) {
      testWidgets('pad settings/${tab.name} has no overflow ($size)', (
        tester,
      ) async {
        final c = setUpFilledPad();
        await _pumpAt(
          tester,
          _sizes[size]!,
          Scaffold(
            body: PadSettingsDialog(
              controller: c,
              padIndex: 0,
              initialTab: tab,
            ),
          ),
        );
        await _savePreview(tester, 'pad_${tab.name}_$size');
        expect(tester.takeException(), isNull);
        await _finish(tester);
      });
    }
  }

  testWidgets('fader dialog and shared dialogs render', (tester) async {
    final c = setUpFilledPad();
    await _pumpAt(
      tester,
      _sizes['expanded']!,
      Scaffold(body: FaderDialog(controller: c, index: 0)),
    );
    await _savePreview(tester, 'fader_dialog');
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, _sizes['compact']!, const Scaffold(body: SizedBox()));
    unawaited(
      confirmDialog(
        title: 'Clear Pad 1?',
        message:
            'The audio is removed from this pad and its copy in the PadVibe library is deleted. Your original file is not touched.',
        confirmLabel: 'Clear pad',
        destructive: true,
      ),
    );
    await tester.pumpAndSettle();
    await _savePreview(tester, 'confirm_dialog_compact');
    expect(tester.takeException(), isNull);
    Get.back(result: false);
    await tester.pumpAndSettle();

    unawaited(
      promptDialog(title: 'Rename tab', label: 'Tab name', initial: 'Default'),
    );
    await tester.pumpAndSettle();
    await _savePreview(tester, 'prompt_dialog_compact');
    expect(tester.takeException(), isNull);
    Get.back();
    await tester.pumpAndSettle();
    await _finish(tester);
  });

  testWidgets('right-click menu on a pad is short', (tester) async {
    final c = setUpFilledPad();
    await _pumpAt(tester, _sizes['expanded']!, const HomeView());
    await tester.tapAt(const Offset(80, 150), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await _savePreview(tester, 'pad_context_menu');
    expect(find.text('Pad settings…'), findsOneWidget);
    expect(find.text('Replace file…'), findsOneWidget);
    expect(find.text('Keyboard Shortcut'), findsNothing);
    expect(tester.takeException(), isNull);
    c.pads.length; // keep the controller alive until here
    await _finish(tester);
  });

  for (final section in SettingsSection.values) {
    for (final entry in _sizes.entries.where((e) => e.key != 'wide')) {
      testWidgets('settings/${section.name} has no overflow (${entry.key})', (
        tester,
      ) async {
        final c = _setUpApp();
        await _pumpAt(
          tester,
          entry.value,
          Scaffold(
            body: SettingsDialog(controller: c, initialSection: section),
          ),
        );
        await _savePreview(tester, 'settings_${section.name}_${entry.key}');
        expect(tester.takeException(), isNull);
        await _finish(tester);
      });
    }
  }
}
