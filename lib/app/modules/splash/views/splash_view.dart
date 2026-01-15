import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/splash_controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Hero(
              tag: 'app_logo',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/logo/512-mac.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // App Name
            Text(
              'PadVibe',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Professional Audio Bus Engine',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 80),
            // Status indicator - minimal and clean
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  Obx(() {
                    final isComplete = controller.isComplete.value;
                    final statusText = controller.initStatus.value;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: isComplete
                              ? Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Colors.green.shade400,
                                )
                              : CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.primary,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            statusText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                  // Subtle progress bar
                  Obx(() {
                    final isComplete = controller.isComplete.value;
                    return AnimatedOpacity(
                      opacity: isComplete ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Error display
            Obx(() {
              final error = controller.sidecarService.lastError.value;
              if (error.isNotEmpty) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }
}
