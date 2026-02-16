import 'package:padvibe/app/service/audio_engine_service.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/local_api_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/sidecar_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app/routes/app_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Only allow one instance
  final isFirstInstance = await FlutterSingleInstance().isFirstInstance();
  if (!isFirstInstance) {
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

  runApp(
    GetMaterialApp(
      title: "PadVibe",
      initialRoute: AppPages.initial,
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
    ),
  );
}
