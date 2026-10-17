import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/core/widgets/panels.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';
import 'package:path/path.dart' as p;

import '../../controllers/home_controller.dart';
import '../settings/settings_dialog.dart';

enum PadSettingsTab {
  playback('Playback'),
  triggers('Triggers'),
  output('Output');

  const PadSettingsTab(this.label);
  final String label;
}

/// Everything about one pad in a single place, in three tabs, instead of a
/// separate dialog per option: how it plays, how it is triggered, where it
/// goes.
class PadSettingsDialog extends StatefulWidget {
  const PadSettingsDialog({
    super.key,
    required this.controller,
    required this.padIndex,
    this.initialTab = PadSettingsTab.playback,
  });

  final HomeController controller;
  final int padIndex;
  final PadSettingsTab initialTab;

  static Future<void> show(
    HomeController controller,
    int padIndex, {
    PadSettingsTab tab = PadSettingsTab.playback,
  }) {
    return Get.dialog(
      PadSettingsDialog(
        controller: controller,
        padIndex: padIndex,
        initialTab: tab,
      ),
    );
  }

  @override
  State<PadSettingsDialog> createState() => _PadSettingsDialogState();
}

class _PadSettingsDialogState extends State<PadSettingsDialog> {
  late PadSettingsTab _tab = widget.initialTab;
  bool _capturingKey = false;
  StreamSubscription? _midiLearn;

  HomeController get c => widget.controller;
  int get i => widget.padIndex;

  @override
  void dispose() {
    _midiLearn?.cancel();
    super.dispose();
  }

