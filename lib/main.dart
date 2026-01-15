import 'package:PadVibe/app/service/audio_engine_service.dart';
import 'package:PadVibe/app/service/audio_player_service.dart';
import 'package:PadVibe/app/service/local_api_service.dart';
import 'package:PadVibe/app/service/midi_interface_service.dart';
import 'package:PadVibe/app/service/sidecar_service.dart';
import 'package:PadVibe/app/service/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/routes/app_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      initialRoute: AppPages.INITIAL,
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
    ),
  );
}
