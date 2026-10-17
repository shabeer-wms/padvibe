import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:padvibe/app/service/audio_player_service.dart';
import 'package:padvibe/app/service/midi_interface_service.dart';

import 'package:padvibe/app/core/widgets/panels.dart';

import '../../controllers/home_controller.dart';

enum SettingsSection {
  general('General', Icons.tune, 'Appearance and pad grid'),
  audio('Audio', Icons.volume_up_outlined, 'Output device'),
  midi('MIDI', Icons.piano_outlined, 'Input devices'),
  integrations('Integrations', Icons.hub_outlined, 'Local API and webhook'),
  diagnostics(
    'Diagnostics',
    Icons.monitor_heart_outlined,
    'Sidecar status and logs',
  );

  const SettingsSection(this.label, this.icon, this.subtitle);
  final String label;
  final IconData icon;
  final String subtitle;
}

/// Settings, organised into sections: a navigation rail beside the content on
/// wide windows, and a horizontal section switcher above it on narrow ones.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.controller,
    this.initialSection = SettingsSection.general,
  });

  final HomeController controller;
  final SettingsSection initialSection;

  static Future<void> show(
    HomeController controller, {
    SettingsSection section = SettingsSection.general,
  }) {
    return Get.dialog(
      SettingsDialog(controller: controller, initialSection: section),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.initialSection;

  HomeController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final inset = screen.width < 600 ? 12.0 : 24.0;
    final wide = screen.width - inset * 2 >= 700;

    return Dialog(
      insetPadding: EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(onClose: Get.back),
            const Divider(),
            Flexible(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 220,
                          // Material (not ColoredBox) so list tiles can paint their
                          // selection highlight on it.
                          child: Material(
                            color: scheme.surfaceContainerLowest,
                            child: _NavRail(
                              selected: _section,
                              onSelected: (s) => setState(() => _section = s),
                            ),
                          ),
                        ),
                        const VerticalDivider(),
                        Expanded(child: _content()),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NavStrip(
                          selected: _section,
                          onSelected: (s) => setState(() => _section = s),
                        ),
                        const Divider(),
                        Flexible(child: _content()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final padding = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: switch (_section) {
            SettingsSection.general => _GeneralSection(c),
            SettingsSection.audio => _AudioSection(c),
            SettingsSection.midi => _MidiSection(c),
            SettingsSection.integrations => _IntegrationsSection(c),
            SettingsSection.diagnostics => _DiagnosticsSection(c),
          },
        ),
      ),
    );
  }
}

// ── Chrome ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
      child: Row(
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelected});
  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final s in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              dense: true,
              selected: s == selected,
              selectedTileColor: scheme.primaryContainer.withValues(
                alpha: 0.55,
              ),
              selectedColor: scheme.onPrimaryContainer,
              leading: Icon(s.icon, size: 20),
              title: Text(
                s.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => onSelected(s),
            ),
          ),
      ],
    );
  }
}

class _NavStrip extends StatelessWidget {
  const _NavStrip({required this.selected, required this.onSelected});
  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final s in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: Icon(s.icon, size: 18),
                label: Text(s.label),
                selected: s == selected,
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sections ───────────────────────────────────────────────────────────────

class _GeneralSection extends StatelessWidget {
  const _GeneralSection(this.c);
  final HomeController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelGroup(
          title: 'Appearance',
          children: [
            PanelRow(
              title: 'Theme',
              hint: 'Follow the system or force light or dark.',
              control: Obx(
                () => SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                  ],
                  selected: {c.themeMode.value},
                  onSelectionChanged: (s) => c.setThemeMode(s.first),
                ),
              ),
            ),
          ],
        ),
        PanelGroup(
          title: 'Pad grid',
          children: [
            PanelRow(
              title: 'Columns',
              hint:
                  'Most pads per row. Narrow windows show fewer automatically.',
              control: Obx(
                () => SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final n in const [4, 5, 6, 8, 10])
                      ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {c.gridColumns.value},
                  onSelectionChanged: (s) => c.updateGridColumns(s.first),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudioSection extends StatelessWidget {
  const _AudioSection(this.c);
  final HomeController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final connected =
          c.sidecarService.wsConnectionStatus.value == 'Connected';
      final devices = c.audioService.outputDevices.toList();
      final selected = c.audioService.selectedDevice.value;

      return PanelGroup(
        title: 'Output device',
        description: 'Where pads play. Individual pads can override this.',
        action: TextButton.icon(
          onPressed: connected ? c.audioService.refreshOutputDevices : null,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
        children: [
          if (!connected)
            const PanelEmpty(
              icon: Icons.sync,
              busy: true,
              message: 'Waiting for the audio engine to connect…',
            )
          else if (devices.isEmpty)
            const PanelEmpty(
              icon: Icons.volume_off_outlined,
              message: 'No audio output devices found.',
            )
          else
            for (final d in devices) _deviceTile(context, d, selected),
        ],
      );
    });
  }

  Widget _deviceTile(
    BuildContext context,
    PlaybackDevice d,
    PlaybackDevice? selected,
  ) {
    final isSelected = selected?.id == d.id;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: const RoundedRectangleBorder(),
      selected: isSelected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: d.isDefault ? const Text('System default') : null,
      onTap: () => c.selectAudioDevice(d),
    );
  }
}