  // ── Trigger capture ──────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_capturingKey || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _capturingKey = false);
      return KeyEventResult.handled;
    }
    final modifiers = {
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifiers.contains(key) || key.keyLabel.isEmpty) {
      return KeyEventResult.handled;
    }
    c.assignKeyboardShortcut(i, key.keyLabel.toUpperCase());
    setState(() => _capturingKey = false);
    return KeyEventResult.handled;
  }

  void _startMidiLearn() {
    _midiLearn?.cancel();
    setState(() {});
    _midiLearn = c.midiService.noteStream.listen((event) {
      final isTrigger =
          event.type == MidiEventType.noteOn ||
          (event.type == MidiEventType.controlChange && event.velocity > 0);
      if (!isTrigger) return;
      c.assignMidiNote(i, event.triggerId);
      _stopMidiLearn();
    });
    setState(() {});
  }

  void _stopMidiLearn() {
    _midiLearn?.cancel();
    _midiLearn = null;
    if (mounted) setState(() {});
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = c.pads[i];
    final file = pad.path == null ? 'No file assigned' : p.basename(pad.path!);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AppDialog(
        title: pad.name,
        subtitle: file,
        icon: Icons.tune,
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PadSettingsTab>(
                showSelectedIcon: false,
                segments: [
                  for (final t in PadSettingsTab.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() {
                  _tab = s.first;
                  _capturingKey = false;
                  _stopMidiLearn();
                }),
              ),
            ),
            const SizedBox(height: 20),
            switch (_tab) {
              PadSettingsTab.playback => _playback(),
              PadSettingsTab.triggers => _triggers(),
              PadSettingsTab.output => _output(),
            },
          ],
        ),
      ),
    );
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  Widget _playback() {
    return Obx(() {
      final pad = c.pads[i];
      final fader = c.faders.firstWhereOrNull((f) => f.id == pad.faderId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelGroup(
            title: 'Sound',
            children: [
              PanelRow(
                title: 'Volume',
                hint: fader != null
                    ? 'Also moved by the “${fader.name}” fader.'
                    : null,
                control: SizedBox(
                  width: 240,
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: pad.volume.clamp(0.0, 1.0),
                          onChanged: (v) => c.updatePadVolume(i, v),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(pad.volume * 100).round()}%',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PanelRow(
                title: 'Loop',
                hint: 'Repeat until stopped.',
                control: Switch(
                  value: pad.isLooping,
                  onChanged: (_) => c.toggleLoop(i),
                ),
              ),
            ],
          ),
          PanelGroup(
            title: 'Mixing',
            children: [
              PanelRow(
                title: 'Mixer fader',
                hint: 'Share one volume control with other pads.',
                control: _faderPicker(pad.faderId),
              ),
              PanelRow(
                title: 'Background pad',
                hint: 'Hide this pad from the local API.',
                control: Switch(
                  value: pad.isBackground,
                  onChanged: (_) => c.toggleBackground(i),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _faderPicker(String? currentId) {
    const none = '__none__';
    const create = '__new__';
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        key: ValueKey('fader-$currentId-${c.faders.length}'),
        initialValue: currentId ?? none,
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: none, child: Text('None')),
          for (final f in c.faders)
            DropdownMenuItem(
              value: f.id,
              child: Text(f.name, overflow: TextOverflow.ellipsis),
            ),
          const DropdownMenuItem(value: create, child: Text('New fader…')),
        ],
        onChanged: (v) async {
          if (v == create) {
            final name = await promptDialog(
              title: 'New fader',
              label: 'Fader name',
              confirmLabel: 'Create',
              icon: Icons.linear_scale,
            );
            if (name != null) {
              c.addFader(name);
              c.assignPadToFader(i, c.faders.last.id);
            }
          } else {
            c.assignPadToFader(i, v == none ? null : v);
          }
          if (mounted) setState(() {});
        },
      ),
    );
  }

  // ── Triggers ─────────────────────────────────────────────────────────────

  Widget _triggers() {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final pad = c.pads[i];
      final key = pad.keyboardShortcut;
      final note = pad.midiNote;
      final learning = _midiLearn != null;
      final midiConnected = c.midiService.connectedDevice.value != null;

      return PanelGroup(
        title: 'Play this pad with',
        children: [
          PanelRow(
            title: 'Keyboard key',
            hint: 'Press the key to play. Shift + key stops.',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_capturingKey)
                  const StatusPill(
                    'Press a key… (Esc to cancel)',
                    Color(0xFFD08A00),
                  )
                else if (key != null) ...[
                  Chip(label: Text(key)),
                  IconButton(
                    tooltip: 'Remove key',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => c.assignKeyboardShortcut(i, null),
                  ),
                ],
                if (!_capturingKey)
                  FilledButton.tonal(
                    onPressed: () => setState(() => _capturingKey = true),
                    child: Text(key == null ? 'Set key' : 'Change'),
                  ),
              ],
            ),
          ),
          PanelRow(
            title: 'MIDI control',
            hint: midiConnected
                ? 'Press “Learn”, then hit a pad or button on your controller.'
                : 'No controller connected.',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (learning)
                  const StatusPill('Listening…', Color(0xFFD08A00))
                else if (note != null) ...[
                  Chip(label: Text(MidiNoteEvent.getDisplayNameForId(note))),
                  IconButton(
                    tooltip: 'Remove MIDI assignment',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => c.assignMidiNote(i, null),
                  ),
                ],
                if (learning)
                  TextButton(
                    onPressed: _stopMidiLearn,
                    child: const Text('Cancel'),
                  )
                else if (midiConnected)
                  FilledButton.tonal(
                    onPressed: _startMidiLearn,
                    child: Text(note == null ? 'Learn' : 'Re-learn'),
                  )
                else
                  TextButton(
                    onPressed: () {
                      Get.back();
                      SettingsDialog.show(c, section: SettingsSection.midi);
                    },
                    child: Text(
                      'Connect',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  // ── Output ───────────────────────────────────────────────────────────────

  Widget _output() {
    return Obx(() {
      final pad = c.pads[i];
      final devices = c.audioService.outputDevices.toList();
      final channels = c.audioService.getDeviceChannels(pad.deviceId);
      final selected = pad.outputChannels ?? const <int>[];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelGroup(
            title: 'Output device',
            description:
                'Default follows the device chosen in Settings → Audio.',
            children: [
              _deviceTile(
                'Default',
                'Follow the app-wide device',
                pad.deviceId == null,
                () => c.assignDeviceIdToPad(i, null),
              ),
              for (final d in devices)
                _deviceTile(
                  d.name,
                  null,
                  pad.deviceId == d.id,
                  () => c.assignDeviceIdToPad(i, d.id),
                ),
            ],
          ),
          // Only multi-channel interfaces need channel mapping; for stereo it is noise.
          if (channels > 2)
            PanelGroup(
              title: 'Channels',
              description:
                  'Which outputs this pad plays on. None selected = default.',
              action: TextButton(
                onPressed: () => c.assignOutputChannelsToPad(i, null),
                child: const Text('Reset'),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var n = 0; n < channels; n++)
                        FilterChip(
                          label: Text('${n + 1}'),
                          selected: selected.contains(n),
                          onSelected: (on) {
                            final next = List<int>.from(selected);
                            on ? next.add(n) : next.remove(n);
                            next.sort();
                            c.assignOutputChannelsToPad(
                              i,
                              next.isEmpty ? null : next,
                            );
                          },
                        ),
                      ActionChip(
                        label: const Text('Stereo 1+2'),
                        onPressed: () => c.assignOutputChannelsToPad(i, [0, 1]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _deviceTile(
    String title,
    String? subtitle,
    bool selected,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: const RoundedRectangleBorder(),
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );
  }
}
