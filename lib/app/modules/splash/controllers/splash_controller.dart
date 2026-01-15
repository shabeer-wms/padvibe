import 'package:get/get.dart';
import '../../../routes/app_pages.dart';
import '../../../service/sidecar_service.dart';

class SplashController extends GetxController {
  final sidecarService = Get.find<SidecarService>();

  @override
  void onInit() {
    super.onInit();

    // Listen to initialization status
    ever(sidecarService.isInitialized, (bool initialized) {
      if (initialized) {
        // Wait a small bit to show "System Check Complete"
        Future.delayed(const Duration(seconds: 1), () {
          Get.offAllNamed(Routes.HOME);
        });
      }
    });
  }

  @override
  void onReady() {
    super.onReady();
    // If already initialized (e.g. hot reload), just go home
    if (sidecarService.isInitialized.value) {
      Get.offAllNamed(Routes.HOME);
    }
  }
}
