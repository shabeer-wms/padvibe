import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-wide logging: one file per launch in `<app support>/logs/padvibe_<ms>.log`.
///
/// Every line is written and flushed immediately (not buffered), so the file
/// is complete even if the app is killed or crashes a moment later. The
/// sidecar writes its own files next to it (sidecar_engine.log and, for native
/// crashes, sidecar_crash.log) and its output is also copied into this file.
class AppLog {
  static const _keepFiles = 30;

  static RandomAccessFile? _file;
  static String? _path;
  static String? _dir;

  static String get path => _path ?? 'No log file';
  static String get directory => _dir ?? '';

  static Future<void> init() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'logs'));
      await dir.create(recursive: true);
      _dir = dir.path;
      await _prune(dir);
      final file = File(
        p.join(
          dir.path,
          'padvibe_${DateTime.now().millisecondsSinceEpoch}.log',
        ),
      );
      _file = file.openSync(mode: FileMode.append);
      _path = file.path;
    } catch (e) {
      debugPrint('AppLog: file logging unavailable: $e');
    }
    log('app', '=== PadVibe started ===');
    log(
      'app',
      'pid=$pid os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    log(
      'app',
      'dart=${Platform.version.split(' ').first} locale=${Platform.localeName} cpus=${Platform.numberOfProcessors}',
    );
    log('app', 'executable=${Platform.resolvedExecutable}');
    log('app', 'log file=$_path');
  }

  static void log(String tag, String message) {
    final line = '[${DateTime.now().toIso8601String()}] [$tag] $message';
    debugPrint(line);
    try {
      _file?.writeStringSync('$line\n');
      _file?.flushSync();
    } catch (_) {
      // Logging must never take the app down.
    }
  }

  static void error(
    String tag,
    Object error,
    StackTrace? stack, {
    String? context,
  }) {
    log(
      '$tag:ERROR',
      '${context != null ? '$context: ' : ''}$error\n${stack ?? StackTrace.current}',
    );
  }

  /// Routes every uncaught Flutter, platform and zone error to the log, and
  /// records process signals and app lifecycle changes (sleep, wake, quit).
  static void installHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'flutter',
        details.exception,
        details.stack,
        context: details.context?.toString(),
      );
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      error('platform', e, st);
      return true; // handled: keep running
    };

    if (Platform.isMacOS || Platform.isLinux) {
      for (final signal in [
        ProcessSignal.sigterm,
        ProcessSignal.sigint,
        ProcessSignal.sighup,
      ]) {
        signal.watch().listen((_) {
          log('app', 'Received $signal; exiting');
          exit(0);
        });
      }
    }
    WidgetsBinding.instance.addObserver(_LifecycleLogger());
  }

  static Future<void> _prune(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                RegExp(r'(padvibe|sidecar)_\d+\.log$').hasMatch(e.path),
          )
          .cast<File>()
          .toList();
      files.sort(
        (a, b) => b.path.compareTo(a.path),
      ); // newest first (ms timestamp)
      for (final old in files.skip(_keepFiles)) {
        await old.delete();
      }
    } catch (_) {}
  }
}

class _LifecycleLogger with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      AppLog.log('lifecycle', state.name);

  @override
  void didHaveMemoryPressure() =>
      AppLog.log('lifecycle', 'MEMORY PRESSURE reported by the OS');

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null) {
      final s = view.physicalSize / view.devicePixelRatio;
      AppLog.log(
        'window',
        'size=${s.width.round()}x${s.height.round()} dpr=${view.devicePixelRatio}',
      );
    }
  }

  @override
  void didChangePlatformBrightness() => AppLog.log(
    'lifecycle',
    'brightness=${WidgetsBinding.instance.platformDispatcher.platformBrightness.name}',
  );
}
