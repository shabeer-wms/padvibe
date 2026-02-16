import "package:flutter/foundation.dart";
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:padvibe/app/core/utils/formatters.dart';
import 'package:padvibe/app/modules/home/controllers/home_controller.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:padvibe/app/service/storage_service.dart';
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
  final RxString localIp = '127.0.0.1'.obs;

  @override
  void onInit() {
    super.onInit();
    _getHostIp();
    _loadSettings();
    _startServer();
    _startWebhookTimer();
  }

  Future<void> _getHostIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            localIp.value = addr.address;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
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

    router.get('/state', _handleGetState);
    router.get('/levels', _handleGetLevels);
    router.get('/timer', _handleGetTimer);
    
    // Simple Control Endpoints
    router.get('/play/<index>', _handlePlay);
    router.get('/stop/<index>', _handleStop);
    router.get('/stop_all', _handleStopAll);
    router.get('/volume/master/<value>', _handleMasterVolume);
    router.get('/volume/pad/<index>/<value>', _handlePadVolume);
    router.get('/volume/fader/<index>/<value>', _handleFaderVolume);
    router.get('/seek/<index>/<value>', _handleSeekPad);
    router.get('/groups', _handleGetGroups);
    router.get('/groups/<index>/switch', _handleSwitchGroup);
    router.get('/faders', _handleGetFaders);
    
    // Device Management Endpoints
    router.get('/audio/devices', _handleGetAudioDevices);
    router.get('/audio/devices/<id>/select', _handleSelectAudioDevice);
    router.get('/midi/devices', _handleGetMidiDevices);
    router.get('/midi/devices/<name>/connect', _handleConnectMidiDevice);
    router.get('/midi/refresh', _handleRefreshMidiDevices);

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 9696);
      debugPrint('Local API Server listening on port ${_server!.port}');
    } catch (e) {
      debugPrint('Failed to start Local API Server: $e');
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

  Response _handleGetLevels(Request request) {
    _audioService ??= Get.find<AudioPlayerService>();
    final json = {
      'rms_l': _audioService!.masterRmsL,
      'rms_r': _audioService!.masterRmsR,
      'peak_l': _audioService!.masterPeakL.value,
      'peak_r': _audioService!.masterPeakR.value,
    };
    return Response.ok(
      jsonEncode(json),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleGetTimer(Request request) {
    _homeController ??= Get.find<HomeController>();
    final remaining = _homeController!.remainingSeconds.value;
    final json = {
      'remaining_seconds': remaining,
      'formatted_remaining_timer': Formatters.formatRemaining(remaining),
      'estimated_completion_timestamp': DateTime.now()
          .add(Duration(milliseconds: (remaining * 1000).toInt()))
          .toIso8601String(),
    };
    return Response.ok(
      jsonEncode(json),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handlePlay(Request request, String indexStr) async {
    final index = int.tryParse(indexStr);
    if (index == null) return Response.badRequest(body: 'Invalid index');
    _homeController ??= Get.find<HomeController>();
    await _homeController!.playPad(index);
    return Response.ok('OK');
  }

  Future<Response> _handleStop(Request request, String indexStr) async {
    final index = int.tryParse(indexStr);
    if (index == null) return Response.badRequest(body: 'Invalid index');
    _homeController ??= Get.find<HomeController>();
    await _homeController!.stopPad(index);
    return Response.ok('OK');
  }

  Future<Response> _handleStopAll(Request request) async {
    _homeController ??= Get.find<HomeController>();
    await _homeController!.stopAll();
    return Response.ok('OK');
  }

  Response _handleMasterVolume(Request request, String valueStr) {
    final value = double.tryParse(valueStr);
    if (value == null) return Response.badRequest(body: 'Invalid value');
    _homeController ??= Get.find<HomeController>();
    _homeController!.updateMasterVolume(value);
    return Response.ok('OK');
  }

  Response _handlePadVolume(Request request, String indexStr, String valueStr) {
    final index = int.tryParse(indexStr);
    final value = double.tryParse(valueStr);
    if (index == null || value == null) return Response.badRequest(body: 'Invalid parameters');
    _homeController ??= Get.find<HomeController>();
    _homeController!.updatePadVolume(index, value);
    return Response.ok('OK');
  }

  Response _handleFaderVolume(Request request, String indexStr, String valueStr) {
    final index = int.tryParse(indexStr);
    final value = double.tryParse(valueStr);
    if (index == null || value == null) return Response.badRequest(body: 'Invalid parameters');
    _homeController ??= Get.find<HomeController>();
    _homeController!.updateFaderVolume(index, value);
    return Response.ok('OK');
  }

  Future<Response> _handleSeekPad(Request request, String indexStr, String valueStr) async {
    final index = int.tryParse(indexStr);
    final value = double.tryParse(valueStr);
    if (index == null || value == null) return Response.badRequest(body: 'Invalid parameters');
    _homeController ??= Get.find<HomeController>();
    await _homeController!.seekPad(index, value);
    return Response.ok('OK');
  }

  Response _handleGetGroups(Request request) {
    _homeController ??= Get.find<HomeController>();
    final groups = _homeController!.groups.map((g) => {
      'id': g.id,
      'name': g.name,
      'pad_count': g.pads.length,
    }).toList();
    return Response.ok(
      jsonEncode(groups),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleSwitchGroup(Request request, String indexStr) {
    final index = int.tryParse(indexStr);
    if (index == null) return Response.badRequest(body: 'Invalid index');
    _homeController ??= Get.find<HomeController>();
    _homeController!.switchTab(index);
    return Response.ok('OK');
  }

  Response _handleGetFaders(Request request) {
    _homeController ??= Get.find<HomeController>();
    final faders = _homeController!.faders.map((f) => f.toJson()).toList();
    return Response.ok(
      jsonEncode(faders),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleGetAudioDevices(Request request) {
    _audioService ??= Get.find<AudioPlayerService>();
    final devices = _audioService!.outputDevices.map((d) => {
      'id': d.id,
      'name': d.name,
      'is_default': d.isDefault,
      'is_selected': d.id == _audioService!.selectedDevice.value?.id,
    }).toList();
    return Response.ok(
      jsonEncode(devices),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleSelectAudioDevice(Request request, String idStr) async {
    final id = int.tryParse(idStr);
    if (id == null) return Response.badRequest(body: 'Invalid ID');
    
    _audioService ??= Get.find<AudioPlayerService>();
    final device = _audioService!.outputDevices.firstWhereOrNull((d) => d.id == id);
    if (device == null) return Response.notFound('Device not found');
    
    _homeController ??= Get.find<HomeController>();
    await _homeController!.selectAudioDevice(device);
    return Response.ok('OK');
  }

  Response _handleGetMidiDevices(Request request) {
    final midiService = Get.find<MidiInterfaceService>();
    final devices = midiService.devices.map((d) => {
      'name': d.name,
      'id': d.id,
      'type': d.type,
      'connected': d.name == midiService.connectedDevice.value?.name,
    }).toList();
    return Response.ok(
      jsonEncode(devices),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleConnectMidiDevice(Request request, String name) {
    final midiService = Get.find<MidiInterfaceService>();
    final decodedName = Uri.decodeComponent(name);
    final device = midiService.devices.firstWhereOrNull((d) => d.name == decodedName);
    if (device == null) return Response.notFound('Device not found');
    
    midiService.connect(device);
    return Response.ok('OK');
  }

  Response _handleRefreshMidiDevices(Request request) {
    final midiService = Get.find<MidiInterfaceService>();
    midiService.refreshDevices();
    return Response.ok('OK');
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
      return;
    }

    try {
      debugPrint('Sending webhook to $url...');
      final uri = Uri.parse(url);
      final json = _generateStateJson();

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(json),
          )
          .timeout(const Duration(seconds: 2));
      debugPrint('Webhook response: ${response.statusCode}');
    } catch (e) {
      debugPrint('Webhook failed: $e');
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
      'formatted_remaining_timer': Formatters.formatRemaining(c.remainingSeconds.value),
      'estimated_completion_timestamp': DateTime.now()
          .add(
            Duration(milliseconds: (c.remainingSeconds.value * 1000).toInt()),
          )
          .toIso8601String(),
      'master_volume_levels': {'left': a.masterRmsL, 'right': a.masterRmsR},
      'master_volume': c.masterVolume.value,
      'active_group': {
        'index': c.currentGroupIndex.value,
        'id': c.groups.isNotEmpty
            ? c.groups[c.currentGroupIndex.value].id
            : 'default',
        'name': c.groups.isNotEmpty
            ? c.groups[c.currentGroupIndex.value].name
            : 'Default',
      },
      'audio_device': {
        'id': a.selectedDevice.value?.id,
        'name': a.selectedDevice.value?.name,
      },
    };

    // Pads
    final padsList = <Map<String, dynamic>>[];
    for (int i = 0; i < c.pads.length; i++) {
      final p = c.pads[i];
      if (p.isBackground) continue; // Skip background pads for API
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
