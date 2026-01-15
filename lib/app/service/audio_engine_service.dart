import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'sidecar_service.dart';

class AudioDevice {
  final int id;
  final String name;
  final String hostapi;
  final int channels;

  AudioDevice({
    required this.id,
    required this.name,
    required this.hostapi,
    required this.channels,
  });
}

class AudioEngineService extends GetxService {
  final SidecarService _sidecar = Get.find<SidecarService>();

  final audioDevices = <AudioDevice>[].obs;

  // Stream for audio events (started/stopped) to help AudioPlayerService sync
  final _audioEventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get audioEventStream =>
      _audioEventStreamController.stream;

  @override
  void onInit() {
    super.onInit();
    _sidecar.registerHandler('audio_device_list', _handleAudioDeviceList);
    _sidecar.registerHandler('audio_started', _handleAudioEvent);
    _sidecar.registerHandler('audio_stopped', _handleAudioEvent);
    _sidecar.registerHandler('all_audio_stopped', _handleAudioEvent);
    _sidecar.registerHandler('audio_finished', _handleAudioEvent);
    _sidecar.registerHandler('audio_loop_updated', _handleAudioEvent);
    _sidecar.registerHandler('waveform_data', _handleAudioEvent);

    // Refresh devices when connected
    ever(_sidecar.wsConnectionStatus, (status) {
      if (status == 'Connected') {
        refreshAudioDevices();
      }
    });
    
    // Also try immediately in case we are already connected (hot reload)
    if (_sidecar.wsConnectionStatus.value == 'Connected') {
      refreshAudioDevices();
    }
  }

  @override
  void onClose() {
    _sidecar.unregisterHandler('audio_device_list', _handleAudioDeviceList);
    _sidecar.unregisterHandler('audio_started', _handleAudioEvent);
    _sidecar.unregisterHandler('audio_stopped', _handleAudioEvent);
    _sidecar.unregisterHandler('all_audio_stopped', _handleAudioEvent);
    _sidecar.unregisterHandler('audio_finished', _handleAudioEvent);
    _sidecar.unregisterHandler('audio_loop_updated', _handleAudioEvent);
    _sidecar.unregisterHandler('waveform_data', _handleAudioEvent);
    _audioEventStreamController.close();
    super.onClose();
  }

  void refreshAudioDevices() {
    print('Refreshing Audio devices via Sidecar...');
    _sidecar.send(jsonEncode({'command': 'list_audio_devices'}));
  }

  void requestWaveform(String filePath, {int points = 100}) {
    _sidecar.send(
      jsonEncode({
        'command': 'get_waveform',
        'file_path': filePath,
        'points': points,
      }),
    );
  }

  void playAudio(
    String filePath, {
    int? deviceId,
    bool loop = false,
    double volume = 1.0,
    List<int>? outputChannels,
    String filterType = 'none',
    double filterFrequency = 20000.0,
  }) {
    _sidecar.send(
      jsonEncode({
        'command': 'play_audio',
        'file_path': filePath,
        'device_id': deviceId,
        'loop': loop,
        'volume': volume,
        'output_channels': outputChannels,
        'filter_type': filterType,
        'filter_frequency': filterFrequency,
      }),
    );
  }

  void stopAudio(int streamId) {
    _sidecar.send(jsonEncode({'command': 'stop_audio', 'stream_id': streamId}));
  }

  void stopAllAudio() {
    _sidecar.send(jsonEncode({'command': 'stop_all_audio'}));
  }

  void setVolume(int streamId, double volume) {
    _sidecar.send(
      jsonEncode({
        'command': 'set_volume',
        'stream_id': streamId,
        'volume': volume,
      }),
    );
  }

  void setLooping(int streamId, bool loop) {
    _sidecar.send(
      jsonEncode({
        'command': 'set_looping',
        'stream_id': streamId,
        'loop': loop,
      }),
    );
  }

  void setRouting(int streamId, List<int>? outputChannels) {
    _sidecar.send(
      jsonEncode({
        'command': 'set_routing',
        'stream_id': streamId,
        'output_channels': outputChannels,
      }),
    );
  }

  void setFilter(int streamId, String type, double frequency) {
    _sidecar.send(
      jsonEncode({
        'command': 'set_filter',
        'stream_id': streamId,
        'filter_type': type,
        'frequency': frequency,
      }),
    );
  }

  void seekAudio(int streamId, double positionSeconds) {
    _sidecar.send(
      jsonEncode({
        'command': 'seek_audio',
        'stream_id': streamId,
        'position': positionSeconds,
      }),
    );
  }

  void _handleAudioDeviceList(Map<String, dynamic> data) {
    final List<dynamic> devList = data['devices'];
    audioDevices.assignAll(
      devList
          .map(
            (d) => AudioDevice(
              id: d['id'],
              name: d['name'],
              hostapi: d['hostapi'],
              channels: d['channels'],
            ),
          )
          .toList(),
    );
    print('Audio Devices found: ${audioDevices.length}');
  }

  void _handleAudioEvent(Map<String, dynamic> data) {
    _audioEventStreamController.add(data);
  }
}