class _MidiSection extends StatelessWidget {
  const _MidiSection(this.c);
  final HomeController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final connected =
          c.sidecarService.wsConnectionStatus.value == 'Connected';
      final devices = c.midiService.devices.toList();
      final active = c.midiService.connectedDevice.value;

      return PanelGroup(
        title: 'Input devices',
        description: 'Connect a controller to trigger pads and faders.',
        action: TextButton.icon(
          onPressed: connected ? c.midiService.refreshDevices : null,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
        children: [
          if (!connected)
            PanelEmpty(
              icon: Icons.sync,
              busy: true,
              message:
                  'Waiting for the MIDI engine (${c.sidecarService.sidecarStatus.value})…',
            )
          else if (devices.isEmpty)
            const PanelEmpty(
              icon: Icons.piano_off_outlined,
              message:
                  'No MIDI devices found.\nPlug one in, then press Refresh.',
            )
          else
            for (final d in devices) _deviceTile(context, d, active),
        ],
      );
    });
  }

  Widget _deviceTile(BuildContext context, MidiDevice d, MidiDevice? active) {
    final isConnected = active?.id == d.id;
    return ListTile(
      shape: const RoundedRectangleBorder(),
      leading: const Icon(Icons.piano_outlined),
      title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: isConnected
          ? StatusPill('Connected', statusColor('Connected'))
          : null,
      trailing: isConnected
          ? OutlinedButton(
              onPressed: c.midiService.disconnect,
              child: const Text('Disconnect'),
            )
          : FilledButton.tonal(
              onPressed: () => c.midiService.connect(d),
              child: const Text('Connect'),
            ),
    );
  }
}

class _IntegrationsSection extends StatefulWidget {
  const _IntegrationsSection(this.c);
  final HomeController c;

  @override
  State<_IntegrationsSection> createState() => _IntegrationsSectionState();
}

class _IntegrationsSectionState extends State<_IntegrationsSection> {
  late final TextEditingController _url = TextEditingController(
    text: widget.c.remoteEndpointUrl,
  );
  late String _saved = widget.c.remoteEndpointUrl;
  bool _justSaved = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _validate(String v) {
    final value = v.trim();
    if (value.isEmpty) return null; // empty disables the webhook
    final uri = Uri.tryParse(value);
    final ok =
        uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    return ok ? null : 'Enter a full http:// or https:// URL';
  }

  void _save() {
    final value = _url.text.trim();
    widget.c.updateRemoteEndpoint(value);
    setState(() {
      _saved = value;
      _justSaved = true;
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justSaved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          final ip = c.localApiService.localIp.value;
          return PanelGroup(
            title: 'Local API',
            description:
                'Other devices on your network can read the live state here.',
            children: [
              PanelValue(label: 'Local IP', value: ip),
              PanelValue(
                label: 'Endpoint',
                value: 'http://$ip:9696/state',
                copyable: true,
              ),
            ],
          );
        }),
        PanelGroup(
          title: 'Webhook',
          description:
              'PadVibe POSTs its state to this URL every second. Leave empty to turn off.',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _url,
                builder: (context, value, _) {
                  final error = _validate(value.text);
                  final dirty = value.text.trim() != _saved;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          hintText: 'https://example.com/webhook',
                          errorText: error,
                        ),
                        onSubmitted: (_) {
                          if (error == null && dirty) _save();
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: (error == null && dirty) ? _save : null,
                            child: const Text('Save'),
                          ),
                          const SizedBox(width: 12),
                          if (_justSaved)
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: statusColor('Connected'),
                                ),
                                const SizedBox(width: 6),
                                const Text('Saved'),
                              ],
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection(this.c);
  final HomeController c;

  @override
  Widget build(BuildContext context) {
    final s = c.sidecarService;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          final sidecar = s.sidecarStatus.value;
          final ws = s.wsConnectionStatus.value;
          final err = s.lastError.value;
          return PanelGroup(
            title: 'Audio & MIDI engine',
            description:
                'A background process (the “sidecar”) plays audio and reads MIDI.',
            action: OutlinedButton.icon(
              onPressed: s.restartSidecar,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restart'),
            ),
            children: [
              PanelRow(
                title: 'Process',
                control: StatusPill(sidecar, statusColor(sidecar)),
              ),
              PanelRow(
                title: 'Connection',
                control: StatusPill(ws, statusColor(ws)),
              ),
              PanelValue(label: 'Port', value: s.lastDiscoveredPort.toString()),
              PanelValue(
                label: 'Process ID',
                value: s.sidecarPid.value?.toString() ?? '—',
              ),
              if (err.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: scheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          err,
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
        PanelGroup(
          title: 'Logs',
          description: 'Share this file when reporting a problem.',
          children: [
            PanelValue(label: 'Log file', value: s.logFilePath, copyable: true),
          ],
        ),
      ],
    );
  }
}
