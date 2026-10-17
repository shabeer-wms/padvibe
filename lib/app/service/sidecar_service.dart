import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:padvibe/app/core/logging/app_log.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Launches and supervises the Python sidecar (audio + MIDI engine) and keeps
/// a WebSocket to it alive.
///
/// - Packaged builds run the one-dir bundle shipped next to the app; dev
///   builds fall back to `python3 sidecar/midi_server.py`.
/// - If the socket drops while the process is alive, it reconnects with
///   backoff. If the process dies, it is restarted with backoff (max 5 tries).
class SidecarService extends GetxService {
  static const _maxRestarts = 5;
  static const _maxReconnectsBeforeRestart = 20;

  final sidecarStatus = 'Not Started'.obs;
  final wsConnectionStatus = 'Disconnected'.obs;
  final lastError = ''.obs;
  final sidecarPid = Rxn<int>();

  String get logFilePath => AppLog.path;

  // Initialization progress for splash screen
  final initStatusText = 'Initializing...'.obs;
  final isInitialized = false.obs;

  WebSocketChannel? _channel;
  Process? _pythonProcess;
  bool _isServerReady = false;
  bool _disposed = false;
  int _discoveredPort = 8765; // Default port
  int _restartCount = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _restartTimer;
  Timer? _heartbeat;

  // High-frequency traffic is counted and summarised by the heartbeat rather
  // than logged line by line.
  static const _noisyIn = {'audio_levels', 'midi_message'};
  static const _noisyOut = {
    'set_volume',
    'set_master_volume',
    'set_routing',
    'set_filter',
  };
  final Map<String, int> _noisyCounts = {};

  int get lastDiscoveredPort => _discoveredPort;

  // Registered message handlers: type -> callback
  final Map<String, List<Function(Map<String, dynamic>)>> _handlers = {};

