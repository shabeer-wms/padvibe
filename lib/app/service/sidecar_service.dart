import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class SidecarService extends GetxService {
  final sidecarStatus = 'Not Started'.obs;
  final wsConnectionStatus = 'Disconnected'.obs;
  final lastError = ''.obs;
  final sidecarPid = Rxn<int>();

  // Initialization progress for splash screen
  final initStatusText = 'Initializing...'.obs;
  final isInitialized = false.obs;

  WebSocketChannel? _channel;
  Process? _pythonProcess;
  bool _isServerReady = false;
  Timer? _healthCheckTimer;

  // Registered message handlers: type -> callback
  final Map<String, List<Function(Map<String, dynamic>)>> _handlers = {};

  @override
  void onInit() {
    super.onInit();
    _startPythonSidecar();
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

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pythonProcess != null) {
        try {
          final result = Process.runSync('ps', [
            '-p',
            '${_pythonProcess!.pid}',
          ]);
          if (result.exitCode != 0) {
            sidecarStatus.value = 'Stopped';
            lastError.value = 'Sidecar process terminated unexpectedly';
          } else {
            sidecarStatus.value = 'Running';
          }
        } catch (e) {
          // ignore
        }
      }
    });
  }

  Future<void> _startPythonSidecar() async {
    print('Starting Python Sidecar...');
    initStatusText.value = 'Cleaning up previous processes...';
    sidecarStatus.value = 'Starting';
    lastError.value = '';

    // Kill any process using port 8765
    try {
      print('Checking for processes using port 8765...');
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('lsof', ['-t', '-i:8765']);
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          final pids = output.split('\n');
          for (final pid in pids) {
            if (pid.isNotEmpty) {
              print('Killing process $pid using port 8765');
              initStatusText.value = 'Terminating stale process $pid...';
              await Process.run('kill', ['-9', pid]);
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      print('Error cleaning up port 8765: $e');
    }

    initStatusText.value = 'Locating Sidecar binary...';
    try {
      String executablePath;
      if (Platform.isMacOS) {
        final binDir = File(Platform.resolvedExecutable).parent;
        final bundleDir = binDir.parent;
        executablePath =
            '${bundleDir.path}/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server';
      } else {
        executablePath = 'sidecar/dist/midi_server';
      }

      if (await File(executablePath).exists()) {
        print('Found sidecar binary at $executablePath');
        initStatusText.value = 'Starting Sidecar binary...';
        if (Platform.isMacOS || Platform.isLinux) {
          await Process.run('chmod', ['+x', executablePath]);
        }
        _pythonProcess = await Process.start(
          executablePath,
          [],
          runInShell: false,
        );
      } else {
        print('Sidecar binary not found. Trying python script fallback...');
        initStatusText.value = 'Starting Python Sidecar engine...';
        _pythonProcess = await Process.start('python3', [
          'sidecar/midi_server.py',
        ], runInShell: true);
      }

      if (_pythonProcess != null) {
        sidecarPid.value = _pythonProcess!.pid;
        print('Sidecar process started with PID: ${_pythonProcess!.pid}');
        _startHealthCheck();
      }

      _pythonProcess?.stdout.transform(utf8.decoder).listen((data) {
        print('SIDECAR OUT: $data');
      });

      _pythonProcess?.stderr.transform(utf8.decoder).listen((data) {
        print('SIDECAR ERR: $data');
        if (data.contains('ERROR') || data.contains('Error')) {
          lastError.value = data.trim();
        }
      });

      initStatusText.value = 'Waiting for Sidecar to initialize...';
      await Future.delayed(const Duration(seconds: 3));
      _connectToWebSocket(retries: 10);
    } catch (e) {
      print('Error starting Python sidecar: $e');
      sidecarStatus.value = 'Error';
      initStatusText.value = 'Initialization Error: ${e.toString()}';
      lastError.value = e.toString();
    }
  }

  void shutdownSidecar() {
    send(jsonEncode({'command': 'shutdown'}));
  }

  void _stopPythonSidecar() {
    print('Stopping Python Sidecar...');
    sidecarStatus.value = 'Stopped';
    shutdownSidecar();
    Future.delayed(const Duration(milliseconds: 100), () {
      _pythonProcess?.kill();
    });
  }

  Future<void> _connectToWebSocket({int retries = 5}) async {
    print('Connecting to WebSocket (Attempts left: $retries)...');
    initStatusText.value = 'Establishing WebSocket connection...';
    wsConnectionStatus.value = 'Connecting';

    try {
      final wsUrl = Uri.parse('ws://127.0.0.1:8765');
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
          print('WebSocket connection closed');
          _isServerReady = false;
          wsConnectionStatus.value = 'Disconnected';
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isServerReady = false;
          wsConnectionStatus.value = 'Error';
          lastError.value = error.toString();
          if (retries > 0) {
            initStatusText.value = 'Connection failed, retrying ($retries)...';
            Future.delayed(
              const Duration(seconds: 1),
              () => _connectToWebSocket(retries: retries - 1),
            );
          }
        },
      );

            _isServerReady = true;

            wsConnectionStatus.value = 'Connected';

            initStatusText.value = 'WebSocket Connected. Starting engines...';

            print('WebSocket connected!');

            

            // Allow a brief moment for other services to register their handlers and request data

            // before marking initialization as complete for the splash screen.

            Future.delayed(const Duration(milliseconds: 500), () {

              initStatusText.value = 'System Ready.';

              isInitialized.value = true;

            });

            

          } catch (e) {
      print('Error connecting to WebSocket: $e');
      wsConnectionStatus.value = 'Error';
      lastError.value = e.toString();
      if (retries > 0) {
        initStatusText.value = 'Retrying WebSocket ($retries)...';
        await Future.delayed(const Duration(seconds: 1));
        _connectToWebSocket(retries: retries - 1);
      }
    }
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      // Global status handling
      if (type == 'status') {
        print('Sidecar Status: ${data['message']}');
      } else if (type == 'error') {
        print('Sidecar Error: ${data['message']}');
      }

      // Dispatch to handlers
      if (_handlers.containsKey(type)) {
        for (var handler in _handlers[type]!) {
          handler(data);
        }
      }
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  void send(String message) {
    if (_channel != null && _isServerReady) {
      try {
        _channel!.sink.add(message);
      } catch (e) {
        print('Error sending message to WebSocket: $e');
        _isServerReady = false;
      }
    }
  }
}
