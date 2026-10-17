import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/core/widgets/panels.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';

import '../../controllers/home_controller.dart';

/// One mixer fader: its MIDI control, which pads follow it, and removal.
class FaderDialog extends StatefulWidget {
  const FaderDialog({super.key, required this.controller, required this.index});

  final HomeController controller;
  final int index;

  static Future<void> show(HomeController controller, int index) =>
      Get.dialog(FaderDialog(controller: controller, index: index));

  @override
  State<FaderDialog> createState() => _FaderDialogState();
}

class _FaderDialogState extends State<FaderDialog> {
  StreamSubscription? _learn;

  HomeController get c => widget.controller;

  @override
  void dispose() {
    _learn?.cancel();
    super.dispose();
  }

  void _startLearn() {
    _learn?.cancel();
    _learn = c.midiService.noteStream.listen((event) {
      if (event.type != MidiEventType.controlChange) return;
      c.assignFaderMidiCc(widget.index, event.triggerId);
      _stopLearn();
    });
    setState(() {});
  }

  void _stopLearn() {
    _learn?.cancel();
    _learn = null;
    if (mounted) setState(() {});
  }

  Future<void> _delete(String name) async {
    final ok = await confirmDialog(
      title: 'Delete fader?',
      message:
          '“$name” will be removed. Pads linked to it keep their own volume.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) {
      c.removeFader(widget.index);
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.index >= c.faders.length) return const SizedBox.shrink();
      final fader = c.faders[widget.index];
      final cc = fader.midiCc;
      final learning = _learn != null;
      final connected = c.midiService.connectedDevice.value != null;

      return AppDialog(
        title: fader.name,
        subtitle: 'Mixer fader',
        icon: Icons.linear_scale,
        maxWidth: 520,
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _delete(fader.name),
            child: const Text('Delete fader'),
          ),
          FilledButton(onPressed: Get.back, child: const Text('Done')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelGroup(
              title: 'MIDI control',
              children: [
                PanelRow(
                  title: 'Hardware fader',
                  hint: connected
                      ? 'Press “Learn”, then move a fader on your controller.'
                      : 'No controller connected.',
                  control: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (learning)
                        const StatusPill('Listening…', Color(0xFFD08A00))
                      else if (cc != null) ...[
                        Chip(
                          label: Text(MidiNoteEvent.getDisplayNameForId(cc)),
                        ),
                        IconButton(
                          tooltip: 'Remove assignment',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              c.assignFaderMidiCc(widget.index, null),
                        ),
                      ],
                      if (learning)
                        TextButton(
                          onPressed: _stopLearn,
                          child: const Text('Cancel'),
                        )
                      else if (connected)
                        FilledButton.tonal(
                          onPressed: _startLearn,
                          child: Text(cc == null ? 'Learn' : 'Re-learn'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            PanelGroup(
              title: 'Linked pads',
              description: 'These pads follow this fader’s volume.',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var n = 0; n < c.pads.length; n++)
                        FilterChip(
                          label: Text(c.pads[n].name),
                          selected: c.pads[n].faderId == fader.id,
                          onSelected: (on) =>
                              c.assignPadToFader(n, on ? fader.id : null),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
