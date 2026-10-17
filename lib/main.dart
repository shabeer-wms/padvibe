import 'package:padvibe/app/service/audio_engine_service.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app/routes/app_pages.dart';
import 'app/core/logging/app_log.dart';
import 'app/core/theme/app_theme.dart';

Future<void> main() async {
  // Anything that escapes the app's own error handling ends up in the log.
  await runZonedGuarded(_run, (e, st) => AppLog.error('zone', e, st));
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  AppLog.installHandlers();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Only allow one instance
  final isFirstInstance = await FlutterSingleInstance().isFirstInstance();
  if (!isFirstInstance) {
    AppLog.log(
      'app',
      'Another instance is already running; focusing it and exiting',
    );
    await FlutterSingleInstance().focus();
    exit(0);
  }

  // Initialize services in order of dependency
  await Get.putAsync(() => StorageService().init());
  Get.put(SidecarService(), permanent: true);
  Get.put(MidiInterfaceService(), permanent: true);
  Get.put(AudioEngineService(), permanent: true);
  Get.put(AudioPlayerService(), permanent: true);
  Get.put(LocalApiService(), permanent: true);

  AppLog.log('app', 'Services ready; starting UI');
  runApp(
    GetMaterialApp(
      title: "PadVibe",
      initialRoute: AppPages.initial,
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
    ),
  );
}
