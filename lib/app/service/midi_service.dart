import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

enum MidiEventType { noteOn, noteOff }

class MidiNoteEvent {
  final int note;
  final int velocity;
  final MidiEventType type;

  MidiNoteEvent({
    required this.note,
    required this.velocity,
    required this.type,
  });
}

class MidiDevice {
  final String name;
  final String id;
  String type;
  bool connected;

  MidiDevice(this.name, this.id, this.type, this.connected);
}

class MidiService extends GetxService {
  final devices = <MidiDevice>[].obs;
  final connectedDevice = Rxn<MidiDevice>();

  final _noteStreamController = StreamController<MidiNoteEvent>.broadcast();
  Stream<MidiNoteEvent> get noteStream => _noteStreamController.stream;

  // Monitoring observables
  final sidecarStatus = 'Not Started'
      .obs; // 'Not Started', 'Starting', 'Running', 'Error', 'Stopped'
  final wsConnectionStatus =
      'Disconnected'.obs; // 'Disconnected', 'Connecting', 'Connected', 'Error'
  final lastError = ''.obs;
  final sidecarPid = Rxn<int>();

  WebSocketChannel? _channel;
  Process? _pythonProcess;
  bool _isServerReady = false;
  Timer? _healthCheckTimer;

  @override
  void onInit() {
    super.onInit();
    _startPythonSidecar();
  }

  @override
  void onClose() {
    _healthCheckTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _noteStreamController.close();
    _stopPythonSidecar();
    super.onClose();
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pythonProcess != null) {
        // Check if process is still running
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
    sidecarStatus.value = 'Starting';
    lastError.value = '';

    try {
      String executablePath;
      if (Platform.isMacOS) {
        // In macOS App Bundle, assets are in Contents/Frameworks/App.framework/Resources/flutter_assets/
        final binDir = File(
          Platform.resolvedExecutable,
        ).parent; // Contents/MacOS
        final bundleDir = binDir.parent; // Contents
        executablePath =
            '${bundleDir.path}/Frameworks/App.framework/Resources/flutter_assets/sidecar/dist/midi_server';
      } else {
        // Fallback for other platforms or dev mode if not in bundle
        executablePath = 'sidecar/dist/midi_server';
      }

      print('Looking for sidecar at: $executablePath');

      if (await File(executablePath).exists()) {
        print('Found sidecar binary at $executablePath');

        // Ensure it's executable
        if (Platform.isMacOS || Platform.isLinux) {
          await Process.run('chmod', ['+x', executablePath]);
        }

        _pythonProcess = await Process.start(
          executablePath,
          [],
          runInShell:
              false, // runInShell: false might be better for direct binary execution
        );
      } else {
        print(
          'Sidecar binary not found at $executablePath. Trying python script fallback...',
        );
        // This fallback likely won't work in sandbox but keeping it for dev
        _pythonProcess = await Process.start('python3', [
          'sidecar/midi_server.py',
        ], runInShell: true);
      }

      if (_pythonProcess != null) {
        sidecarPid.value = _pythonProcess!.pid;
        print('Sidecar process started with PID: ${_pythonProcess!.pid}');

        // Start health monitoring
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

      // Wait longer for the PyInstaller binary to start
      await Future.delayed(const Duration(seconds: 5));
      _connectToWebSocket(retries: 10);
    } catch (e) {
      print('Error starting Python sidecar: $e');
      sidecarStatus.value = 'Error';
      lastError.value = e.toString();
    }
  }

  void _stopPythonSidecar() {
    print('Stopping Python Sidecar...');
    sidecarStatus.value = 'Stopped';
    _pythonProcess?.kill();
  }

  Future<void> _connectToWebSocket({int retries = 5}) async {
    print('Connecting to WebSocket (Attempts left: $retries)...');
    wsConnectionStatus.value = 'Connecting';

    try {
      final wsUrl = Uri.parse('ws://127.0.0.1:8765');
      _channel = WebSocketChannel.connect(wsUrl);

      // Wait for the connection to be established by sending a ping or just waiting
      // Since WebSocketChannel doesn't have a ready state, we just listen.
      // But if it fails immediately, we catch it in onError.

      _channel?.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onDone: () {
          print('WebSocket connection closed');
          _isServerReady = false;
          wsConnectionStatus.value = 'Disconnected';
          // If we closed unexpectedly, maybe retry?
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isServerReady = false;
          wsConnectionStatus.value = 'Error';
          lastError.value = error.toString();
          if (retries > 0) {
            print('Retrying connection in 1 second...');
            Future.delayed(
              const Duration(seconds: 1),
              () => _connectToWebSocket(retries: retries - 1),
            );
          }
        },
      );

      // Send a ping to verify connection?
      // Or just assume it's connected until error.
      // Let's try to send a list_devices command immediately.
      // If it fails, the error handler will trigger retry.

      _isServerReady = true;
      wsConnectionStatus.value = 'Connected';
      print('WebSocket connected!');
      refreshDevices();
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      wsConnectionStatus.value = 'Error';
      lastError.value = e.toString();
      if (retries > 0) {
        await Future.delayed(const Duration(seconds: 1));
        _connectToWebSocket(retries: retries - 1);
      }
    }
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      if (type == 'device_list') {
        final List<dynamic> deviceNames = data['devices'];
        devices.assignAll(
          deviceNames
              .map((name) => MidiDevice(name, name, 'native', false))
              .toList(),
        );
        print('MIDI Devices found: ${devices.length}');
      } else if (type == 'midi_message') {
        final msg = data['message'];
        final msgType = msg['type'];
        final note = msg['note'];
        final velocity = msg['velocity'];

        if (msgType == 'note_on' && velocity > 0) {
          _noteStreamController.add(
            MidiNoteEvent(
              note: note,
              velocity: velocity,
              type: MidiEventType.noteOn,
            ),
          );
        } else if (msgType == 'note_off' ||
            (msgType == 'note_on' && velocity == 0)) {
          _noteStreamController.add(
            MidiNoteEvent(note: note, velocity: 0, type: MidiEventType.noteOff),
          );
        }
      } else if (type == 'status') {
        print('Sidecar Status: ${data['message']}');
      } else if (type == 'error') {
        print('Sidecar Error: ${data['message']}');
      }
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  void refreshDevices() {
    if (_channel != null && _isServerReady) {
      print('Refreshing devices via WebSocket...');
      _channel!.sink.add(jsonEncode({'command': 'list_devices'}));
    } else {
      print('WebSocket not ready, cannot refresh devices.');
    }
  }

  void connect(MidiDevice device) {
    if (_channel != null && _isServerReady) {
      print('Connecting to device: ${device.name}');
      _channel!.sink.add(
        jsonEncode({'command': 'connect_device', 'device_name': device.name}),
      );
      connectedDevice.value = device;
      // Optimistically set connected, real status comes from sidecar but for UI we might need this
      // Ideally we should wait for confirmation
    }
  }

  void disconnect() {
    // Implement disconnect logic if needed on sidecar
    connectedDevice.value = null;
  }
}
