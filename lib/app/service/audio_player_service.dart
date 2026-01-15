import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:collection/collection.dart';

import 'package:get/get.dart';
import 'package:PadVibe/app/service/audio_engine_service.dart';

// --- Types Compatibility ---
typedef SoundHandle = int;

class PlaybackDevice {
  final int id;
  final String name;
  final bool isDefault;

  PlaybackDevice({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

// --- Active Stream Context ---
class ActiveStream {
  final int streamId;
  final String path;
  final int? deviceId; // Captured device ID
  DateTime startTime;
  final double durationSeconds;
  bool isLooping;
  bool isPaused = false;
  Duration pausedAt = Duration.zero;

  ActiveStream({
    required this.streamId,
    required this.path,
    this.deviceId,
    required this.startTime,
    required this.durationSeconds,
    this.isLooping = false,
  });
}

class AudioPlayerService extends GetxService {
  late final AudioEngineService _audioEngine;

  final isInitialized = false.obs;

  // Track active streams: streamId -> ActiveStream
  final Map<int, ActiveStream> _activeStreams = {};

  // Expose active handles (streamIds) for compatibility
  final RxList<SoundHandle> activeHandles = <SoundHandle>[].obs;

  // Track which path each active handle belongs to
  final Map<SoundHandle, String> _handlePath = {};

  // Track seek positions for inactive paths: path -> position (Duration)
  final Map<String, Duration> _inactiveSeekPositions = {};

  // Cached waveforms: path -> normalized amplitude data
  final Map<String, List<double>> _waveforms = {};
  final _waveformStreamController = StreamController<String>.broadcast();
  Stream<String> get waveformUpdates => _waveformStreamController.stream;

  // --- added: audio output device management ---
  final RxList<PlaybackDevice> outputDevices = <PlaybackDevice>[].obs;
  final Rxn<PlaybackDevice> selectedDevice = Rxn<PlaybackDevice>();
  // --- end added ---

  // --- added: expose master RMS levels for meters ---
  double masterRmsL = 0.0;
  double masterRmsR = 0.0;
  // --- end added ---

  StreamSubscription? _audioEventSub;

  @override
  void onInit() {
    super.onInit();
    _audioEngine = Get.find<AudioEngineService>();
    _initialize();
  }

  Future<void> _initialize() async {
    // Listen to Sidecar events
    _audioEventSub = _audioEngine.audioEventStream.listen((event) {
      final type = event['type'];
      if (type == 'audio_started') {
        _handleAudioStarted(event);
      } else if (type == 'audio_stopped' || type == 'audio_finished') {
        _handleAudioStopped(event);
      } else if (type == 'all_audio_stopped') {
        _handleAllAudioStopped();
      } else if (type == 'audio_loop_updated') {
        _handleAudioLoopUpdated(event);
      } else if (type == 'waveform_data') {
        _handleWaveformData(event);
      }
    });

    // Sync devices from Sidecar
    ever(_audioEngine.audioDevices, (List<AudioDevice> devices) {
      _updatePlaybackDevices(devices);
    });

    isInitialized.value = true;

    // Trigger initial refresh
    if (_audioEngine.audioDevices.isNotEmpty) {
      _updatePlaybackDevices(_audioEngine.audioDevices);
    } else {
      refreshOutputDevices();
    }
  }

  void _updatePlaybackDevices(List<AudioDevice> devices) {
    final mapped = devices
        .map(
          (d) => PlaybackDevice(
            id: d.id,
            name: d.name,
            isDefault: d.id == selectedDevice.value?.id, // Simple heuristic
          ),
        )
        .toList();

    outputDevices.assignAll(mapped);

    if (selectedDevice.value == null && mapped.isNotEmpty) {
      selectedDevice.value = mapped.first;
    }
  }

  void _handleAudioStarted(Map<String, dynamic> event) {
    final streamId = event['stream_id'] as int;
    final path = event['file_path'] as String;
    final duration = (event['duration_seconds'] as num?)?.toDouble() ?? 0.0;
    final loop = event['loop'] as bool? ?? false;
    final deviceId =
        event['device_id'] as int?; // Needs sidecar update to send this

    final stream = ActiveStream(
      streamId: streamId,
      path: path,
      deviceId: deviceId,
      startTime: DateTime.now(),
      durationSeconds: duration,
      isLooping: loop,
    );

    _activeStreams[streamId] = stream;
    _handlePath[streamId] = path;
    activeHandles.add(streamId);
  }

  void _handleAudioLoopUpdated(Map<String, dynamic> event) {
    final streamId = event['stream_id'] as int;
    final loop = event['loop'] as bool;
    final stream = _activeStreams[streamId];
    if (stream != null) {
      stream.isLooping = loop;
    }
  }

  void _handleWaveformData(Map<String, dynamic> event) {
    final path = event['file_path'] as String;
    final data = (event['data'] as List).cast<double>();
    _waveforms[path] = data;
    _waveformStreamController.add(path);
  }

  List<double>? getWaveform(String path) => _waveforms[path];

  void loadWaveform(String path) {
    if (_waveforms.containsKey(path)) return; // Already loaded
    _audioEngine.requestWaveform(path);
  }

  Future<void> setRouting(String path, List<int>? channels) async {
    final streams = _activeStreams.values.where((s) => s.path == path).toList();
    for (final s in streams) {
      _audioEngine.setRouting(s.streamId, channels);
    }
  }

  int? getDeviceIdForPath(String path) {
    final stream = _activeStreams.values.firstWhereOrNull(
      (s) => s.path == path,
    );
    return stream?.deviceId;
  }

  void _handleAudioStopped(Map<String, dynamic> event) {
    final streamId = event['stream_id'] as int;
    _removeStream(streamId);
  }

  void _handleAllAudioStopped() {
    _activeStreams.clear();
    _handlePath.clear();
    activeHandles.clear();
  }

  void _removeStream(int streamId) {
    _activeStreams.remove(streamId);
    _handlePath.remove(streamId);
    activeHandles.remove(streamId);
  }

  @override
  void onClose() {
    _audioEventSub?.cancel();
    stopAllSounds();
    super.onClose();
  }

  Future<void> loadSound(String path) async {
    // No-op for sidecar streaming
  }

  Future<void> playSound(
    String path, {
    bool loop = false,
    int? deviceId,
    List<int>? outputChannels,
    String filterType = 'none',
    double filterFrequency = 20000.0,
  }) async {
    await ensureInitialized();
    // Default to selected device, or use the explicit deviceId passed
    final targetDeviceId = deviceId ?? selectedDevice.value?.id;
    _audioEngine.playAudio(
      path,
      deviceId: targetDeviceId,
      loop: loop,
      outputChannels: outputChannels,
      filterType: filterType,
      filterFrequency: filterFrequency,
    );

    // Apply stored seek position if it exists
    if (_inactiveSeekPositions.containsKey(path)) {
      final pos = _inactiveSeekPositions.remove(path)!;
      Future.delayed(const Duration(milliseconds: 100), () => seek(path, pos));
    }
  }

  Future<void> setFilter(String path, String type, double frequency) async {
    final streams = _activeStreams.values.where((s) => s.path == path).toList();
    for (final s in streams) {
      _audioEngine.setFilter(s.streamId, type, frequency);
    }
  }

  int getDeviceChannels(int? deviceId) {
    if (deviceId == null) return 2; // Default assumption
    // Find device in audio engine list
    final device = _audioEngine.audioDevices.firstWhereOrNull(
      (d) => d.id == deviceId,
    );
    return device?.channels ?? 2;
  }

  Future<void> stopAllSounds() async {
    if (!isInitialized.value) return;
    _audioEngine.stopAllAudio();
    // Optimistic clear to update UI immediately
    _activeStreams.clear();
    _handlePath.clear();
    activeHandles.clear();
  }

  Future<void> clearAll() async {
    await stopAllSounds();
  }

  Float32List getMasterFft() {
    // Mock FFT for now
    return Float32List(256);
  }

  double getRemainingTime() {
    if (!isInitialized.value || activeHandles.isEmpty) return 0.0;

    double maxRemaining = 0.0;
    final now = DateTime.now();

    for (final streamId in activeHandles) {
      final stream = _activeStreams[streamId];
      if (stream == null) continue;

      // Calculate elapsed
      final elapsed = now.difference(stream.startTime).inMilliseconds / 1000.0;
      double remaining;

      if (stream.isLooping && stream.durationSeconds > 0) {
        remaining = stream.durationSeconds - (elapsed % stream.durationSeconds);
      } else {
        remaining = stream.durationSeconds - elapsed;
      }

      if (remaining > maxRemaining) {
        maxRemaining = remaining;
      }
    }
    return maxRemaining > 0 ? maxRemaining : 0.0;
  }

  double? getRemainingFractionForPath(String path) {
    if (!isInitialized.value || activeHandles.isEmpty) return null;

    final now = DateTime.now();
    double? best;

    for (final stream in _activeStreams.values) {
      if (stream.path != path) continue;
      if (stream.durationSeconds <= 0) continue;

      final elapsed = now.difference(stream.startTime).inMilliseconds / 1000.0;
      double remaining;

      if (stream.isLooping) {
        remaining = stream.durationSeconds - (elapsed % stream.durationSeconds);
      } else {
        remaining = stream.durationSeconds - elapsed;
      }

      if (remaining <= 0 && !stream.isLooping) continue; // Finished or invalid

      final frac = remaining / stream.durationSeconds;
      if (best == null || frac > best) best = frac;
    }
    return best;
  }

  Future<void> ensureInitialized() async {
    if (!isInitialized.value) {
      // wait a bit?
    }
  }

  Future<void> stopPath(String path) async {
    // Find all streams with this path
    final streamIds = _activeStreams.values
        .where((s) => s.path == path)
        .map((s) => s.streamId)
        .toList();

    for (final id in streamIds) {
      _audioEngine.stopAudio(id);
      _removeStream(id); // Optimistic UI update
    }
  }

  Future<void> unloadPath(String path) async {
    await stopPath(path);
  }

  bool isPlaying(String path) {
    return _activeStreams.values.any((s) => s.path == path);
  }

  Future<void> preloadSounds(Iterable<String> paths) async {
    // No-op
  }

  // --- Pause/Resume not fully supported by Python sidecar yet, implemented as Stop/Play for now ---
  // Or just no-op if complex
  Future<void> pausePath(String path) async {
    await stopPath(path); // Simplification: Pause = Stop
  }

  Future<void> resumePath(String path) async {
    // Simplification: Resume = Play from start
    playSound(path);
  }

  bool isPaused(String path) {
    return false;
  }

  Duration getPosition(String path) {
    final now = DateTime.now();
    for (final stream in _activeStreams.values) {
      if (stream.path == path) {
        final ms = now.difference(stream.startTime).inMilliseconds;
        if (stream.isLooping && stream.durationSeconds > 0) {
          final loopMs = (stream.durationSeconds * 1000).toInt();
          return Duration(milliseconds: ms % loopMs);
        }
        return Duration(milliseconds: ms);
      }
    }
    // Return stored seek position if available
    return _inactiveSeekPositions[path] ?? Duration.zero;
  }

  Duration getLength(String path) {
    for (final stream in _activeStreams.values) {
      if (stream.path == path) {
        return Duration(milliseconds: (stream.durationSeconds * 1000).toInt());
      }
    }
    return Duration.zero;
  }

  Future<void> setLooping(String path, bool loop) async {
    // Find all streams with this path
    final streams = _activeStreams.values.where((s) => s.path == path).toList();

    for (final s in streams) {
      _audioEngine.setLooping(s.streamId, loop);
    }
  }

  Future<void> seek(String path, Duration position) async {
    final posSec = position.inMilliseconds / 1000.0;

    // Find all streams with this path
    final streams = _activeStreams.values.where((s) => s.path == path).toList();

    if (streams.isEmpty) {
      // Not playing, store position for later
      _inactiveSeekPositions[path] = position;
      return;
    }

    for (final s in streams) {
      _audioEngine.seekAudio(s.streamId, posSec);

      // Update local startTime so progress calculations remain accurate
      // startTime = now - position
      final now = DateTime.now();
      s.startTime = now.subtract(position);
    }
  }

  List<double> getMasterLevels() {
    // Mock levels
    masterRmsL = 0.0;
    masterRmsR = 0.0;
    return [0.0, 0.0];
  }

  double getMasterLevel() {
    return 0.0;
  }

  Future<void> refreshOutputDevices() async {
    if (!isInitialized.value) return;
    _audioEngine.refreshAudioDevices();
  }

  Future<void> selectOutputDevice(PlaybackDevice device) async {
    selectedDevice.value = device;
    // We don't need to tell Python globally, we pass the ID on play.
  }
}