  @override
  void onInit() {
    super.onInit();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      _log(
        'heartbeat: rss=${ProcessInfo.currentRss ~/ 1048576}MB '
        'maxRss=${ProcessInfo.maxRss ~/ 1048576}MB '
        'sidecar=${sidecarStatus.value} ws=${wsConnectionStatus.value} '
        'pid=${sidecarPid.value} traffic(last 60s)=$_noisyCounts',
      );
      _noisyCounts.clear();
    });
    _startPythonSidecar();
  }

  Future<void> _log(String message) async => AppLog.log('sidecar', message);

  @override
  void onClose() {
    _disposed = true;
    _log('SidecarService closing');
    _heartbeat?.cancel();
    _reconnectTimer?.cancel();
    _restartTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _stopPythonSidecar();
    super.onClose();
  }

  void registerHandler(String type, Function(Map<String, dynamic>) handler) {
    if (!_handlers.containsKey(type)) {
      _handlers[type] = [];
    }
    _handlers[type]!.add(handler);
  }

  void unregisterHandler(String type, Function(Map<String, dynamic>) handler) {
    if (_handlers.containsKey(type)) {
      _handlers[type]!.remove(handler);
    }
  }

  /// Finds what to launch: the packaged one-dir bundle, or (dev) the Python
  /// script. Returns null when neither exists.
  Future<({String exe, List<String> args})?> _resolveSidecar() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final sep = Platform.pathSeparator;
    final binary = Platform.isWindows ? 'midi_server.exe' : 'midi_server';

    // Packaged layout (see scripts/bundle_sidecar_macos.sh and the CMake install rules):
    //   macOS:          PadVibe.app/Contents/Resources/sidecar/midi_server
    //   Windows/Linux:  <bundle>/sidecar/midi_server[.exe]
    final packaged = Platform.isMacOS
        ? '${exeDir.parent.path}/Resources/sidecar/$binary'
        : '${exeDir.path}${sep}sidecar$sep$binary';
    await _log('Checking path: $packaged');
    if (await File(packaged).exists()) {
      return (exe: packaged, args: <String>[]);
    }

    // Development fallback: run the script with the system Python.
    final scripts = [
      if (Platform.isMacOS)
        '${exeDir.parent.path}/Frameworks/App.framework/Resources/flutter_assets/sidecar/midi_server.py',
      '${exeDir.path}${sep}data${sep}flutter_assets${sep}sidecar${sep}midi_server.py',
      'sidecar/midi_server.py',
    ];
    for (final script in scripts) {
      if (await File(script).exists()) {
        await _log('Packaged sidecar not found; using Python script: $script');
        return (exe: Platform.isWindows ? 'python' : 'python3', args: [script]);
      }
    }
    return null;
  }

  /// Kills a leftover sidecar still holding port 8765 (e.g. after the app was
  /// force-quit). Only our own process is killed; anything else is left alone
  /// since the sidecar can bind the next free port.
  Future<void> _killStaleSidecar() async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    try {
      final lsof = await Process.run(
        Platform.isMacOS ? '/usr/sbin/lsof' : 'lsof',
        ['-t', '-i:8765', '-sTCP:LISTEN'],
      );
      for (final pidStr in lsof.stdout.toString().trim().split('\n')) {
        if (pidStr.isEmpty) continue;
        final ps = await Process.run('ps', ['-p', pidStr, '-o', 'command=']);
        if (ps.stdout.toString().contains('midi_server')) {
          await _log('Killing stale sidecar $pidStr using port 8765');
          initStatusText.value = 'Terminating stale process $pidStr...';
          await Process.run('kill', ['-9', pidStr]);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      _log('Error cleaning up stale sidecar: $e');
    }
  }

  Future<void> _startPythonSidecar() async {
    if (_disposed) return;
    await _log('Starting Python Sidecar...');
    initStatusText.value = 'Cleaning up previous processes...';
    sidecarStatus.value = 'Starting';
    lastError.value = '';

    await _killStaleSidecar();

    initStatusText.value = 'Locating Sidecar binary...';
    try {
      final cmd = await _resolveSidecar();
      if (cmd == null) {
        throw Exception('Could not locate sidecar binary or python script.');
      }

      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('/bin/chmod', ['+x', cmd.exe]).catchError((e) {
          _log('Chmod failed: $e');
          return ProcessResult(0, 1, '', '');
        });
      }

      initStatusText.value = 'Starting Sidecar...';
      final proc = await Process.start(
        cmd.exe,
        cmd.args,
        // The sidecar exits when this pid disappears (its own parent is the
        // PyInstaller bootloader, which outlives a force-quit app).
        environment: {
          'PADVIBE_PARENT_PID': '$pid',
          'PYTHONUNBUFFERED': '1',
          // The sidecar writes its own rotating log and crash dump here.
          'PADVIBE_LOG_DIR': AppLog.directory,
        },
      );
      _pythonProcess = proc;
      sidecarPid.value = proc.pid;
      await _log('Sidecar process started with PID: ${proc.pid}');

      proc.exitCode.then((code) => _onSidecarExit(proc, code));

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) async {
            AppLog.log('sidecar-out', line);
            // The sidecar prints exactly this at the start of a line once it listens.
            if (line.startsWith('PORT_BIND_SUCCESS:')) {
              final port = int.tryParse(line.split(':').last.trim());
              if (port != null) {
                _discoveredPort = port;
                await _log('Detected sidecar port: $_discoveredPort');
                _reconnectAttempt = 0;
                _connectToWebSocket();
              }
            }
          });

      proc.stderr.transform(utf8.decoder).listen((data) async {
        AppLog.log('sidecar-err', data.trimRight());
        // Capture ANY stderr as potential error if sidecar is not initialized
        if (!isInitialized.value) {
          lastError.value = data.trim();
        }
      });

      // The very first launch after install is slow while the OS verifies the
      // bundled libraries; later launches take about a second.
      initStatusText.value =
          'Waiting for Sidecar to initialize (first launch can take ~15s)...';
    } catch (e, stackTrace) {
      await _log('Error starting Python sidecar: $e');
      await _log('Stack trace: $stackTrace');
      sidecarStatus.value = 'Error';
      final errorMsg =
          'Initialization Error: ${e.toString()}\nLog: ${AppLog.path}';
      initStatusText.value = errorMsg;
      lastError.value = errorMsg;
      _scheduleSidecarRestart();
    }
  }

  Future<void> _onSidecarExit(Process proc, int code) async {
    if (!identical(_pythonProcess, proc)) return; // superseded by a restart
    await _log('Sidecar process exited with code $code');
    _pythonProcess = null;
    sidecarPid.value = null;
    _isServerReady = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    wsConnectionStatus.value = 'Disconnected';
    if (_disposed) {
      sidecarStatus.value = 'Stopped';
      return;
    }
    sidecarStatus.value = code == 0 ? 'Stopped' : 'Error';
    if (code != 0) {
      final msg =
          'Sidecar crashed (Code $code). Check logs at: ${AppLog.path}';
      lastError.value = 'Crashed with code $code. Check log file.';
      initStatusText.value = msg;
      await _log('FATAL ERROR: $msg');
    }
    _scheduleSidecarRestart();
  }

  void _scheduleSidecarRestart() {
    if (_disposed) return;
    if (_restartCount >= _maxRestarts) {
      sidecarStatus.value = 'Error';
      initStatusText.value =
          'Sidecar keeps failing. Check logs at: ${AppLog.path}';
      _log('Giving up after $_maxRestarts restart attempts');
      return;
    }
    final delay = Duration(seconds: math.min(1 << _restartCount, 15));
    _restartCount++;
    _log('Restarting sidecar in ${delay.inSeconds}s (attempt $_restartCount)');
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, _startPythonSidecar);
  }

  /// Restarts the sidecar on demand (e.g. from Settings > Diagnostics).
  void restartSidecar() {
    _log('Manual sidecar restart requested');
    _restartCount = 0;
    _restartTimer?.cancel();
    final proc = _pythonProcess;
    if (proc != null) {
      proc.kill(); // the exit handler starts a fresh one
    } else {
      _startPythonSidecar();
    }
  }

  void shutdownSidecar() {
    send(jsonEncode({'command': 'shutdown'}));
  }

  void _stopPythonSidecar() {
    _log('Stopping Python Sidecar...');
    sidecarStatus.value = 'Stopped';
    shutdownSidecar();
    Future.delayed(const Duration(milliseconds: 100), () {
      _pythonProcess?.kill();
    });
  }

  Future<void> _connectToWebSocket() async {
    if (_disposed) return;
    final port = _discoveredPort;
    _log('Connecting to WebSocket on port $port...');
    initStatusText.value = 'Establishing WebSocket connection...';
    wsConnectionStatus.value = 'Connecting';

    try {
      // dart:io sends protocol-level pings and closes the socket when a pong
      // is missed, so a hung sidecar surfaces as onDone and triggers reconnect.
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
        pingInterval: const Duration(seconds: 10),
        connectTimeout: const Duration(seconds: 5),
      );
      await channel.ready;
      if (_disposed) {
        channel.sink.close();
        return;
      }

      _channel = channel;
      _reconnectAttempt = 0;
      _restartCount = 0;
      _isServerReady = true;
      wsConnectionStatus.value = 'Connected';
      sidecarStatus.value = 'Running';
      initStatusText.value = 'System Ready.';
      isInitialized.value = true;
      _log('WebSocket connected on port $port');

      channel.stream.listen(
        (message) => _handleWebSocketMessage(message as String),
        onDone: () => _onSocketLost(channel, null),
        onError: (Object error) => _onSocketLost(channel, error),
        cancelOnError: true,
      );
    } catch (e) {
      _log('Error connecting to WebSocket: $e');
      wsConnectionStatus.value = 'Error';
      if (sidecarStatus.value != 'Error') {
        lastError.value = e.toString();
      }
      _scheduleReconnect();
    }
  }

  void _onSocketLost(WebSocketChannel channel, Object? error) {
    if (!identical(channel, _channel)) return; // stale socket
    _log('WebSocket lost: ${error ?? 'closed'}');
    _channel = null;
    _isServerReady = false;
    wsConnectionStatus.value = error == null ? 'Disconnected' : 'Error';
    if (error != null) {
      lastError.value = error.toString();
    }
    _scheduleReconnect();
  }

  /// Reconnects with backoff (0.5s, 1s, 2s, 4s, then 5s) while the process is
  /// alive. If it never answers, kill it so the exit handler restarts it.
  void _scheduleReconnect() {
    if (_disposed || _pythonProcess == null) {
      return; // exit handler owns restarts
    }
    if (_reconnectAttempt >= _maxReconnectsBeforeRestart) {
      _log(
        'Sidecar unresponsive after $_reconnectAttempt reconnects; restarting it',
      );
      _pythonProcess?.kill();
      return;
    }
    final delay = Duration(
      milliseconds: math.min(500 * (1 << math.min(_reconnectAttempt, 4)), 5000),
    );
    _reconnectAttempt++;
    initStatusText.value = 'Reconnecting to sidecar ($_reconnectAttempt)...';
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connectToWebSocket);
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      if (_noisyIn.contains(type)) {
        _count('in:$type');
      } else {
        _log('<- $type${_detail(data)}');
      }

      // Dispatch to handlers
      if (_handlers.containsKey(type)) {
        for (var handler in _handlers[type]!) {
          handler(data);
        }
      }
    } catch (e) {
      _log('Error parsing WebSocket message: $e');
    }
  }

  void send(String message) {
    final command =
        RegExp(r'"command"\s*:\s*"(\w+)"').firstMatch(message)?.group(1) ?? '?';
    if (_channel == null || !_isServerReady) {
      _log(
        'DROPPED command $command: sidecar not connected '
        '(ws=${wsConnectionStatus.value}, process=${sidecarStatus.value})',
      );
      return;
    }
    if (_noisyOut.contains(command)) {
      _count('out:$command');
    } else {
      _log('-> ${message.length > 300 ? '${message.substring(0, 300)}…' : message}');
    }
    try {
      _channel!.sink.add(message);
    } catch (e) {
      _log('Error sending $command to WebSocket: $e');
      _isServerReady = false;
    }
  }

  void _count(String key) => _noisyCounts[key] = (_noisyCounts[key] ?? 0) + 1;

  /// The interesting fields of a message, without bulky payloads.
  String _detail(Map data) {
    final parts = <String>[
      for (final k in ['stream_id', 'message', 'file_path', 'duration_seconds', 'device_id'])
        if (data.containsKey(k)) '$k=${data[k]}',
      for (final k in ['devices', 'data'])
        if (data[k] is List) '$k[${(data[k] as List).length}]',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }
}
