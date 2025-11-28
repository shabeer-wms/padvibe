import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:get/get.dart';

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

class MidiService extends GetxService {
  final _midiCommand = MidiCommand();
  final devices = <MidiDevice>[].obs;
  final connectedDevice = Rxn<MidiDevice>();

  StreamSubscription<MidiPacket>? _midiSubscription;
  StreamSubscription<String>? _setupSubscription;

  final _noteStreamController = StreamController<MidiNoteEvent>.broadcast();
  Stream<MidiNoteEvent> get noteStream => _noteStreamController.stream;

  @override
  void onInit() {
    super.onInit();

    _setupSubscription = _midiCommand.onMidiSetupChanged?.listen((data) {
      refreshDevices();
    });

    _midiSubscription = _midiCommand.onMidiDataReceived?.listen((packet) {
      _handleMidiPacket(packet);
    });

    refreshDevices();
  }

  @override
  void onClose() {
    _midiSubscription?.cancel();
    _setupSubscription?.cancel();
    _noteStreamController.close();
    super.onClose();
  }

  Future<void> refreshDevices() async {
    final list = await _midiCommand.devices;
    devices.assignAll(list ?? []);
  }

  Future<void> connect(MidiDevice device) async {
    if (connectedDevice.value?.id == device.id) {
      return;
    }

    try {
      await _midiCommand.connectToDevice(device);
    } catch (e) {
      if (e.toString().contains("Device already connected")) {
        try {
          _midiCommand.disconnectDevice(device);
          await Future.delayed(const Duration(milliseconds: 200));
          await _midiCommand.connectToDevice(device);
        } catch (retryError) {
          // Retry failed, but continue anyway
        }
      }
    }

    connectedDevice.value = device;
  }

  void disconnect() {
    connectedDevice.value = null;
  }

  void _handleMidiPacket(MidiPacket packet) {
    if (packet.data.isEmpty) return;

    final status = packet.data[0];
    final command = status & 0xF0;

    // Note On: 0x90
    if (command == 0x90) {
      if (packet.data.length < 3) return;
      final note = packet.data[1];
      final velocity = packet.data[2];

      if (velocity > 0) {
        _noteStreamController.add(
          MidiNoteEvent(
            note: note,
            velocity: velocity,
            type: MidiEventType.noteOn,
          ),
        );
      } else {
        _noteStreamController.add(
          MidiNoteEvent(note: note, velocity: 0, type: MidiEventType.noteOff),
        );
      }
    }
    // Note Off: 0x80
    else if (command == 0x80) {
      if (packet.data.length < 3) return;
      final note = packet.data[1];
      final velocity = packet.data[2];
      _noteStreamController.add(
        MidiNoteEvent(
          note: note,
          velocity: velocity,
          type: MidiEventType.noteOff,
        ),
      );
    }
  }
}
