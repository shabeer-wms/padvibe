import "package:flutter/foundation.dart";
import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'sidecar_service.dart';

enum MidiEventType { noteOn, noteOff, controlChange, programChange }

class MidiNoteEvent {
  final int? note;
  final int? control;
  final int? value;
  final int velocity;
  final int channel;
  final MidiEventType type;

  MidiNoteEvent({
    this.note,
    this.control,
    this.value,
    required this.velocity,
    required this.channel,
    required this.type,
  });

  int get triggerId {
    if (type == MidiEventType.controlChange) {
      return 30000 + (channel * 200) + (control ?? 0);
    } else if (type == MidiEventType.programChange) {
      return 50000 + (channel * 200) + (note ?? 0);
    } else {
      return 10000 + (channel * 200) + (note ?? 0);
    }
  }

  String get displayName {
    final ch = channel + 1;
    if (type == MidiEventType.controlChange) {
      return 'CC $control (Ch $ch)';
    } else if (type == MidiEventType.programChange) {
      return 'PC $note (Ch $ch)';
    } else {
      return 'Note $note (Ch $ch)';
    }
  }

  static String getDisplayNameForId(int id) {
    if (id >= 50000) {
      final rem = id - 50000;
      final ch = (rem ~/ 200) + 1;
      final pc = rem % 200;
      return 'PC $pc (Ch $ch)';
    } else if (id >= 30000) {
      final rem = id - 30000;
      final ch = (rem ~/ 200) + 1;
      final cc = rem % 200;
      return 'CC $cc (Ch $ch)';
    } else if (id >= 10000) {
      final rem = id - 10000;
      final ch = (rem ~/ 200) + 1;
      final note = rem % 200;
      return 'Note $note (Ch $ch)';
    }
    return 'ID $id';
  }
}

class MidiDevice {
  final String name;
  final String id;
  String type;
  bool connected;

  MidiDevice(this.name, this.id, this.type, this.connected);
}

class MidiInterfaceService extends GetxService {
  final SidecarService _sidecar = Get.find<SidecarService>();

  final devices = <MidiDevice>[].obs;
  final connectedDevice = Rxn<MidiDevice>();

  final _noteStreamController = StreamController<MidiNoteEvent>.broadcast();
  Stream<MidiNoteEvent> get noteStream => _noteStreamController.stream;

  @override
  void onInit() {
    super.onInit();
        _sidecar.registerHandler('device_list', _handleDeviceList);
        _sidecar.registerHandler('midi_message', _handleMidiMessage);
        
        // Refresh devices when connected
        ever(_sidecar.wsConnectionStatus, (status) {
          if (status == 'Connected') {
            refreshDevices();
          }
        });
    
        // Initial refresh request
        if (_sidecar.wsConnectionStatus.value == 'Connected') {
          refreshDevices();
        }
      }
  @override
  void onClose() {
    _sidecar.unregisterHandler('device_list', _handleDeviceList);
    _sidecar.unregisterHandler('midi_message', _handleMidiMessage);
    _noteStreamController.close();
    super.onClose();
  }

  void refreshDevices() {
    debugPrint('Refreshing MIDI devices via Sidecar...');
    _sidecar.send(jsonEncode({'command': 'list_devices'}));
  }

  void connect(MidiDevice device) {
    debugPrint('Connecting to device: ${device.name}');
    _sidecar.send(
      jsonEncode({'command': 'connect_device', 'device_name': device.name}),
    );
    connectedDevice.value = device;
  }

  void disconnect() {
    connectedDevice.value = null;
    // Implement disconnect logic if needed on sidecar
  }

  void _handleDeviceList(Map<String, dynamic> data) {
    final List<dynamic> deviceNames = data['devices'];
    devices.assignAll(
      deviceNames
          .map((name) => MidiDevice(name, name, 'native', false))
          .toList(),
    );
    debugPrint('MIDI Devices found: ${devices.length}');
  }

  void _handleMidiMessage(Map<String, dynamic> data) {
    debugPrint('MidiInterfaceService processing: ${jsonEncode(data)}');
    final msg = data['message'];
    final msgType = msg['type'];
    final int channel = msg['channel'] ?? 0;
    final int? note = msg['note'];
    final int? control = msg['control'];
    final int? value = msg['value'];
    final int velocity = msg['velocity'] ?? (value ?? 0);

    final int? program = msg['program'];

    if (msgType == 'note_on' && velocity > 0) {
      _noteStreamController.add(
        MidiNoteEvent(
          note: note,
          velocity: velocity,
          channel: channel,
          type: MidiEventType.noteOn,
        ),
      );
    } else if (msgType == 'note_off' ||
        (msgType == 'note_on' && velocity == 0)) {
      _noteStreamController.add(
        MidiNoteEvent(
          note: note,
          velocity: 0,
          channel: channel,
          type: MidiEventType.noteOff,
        ),
      );
    } else if (msgType == 'control_change') {
      _noteStreamController.add(
        MidiNoteEvent(
          control: control,
          value: value,
          velocity: value ?? 0,
          channel: channel,
          type: MidiEventType.controlChange,
        ),
      );
    } else if (msgType == 'program_change') {
      _noteStreamController.add(
        MidiNoteEvent(
          note: program,
          velocity: 127,
          channel: channel,
          type: MidiEventType.programChange,
        ),
      );
    }
  }
}
