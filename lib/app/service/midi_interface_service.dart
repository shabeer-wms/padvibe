import "package:flutter/foundation.dart";
import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'sidecar_service.dart';

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
  }
}
