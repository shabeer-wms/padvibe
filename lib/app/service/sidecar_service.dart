import "package:flutter/foundation.dart";
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class SidecarService extends GetxService {
  File? _logFile;
  final sidecarStatus = 'Not Started'.obs;
  final wsConnectionStatus = 'Disconnected'.obs;
  final lastError = ''.obs;
  final sidecarPid = Rxn<int>();

  String get logFilePath => _logFile?.path ?? 'No log file';

  // Initialization progress for splash screen
  final initStatusText = 'Initializing...'.obs;
  final isInitialized = false.obs;

  WebSocketChannel? _channel;
  Process? _pythonProcess;
  bool _isServerReady = false;
  Timer? _healthCheckTimer;
  int _discoveredPort = 8765; // Default port

  int get lastDiscoveredPort => _discoveredPort;

  // Registered message handlers: type -> callback
  final Map<String, List<Function(Map<String, dynamic>)>> _handlers = {};

  @override
  void onInit() {
    super.onInit();
    _initLogging();
    _startPythonSidecar();
  }

  Future<void> _initLogging() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final logDir = Directory('${appDir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}/sidecar_${DateTime.now().millisecondsSinceEpoch}.log');
      await _log('=== PadVibe Sidecar Log ===');
      await _log('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      await _log('Executable: ${Platform.resolvedExecutable}');
    } catch (e) {
      debugPrint('Failed to initialize logging: $e');
    }
  }

  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';
    debugPrint(logMessage);
    try {
      await _logFile?.writeAsString('$logMessage\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write to log file: $e');
    }
  }

  @override
  void onClose() {
    _healthCheckTimer?.cancel();
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

  int _healthCheckFailCount = 0;

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckFailCount = 0;
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pythonProcess != null) {
        try {
          // Use 'kill -0' which is very fast and standard on Unix to check process existence
          final result = Process.runSync('kill', ['-0', '${_pythonProcess!.pid}']);
          if (result.exitCode != 0) {
            _healthCheckFailCount++;
            if (_healthCheckFailCount >= 2) {
              sidecarStatus.value = 'Stopped';
              lastError.value = 'Sidecar process terminated unexpectedly (Health check failed)';
            }
          } else {
            _healthCheckFailCount = 0;
            sidecarStatus.value = 'Running';
          }
        } catch (e) {
          // ignore or log
        }
      }
    });
  }

  Future<void> _startPythonSidecar() async {
    await _log('Starting Python Sidecar...');
    initStatusText.value = 'Cleaning up previous processes...';
    sidecarStatus.value = 'Starting';
    lastError.value = '';

    // Kill any process using port 8765
    try {
      await _log('Checking for processes using port 8765...');
      if (Platform.isMacOS || Platform.isLinux) {
        // Use absolute paths for reliability
        final lsofHeader = await Process.run('/usr/sbin/lsof', [
          '-t',
          '-i:8765',
        ]);
        final output = lsofHeader.stdout.toString().trim();
        if (output.isNotEmpty) {
          final pids = output.split('\n');
          for (final pid in pids) {
            if (pid.isNotEmpty) {
              await _log('Killing process $pid using port 8765');
              initStatusText.value = 'Terminating stale process $pid...';
              await Process.run('/bin/kill', ['-9', pid]);
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up port 8765: $e');
    }

    initStatusText.value = 'Locating Sidecar binary...';
    try {
      String? executablePath;

      if (Platform.isMacOS) {
        final binDir = File(Platform.resolvedExecutable).parent;
        final bundleDir = binDir.parent;
        final assetPath = 'sidecar/dist/midi_server';

        // Try multiple potential paths for robustness
        final potentialPaths = [
          '${bundleDir.path}/Frameworks/App.framework/Resources/flutter_assets/$assetPath',
          '${bundleDir.path}/Frameworks/App.framework/Versions/Current/Resources/flutter_assets/$assetPath',
          '${bundleDir.path}/Resources/flutter_assets/$assetPath',
        ];

        for (final path in potentialPaths) {
          await _log('Checking path: $path');
          if (await File(path).exists()) {
            executablePath = path;
            await _log('Found binary at: $path');
            break;
          }
        }
      } else {
        executablePath = 'sidecar/dist/midi_server';
      }

      if (executablePath != null && await File(executablePath).exists()) {
        await _log('Found sidecar binary at $executablePath');
        
        // Check if file is executable
        final stat = await File(executablePath).stat();
        await _log('Binary permissions: ${stat.modeString()}');
        
        initStatusText.value = 'Starting Sidecar binary...';

        if (Platform.isMacOS || Platform.isLinux) {
          try {
            final chmodResult = await Process.run('/bin/chmod', ['+x', executablePath]);
            await _log('chmod result: exit=${chmodResult.exitCode}');
          } catch (e) {
            await _log('Chmod failed: $e');
          }
        }

        // Verify code signature on macOS
        if (Platform.isMacOS) {
          try {
            final codesignResult = await Process.run('codesign', ['-dv', executablePath]);
            await _log('Code signing status: ${codesignResult.stderr}');
          } catch (e) {
            await _log('Code signature check failed: $e');
          }
        }

        try {
          _pythonProcess = await Process.start(
            executablePath,
            [],
            runInShell: false,
          );
        } catch (e) {
          await _log('FATAL: Failed to start sidecar binary: $e');
          throw Exception('Failed to start sidecar binary: $e');
        }
      } else {
        // Fallback Logic - Try to find the script in assets if binary missing
        debugPrint(
          'Sidecar binary not found. Trying python script fallback...',
        );
        initStatusText.value = 'Binary missing. Trying Python...';

        // Attempt to find absolute path to script in bundle
        String? scriptPath;
        if (Platform.isMacOS) {
          final binDir = File(Platform.resolvedExecutable).parent;
          final bundleDir = binDir.parent;
          final scriptRel = 'sidecar/midi_server.py';
          final potentialScripts = [
            '${bundleDir.path}/Frameworks/App.framework/Resources/flutter_assets/$scriptRel',
            '${bundleDir.path}/Resources/flutter_assets/$scriptRel',
          ];
          for (final p in potentialScripts) {
            if (await File(p).exists()) {
              scriptPath = p;
              break;
            }
          }
        } else {
          scriptPath = 'sidecar/midi_server.py';
        }

        if (scriptPath != null) {
          _pythonProcess = await Process.start('python3', [
            scriptPath,
          ], runInShell: true);
        } else {
          throw Exception(
            'Could not locate sidecar binary OR python script in bundle.',
          );
        }
      }

      if (_pythonProcess != null) {
        sidecarPid.value = _pythonProcess!.pid;
        await _log('Sidecar process started with PID: ${_pythonProcess!.pid}');
        await _log('Machine Architecture: ${Platform.version}'); // Logs some system info
        _startHealthCheck();

        // Monitor for unexpected exit
        _pythonProcess!.exitCode.then((code) async {
          await _log('Sidecar process exited with code $code');
          sidecarPid.value = null;
          if (code != 0) {
            sidecarStatus.value = 'Error';
            final msg = 'Sidecar crashed (Code $code). Check logs at: ${_logFile?.path}';
            lastError.value = 'Crashed with code $code. Check log file.';
            initStatusText.value = msg;
            await _log('FATAL ERROR: $msg');
          } else {
            sidecarStatus.value = 'Stopped';
          }
        });
      }

      _pythonProcess?.stdout.transform(utf8.decoder).listen((data) async {
        await _log('SIDECAR OUT: $data');
        if (data.contains('PORT_BIND_SUCCESS:')) {
          final portStr = data.split('PORT_BIND_SUCCESS:').last.trim();
          final port = int.tryParse(portStr);
          if (port != null) {
            _discoveredPort = port;
            await _log('Detected sidecar port: $_discoveredPort');
            _connectToWebSocket(port: _discoveredPort, retries: 20);
          }
        }
      });

      _pythonProcess?.stderr.transform(utf8.decoder).listen((data) async {
        await _log('SIDECAR ERR: $data');
        // Capture ANY stderr as potential error if sidecar is not initialized
        if (!isInitialized.value) {
          lastError.value = data.trim();
        }
      });

      initStatusText.value = 'Waiting for Sidecar to initialize...';
      // No longer using fixed delay, waiting for PORT_BIND_SUCCESS signal
    } catch (e, stackTrace) {
      await _log('Error starting Python sidecar: $e');
      await _log('Stack trace: $stackTrace');
      sidecarStatus.value = 'Error';
      final errorMsg = 'Initialization Error: ${e.toString()}\nLog: ${_logFile?.path}';
      initStatusText.value = errorMsg;
      lastError.value = errorMsg;
    }
  }

  void shutdownSidecar() {
    send(jsonEncode({'command': 'shutdown'}));
  }

  void _stopPythonSidecar() {
    debugPrint('Stopping Python Sidecar...');
    sidecarStatus.value = 'Stopped';
    shutdownSidecar();
    Future.delayed(const Duration(milliseconds: 100), () {
      _pythonProcess?.kill();
    });
  }

  Future<void> _connectToWebSocket({int? port, int retries = 5}) async {
    final int currentPort = port ?? _discoveredPort;
    debugPrint('Connecting to WebSocket on port $currentPort (Attempts left: $retries)...');
    initStatusText.value = 'Establishing WebSocket connection...';
    wsConnectionStatus.value = 'Connecting';

    try {
      final wsUrl = Uri.parse('ws://127.0.0.1:$currentPort');
      _channel = WebSocketChannel.connect(wsUrl);

      try {
        await _channel!.ready;
      } catch (e) {
        throw WebSocketChannelException('Connection failed: $e');
      }

      _channel?.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _isServerReady = false;
          wsConnectionStatus.value = 'Disconnected';
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _isServerReady = false;
          wsConnectionStatus.value = 'Error';
          lastError.value = error.toString();
          if (retries > 0) {
            initStatusText.value = 'Connection failed, retrying ($retries)...';
            Future.delayed(
              const Duration(seconds: 1),
              () => _connectToWebSocket(port: currentPort, retries: retries - 1),
            );
          }
        },
      );

      _isServerReady = true;
      wsConnectionStatus.value = 'Connected';
      initStatusText.value = 'WebSocket Connected. Starting engines...';
      debugPrint('WebSocket connected!');

      Future.delayed(const Duration(milliseconds: 500), () {
        initStatusText.value = 'System Ready.';
        isInitialized.value = true;
      });
    } catch (e) {
      debugPrint('Error connecting to WebSocket: $e');
      wsConnectionStatus.value = 'Error';

      if (sidecarStatus.value != 'Error') {
        lastError.value = e.toString();
      }

      if (retries > 0) {
        if (sidecarStatus.value == 'Error' ||
            sidecarStatus.value == 'Stopped') {
          initStatusText.value = 'Sidecar failed. Cannot connect.';
          return;
        }
        initStatusText.value = 'Retrying WebSocket ($retries)...';
        await Future.delayed(const Duration(seconds: 1));
        _connectToWebSocket(port: currentPort, retries: retries - 1);
      }
    }
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      // Global status handling
      if (type == 'status') {
        debugPrint('Sidecar Status: ${data['message']}');
      } else if (type == 'error') {
        debugPrint('Sidecar Error: ${data['message']}');
      }

      // Dispatch to handlers
      if (_handlers.containsKey(type)) {
        for (var handler in _handlers[type]!) {
          handler(data);
        }
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  void send(String message) {
    if (_channel != null && _isServerReady) {
      try {
        debugPrint('DEBUG SENDING: $message');
        _channel!.sink.add(message);
      } catch (e) {
        debugPrint('Error sending message to WebSocket: $e');
        _isServerReady = false;
      }
    }
  }
}
