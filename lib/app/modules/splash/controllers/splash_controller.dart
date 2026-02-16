import 'package:get/get.dart';
import '../../../data/pad_model.dart';
import '../../../routes/app_pages.dart';
import '../../../service/audio_player_service.dart';
import '../../../service/sidecar_service.dart';
import '../../../service/storage_service.dart';

class SplashController extends GetxController {
  final sidecarService = Get.find<SidecarService>();
  final storage = Get.find<StorageService>();
  final audioService = Get.find<AudioPlayerService>();

  final initStatus = 'Initializing...'.obs;
  final isComplete = false.obs;

  // Store loaded data to pass to HomeController
  final loadedGroups = <PadGroup>[].obs;
  final loadedFaders = <Fader>[].obs;
  final loadedGridColumns = 5.obs;
  String? savedAudioDeviceName;
  int? savedAudioDeviceId;

  @override
  void onInit() {
    super.onInit();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Initialize storage
      initStatus.value = 'Initializing storage...';
      await storage.init();
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 2: Load pad groups
      initStatus.value = 'Loading pad groups...';
      final groups = await storage.loadPadGroups();
      if (groups.isNotEmpty) {
        loadedGroups.assignAll(groups);
      } else {
        // Create default group
        loadedGroups.add(
          PadGroup(
            id: 'default',
            name: 'Default',
            pads: List.generate(20, (i) => Pad(name: 'Pad ${i + 1}')),
          ),
        );
      }

      // Step 2.5: Load faders
      initStatus.value = 'Loading faders...';
      final faders = await storage.loadFaders();
      loadedFaders.assignAll(faders);
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 3: Load grid columns preference
      initStatus.value = 'Loading preferences...';
      final gridCols = await storage.getGridColumns();
      if (gridCols != null) {
        loadedGridColumns.value = gridCols;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 4: Load saved audio device
      initStatus.value = 'Loading audio device...';
      savedAudioDeviceName = await storage.getSavedAudioDeviceName();
      savedAudioDeviceId = await storage.getSavedAudioDeviceId();
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 5: Wait for sidecar to be ready
      initStatus.value = 'Connecting to audio engine...';

      // Listen to sidecar initialization
      ever(sidecarService.isInitialized, (bool initialized) {
        if (initialized && !isComplete.value) {
          _completeInitialization();
        }
      });

      // Also listen to status text updates for better UX
      ever(sidecarService.initStatusText, (String status) {
        initStatus.value = status;
      });

      // If already initialized (e.g., hot reload), complete immediately
      if (sidecarService.isInitialized.value) {
        _completeInitialization();
      }
    } catch (e) {
      initStatus.value = 'Error: $e';
      // Still try to navigate after a delay
      Future.delayed(const Duration(seconds: 3), () {
        Get.offAllNamed(Routes.home);
      });
    }
  }

  void _completeInitialization() {
    isComplete.value = true;
    initStatus.value = 'Ready!';

    // Small delay to show "Ready!" message
    Future.delayed(const Duration(milliseconds: 800), () {
      // Navigate to home and pass the loaded data
      Get.offAllNamed(
        Routes.home,
        arguments: {
          'groups': loadedGroups.toList(),
          'faders': loadedFaders.toList(),
          'gridColumns': loadedGridColumns.value,
          'savedAudioDeviceName': savedAudioDeviceName,
          'savedAudioDeviceId': savedAudioDeviceId,
        },
      );
    });
  }
}
