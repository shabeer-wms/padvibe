import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PadVibe/app/modules/home/controllers/home_controller.dart';
import 'package:PadVibe/app/service/audio_player_service.dart';
import 'package:PadVibe/app/service/storage_service.dart';
import 'package:get/get.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;

class LocalApiService extends GetxService {
  final StorageService _storage = Get.find<StorageService>();

  // We need lazy access to HomeController to avoid circular dependency during init if possible,
  // or just find it when needed.
  HomeController? _homeController;
  AudioPlayerService? _audioService;

  HttpServer? _server;
  Timer? _webhookTimer;

  final RxString remoteEndpointUrl = ''.obs;
  final RxInt webhookIntervalMs = 1000.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    _startServer();
    _startWebhookTimer();
  }

  @override
  void onClose() {
    _stopServer();
    _stopWebhookTimer();
    super.onClose();
  }

  Future<void> _loadSettings() async {
    final url = await _storage.getRemoteEndpointUrl();
    if (url != null) remoteEndpointUrl.value = url;

    final interval = await _storage.getWebhookInterval();
    if (interval != null) webhookIntervalMs.value = interval;
  }

  Future<void> updateRemoteEndpoint(String url) async {
    remoteEndpointUrl.value = url;
    await _storage.saveRemoteEndpointUrl(url);
  }

  Future<void> updateWebhookInterval(int interval) async {
    webhookIntervalMs.value = interval;
    await _storage.saveWebhookInterval(interval);
    _startWebhookTimer(); // restart with new interval
  }

  // --- Server Logic ---

  Future<void> _startServer() async {
    final router = Router();

    router.get('/api/v1/state', _handleGetState);

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    try {
      // Listen on any interface (0.0.0.0) or loopback?
      // 0.0.0.0 allows other devices on LAN to access it, which is often desired for "local API".
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 9696);
      print('Local API Server listening on port ${_server!.port}');
    } catch (e) {
      print('Failed to start Local API Server: $e');
    }
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware _corsMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        if (request.method == 'OPTIONS') {
          return Response.ok(
            '',
            headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type',
            },
          );
        }
        return null;
      },
      responseHandler: (response) {
        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type',
          },
        );
      },
    );
  }

  Response _handleGetState(Request request) {
    final json = _generateStateJson();
    return Response.ok(
      jsonEncode(json),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // --- Webhook Logic ---

  void _startWebhookTimer() {
    _webhookTimer?.cancel();
    _webhookTimer = Timer.periodic(
      Duration(milliseconds: webhookIntervalMs.value),
      (_) => _sendWebhook(),
    );
  }

  void _stopWebhookTimer() {
    _webhookTimer?.cancel();
    _webhookTimer = null;
  }

  Future<void> _sendWebhook() async {
    final url = remoteEndpointUrl.value;
    if (url.isEmpty) {
      print('Webhook URL empty');
      return;
    }

    try {
      print('Sending webhook to $url...');
      final uri = Uri.parse(url);
      final json = _generateStateJson();

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(json),
          )
          .timeout(const Duration(seconds: 2));
      print('Webhook response: ${response.statusCode}');
    } catch (e) {
      print('Webhook failed: $e');
    }
  }

  // --- State Generation ---

  Map<String, dynamic> _generateStateJson() {
    _homeController ??= Get.find<HomeController>();
    _audioService ??= Get.find<AudioPlayerService>();

    final c = _homeController!;
    final a = _audioService!;

    // Global
    final global = {
      'remaining_timer_seconds': c.remainingSeconds.value,
      'estimated_completion_timestamp': DateTime.now()
          .add(
            Duration(milliseconds: (c.remainingSeconds.value * 1000).toInt()),
          )
          .toIso8601String(),
      'master_volume_levels': {'left': a.masterRmsL, 'right': a.masterRmsR},
      'active_group': {
        'index': c.currentGroupIndex.value,
        'id': c.groups.isNotEmpty
            ? c.groups[c.currentGroupIndex.value].id
            : 'default',
        'name': c.groups.isNotEmpty
            ? c.groups[c.currentGroupIndex.value].name
            : 'Default',
      },
    };

    // Pads
    final padsList = <Map<String, dynamic>>[];
    for (int i = 0; i < c.pads.length; i++) {
      final p = c.pads[i];
      final path = p.path;

      String state = 'empty';
      double pos = 0.0;
      double dur = 0.0;
      double progress = 0.0;

      if (path != null) {
        if (a.isPlaying(path)) {
          state = a.isPaused(path) ? 'paused' : 'playing';
        } else {
          state = 'stopped';
        }

        // Only get details if active/valid
        // But we want details even if stopped?
        // AudioService.getLength returns 0 if not active handle.
        // So we might not get duration if stopped.
        // For now, rely on AudioService.

        final d = a.getLength(path);
        if (d.inMilliseconds > 0) {
          dur = d.inMilliseconds / 1000.0;
          final pTime = a.getPosition(path);
          pos = pTime.inMilliseconds / 1000.0;
          progress = pos / dur;
        }
      }

      padsList.add({
        'id': i,
        'name': p.name,
        'color': p.color,
        'file_path': path,
        'keyboard_shortcut': p.keyboardShortcut,
        'settings': {'is_looping': p.isLooping},
        'playback': {
          'state': state,
          'position_seconds': pos,
          'duration_seconds': dur,
          'progress_percent': progress,
        },
      });
    }

    return {'global': global, 'pads': padsList};
  }
}
