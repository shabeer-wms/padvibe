import 'dart:math' as math;
import 'dart:async'; // added
import 'dart:ui'; // for FontFeature
import 'package:PadVibe/app/data/pad_model.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:PadVibe/app/service/midi_interface_service.dart'; // updated
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  // --- Added: detachable timer overlay state/helpers ---
  static OverlayEntry? _timerOverlay;
  static final ValueNotifier<Offset> _timerOverlayPos = ValueNotifier<Offset>(
    const Offset(80, 80),
  );

  // Added: overlay sizing (now resizable)
  static const double _kOverlayW = 260.0;
  static const double _kOverlayH = 56.0;
  static const double _kOverlayMinW = 200.0;
  static const double _kOverlayMinH = 56.0;
  static final ValueNotifier<Size> _timerOverlaySize = ValueNotifier<Size>(
    const Size(_kOverlayW, _kOverlayH),
  );
  static final ValueNotifier<bool> _isTimerDetached = ValueNotifier<bool>(
    false,
  );

  // Added: API to get formatted timer text only
  static String getTimerTextOnly() {
    final secs = Get.find<HomeController>().remainingSeconds.value;
    return _formatRemaining(secs);
  }

  // Changed: make formatter static so it can be used by the API
  static String _formatRemaining(double secs) {
    if (secs.isNaN || secs.isInfinite) return '00:00:000';
    if (secs < 0) secs = 0;
    final totalMs = (secs * 1000).round();
    final mins = totalMs ~/ 60000;
    final secInt = (totalMs % 60000) ~/ 1000;
    final millis = (totalMs % 1000); // 3 digits (000-999)

    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(mins)}:${two(secInt)}:${three(millis)}';
  }

  // Added: urgency color for timer
  Color _urgencyColor(BuildContext context, double secs) {
    if (secs <= 10) return Colors.redAccent;
    if (secs <= 30) return Colors.orangeAccent;
    return Theme.of(context).colorScheme.primary;
  }

  // Added: blink indicator in last 5s
  bool _blink(double secs) {
    if (secs > 5) return false;
    final t = DateTime.now().millisecondsSinceEpoch ~/ 400; // ~2.5Hz blink
    return t.isEven;
  }

  // --- End added ---

  // --- Added: overlay controls (toggle/show/hide) ---
  void _toggleTimerOverlay(BuildContext context) {
    if (_timerOverlay == null) {
      _showTimerOverlay(context);
    } else {
      _hideTimerOverlay();
    }
  }

  void _showTimerOverlay(BuildContext context) {
    if (_timerOverlay != null) return;
    final overlay = Overlay.of(context);

    _timerOverlay = OverlayEntry(
      builder: (ctx) {
        return ValueListenableBuilder<Offset>(
          valueListenable: _timerOverlayPos,
          builder: (_, pos, __) {
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: ValueListenableBuilder<Size>(
                valueListenable: _timerOverlaySize,
                builder: (_, size, __) {
                  return Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      // Drag the whole card by clicking and dragging anywhere except the resize handle.
                      onPanUpdate: (details) {
                        _timerOverlayPos.value =
                            _timerOverlayPos.value + details.delta;
                      },
                      child: Container(
                        width: size.width,
                        height: size.height,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.surface.withOpacity(0.98),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.primary.withOpacity(0.35),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Center: big, readable timer text
                            Center(
                              child: Obx(() {
                                final secs = Get.find<HomeController>()
                                    .remainingSeconds
                                    .value;
                                final accent = _urgencyColor(ctx, secs);
                                final blinking = _blink(secs);
                                final text = _formatRemaining(secs);
                                final h = _timerOverlaySize.value.height;
                                final fontSize = (h * 0.55).clamp(28.0, 220.0);

                                return AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 120),
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w700,
                                    color: accent.withOpacity(
                                      blinking ? 1.0 : 0.45,
                                    ),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  child: Text(text),
                                );
                              }),
                            ),
                            // Top-right: close button
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                tooltip: 'Pin timer',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                onPressed: _hideTimerOverlay,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                            // Bottom-right: resize handle
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  final w = math.max(
                                    _kOverlayMinW,
                                    _timerOverlaySize.value.width +
                                        details.delta.dx,
                                  );
                                  final h = math.max(
                                    _kOverlayMinH,
                                    _timerOverlaySize.value.height +
                                        details.delta.dy,
                                  );
                                  _timerOverlaySize.value = Size(w, h);
                                },
                                child: MouseRegion(
                                  cursor:
                                      SystemMouseCursors.resizeUpLeftDownRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.open_in_full,
                                      size: 16,
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );

    overlay.insert(_timerOverlay!);
    _isTimerDetached.value = true;
  }

  void _hideTimerOverlay() {
    _timerOverlay?.remove();
    _timerOverlay = null;
    _isTimerDetached.value = false;
  }
  // --- End added ---

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.red,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
      Colors.pink,
      Colors.lime,
      Colors.brown,
    ];
    return Scaffold(
      appBar: _appBar(context),
      body: Focus(
        autofocus: true,
        focusNode: controller.focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // Space key stops all
            if (event.logicalKey == LogicalKeyboardKey.space) {
              controller.stopAll();
              return KeyEventResult.handled;
            }

            // Get the key label
            final keyLabel = event.logicalKey.keyLabel.toUpperCase();
            if (keyLabel.isEmpty) return KeyEventResult.ignored;

            // Find pad with this keyboard shortcut
            final padIndex = controller.pads.indexWhere(
              (pad) => pad.keyboardShortcut == keyLabel,
            );

            if (padIndex != -1) {
              // Check if Shift is pressed using HardwareKeyboard
              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

              if (isShiftPressed) {
                // Shift + key = Stop
                controller.stopPad(padIndex);
              } else {
                // Just key = Play/Pause
                controller.playPad(padIndex);
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Obx(() {
                      // Read the ticker to trigger rebuilds for progress bars.
                      final _ = controller.remainingSeconds.value;
                      // Also observe active handles for immediate play/pause updates
                      final __ = controller.audioService.activeHandles.length;
                      // Also observe manual force updates (e.g. seeking while paused)
                      final ___ = controller.forceUpdate.value;
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Obx(() {
                              final width = constraints.maxWidth;
                              const spacing = 12.0;
                              final cols = controller.gridColumns.value;
                              final childAspect = 4 / 3;

                              return GridView.builder(
                                itemCount: controller.pads.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cols,
                                      mainAxisSpacing: spacing,
                                      crossAxisSpacing: spacing,
                                      childAspectRatio: childAspect,
                                    ),
                                itemBuilder: (context, index) {
                                  final pad = controller.pads[index].obs;
                                  final color = colors[index % colors.length];
                                  final hasFile = pad.value.path != null;
                                  final fileName = hasFile
                                      ? pad.value.path!.split('/').last
                                      : 'Empty';

                                  return Obx(
                                    () => DropTarget(
                                      onDragDone: (detail) {
                                        if (detail.files.isEmpty) return;
                                        final f = detail.files.first;
                                        if (!f.name.toLowerCase().endsWith(
                                              '.mp3',
                                            ) &&
                                            !f.name.toLowerCase().endsWith(
                                              '.wav',
                                            ) &&
                                            !f.name.toLowerCase().endsWith(
                                              '.ogg',
                                            ) &&
                                            !f.name.toLowerCase().endsWith(
                                              '.flac',
                                            ) &&
                                            !f.name.toLowerCase().endsWith(
                                              '.aac',
                                            ) &&
                                            !f.name.toLowerCase().endsWith(
                                              '.m4a',
                                            )) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Unsupported file type: ${f.name}',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        controller.assignFilePathToPad(
                                          index,
                                          f.path,
                                        );
                                      },
                                      child: GestureDetector(
                                        onSecondaryTapUp: (details) =>
                                            _showPadOptions(
                                              context,
                                              index,
                                              details.globalPosition,
                                            ),
                                        onTap: hasFile
                                            ? () => controller.playPad(index)
                                            : null,
                                        onLongPress: () =>
                                            controller.assignFileToPad(index),
                                        child: _pad(
                                          color,
                                          hasFile,
                                          index,
                                          pad.value,
                                          fileName,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            });
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isTimerDetached,
                    builder: (context, detached, _) {
                      return Obx(() {
                        final secs = controller.remainingSeconds.value;
                        final accent = _urgencyColor(context, secs);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!detached)
                              Text(
                                'Remaining: ${_formatRemaining(secs)}',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              )
                            else
                              Text(
                                'Timer detached (${_formatRemaining(secs)})',
                                style: TextStyle(
                                  color: accent.withOpacity(0.85),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: detached ? 'Pin timer' : 'Pop-out timer',
                              icon: Icon(
                                detached ? Icons.push_pin : Icons.open_in_new,
                              ),
                              onPressed: () => _toggleTimerOverlay(context),
                            ),
                          ],
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
      title: const Text('PadVibe'),
      centerTitle: false,
      actions: [
        // Grid Size Selector
        Obx(
          () => DropdownButton<int>(
            value: controller.gridColumns.value,
            dropdownColor: Theme.of(context).colorScheme.surface,
            underline: const SizedBox(),
            icon: const Icon(Icons.grid_view),
            onChanged: (val) {
              if (val != null) controller.updateGridColumns(val);
            },
            items: [4, 5, 6, 8, 10]
                .map((e) => DropdownMenuItem(value: e, child: Text('${e}x')))
                .toList(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings),
          onPressed: () => _showSettingsDialog(context),
        ),
        IconButton(
          tooltip: 'Add files',
          icon: const Icon(Icons.library_music),
          onPressed: controller.addFiles,
        ),
        IconButton(
          tooltip: 'MIDI Devices',
          icon: const Icon(Icons.piano),
          onPressed: () => _showMidiDevicesDialog(context),
        ),
        IconButton(
          tooltip: 'Audio Output',
          icon: const Icon(Icons.volume_up),
          onPressed: () => _showAudioOutputDialog(context),
        ),
        IconButton(
          tooltip: 'Stop all',
          icon: const Icon(Icons.stop_circle_outlined),
          onPressed: controller.stopAll,
        ),
        IconButton(
          tooltip: 'Clear all',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear all pads?'),
                content: const Text(
                  'This stops playback, removes assigned files, and clears saved layout.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Get.back(result: true),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await controller.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All pads cleared')),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: controller.groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = controller.groups[index];
                  return Obx(() {
                    final isSelected =
                        controller.currentGroupIndex.value == index;
                    return GestureDetector(
                      onSecondaryTapUp: (details) => _showTabOptions(
                        context,
                        index,
                        details.globalPosition,
                      ),
                      onDoubleTapDown: (details) => _showRenameTabPopover(
                        context,
                        index,
                        details.globalPosition,
                      ),
                      child: ChoiceChip(
                        label: Text(group.name),
                        selected: isSelected,
                        onSelected: (_) => controller.switchTab(index),
                      ),
                    );
                  });
                },
              );
            }),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddTabDialog(context),
            tooltip: 'Add Tab',
          ),
        ],
      ),
    );
  }

  void _showAddTabDialog(BuildContext context) {
    final textCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Add Tab'),
        content: TextField(
          controller: textCtrl,
          decoration: const InputDecoration(hintText: 'Tab Name'),
          autofocus: true,
          onSubmitted: (val) {
            if (val.isNotEmpty) {
              controller.addTab(val);
              Get.back();
            }
          },
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (textCtrl.text.isNotEmpty) {
                controller.addTab(textCtrl.text);
                Get.back();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showTabOptions(BuildContext context, int index, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: const ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          onTap: () {
            // Slight delay to allow menu to close before showing dialog/popover
            Future.delayed(
              const Duration(milliseconds: 100),
              () => _showRenameTabPopover(context, index, position),
            );
          },
        ),
        PopupMenuItem(
          value: 'delete',
          child: const ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          onTap: () {
            Future.delayed(
              const Duration(milliseconds: 100),
              () => _showDeleteTabConfirmation(context, index),
            );
          },
        ),
      ],
    );
  }

  void _showRenameTabPopover(BuildContext context, int index, Offset position) {
    final textCtrl = TextEditingController(text: controller.groups[index].name);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          enabled: false, // Don't close on tap, handle manually
          child: SizedBox(
            width: 200,
            child: TextField(
              controller: textCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Tab Name',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onSubmitted: (val) {
                if (val.isNotEmpty) {
                  controller.renameTab(index, val);
                  Navigator.of(context).pop(); // Close menu
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteTabConfirmation(BuildContext context, int index) {
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Tab'),
        content: const Text(
          'Are you sure you want to delete this tab? All assigned pads in this tab will be lost.',
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              controller.deleteTab(index);
              Get.back();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showKeyboardShortcutDialog(int padIndex) {
    Get.dialog(
      KeyboardListener(
        autofocus: true,
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            String? keyLabel;

            // Get a human-readable key label
            if (key.keyLabel.isNotEmpty) {
              keyLabel = key.keyLabel.toUpperCase();
            }

            if (keyLabel != null && keyLabel.isNotEmpty) {
              controller.assignKeyboardShortcut(padIndex, keyLabel);
              Get.back();
            }
          }
        },
        child: AlertDialog(
          title: const Text('Assign Keyboard Shortcut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Press any key to assign it to this pad.'),
              const SizedBox(height: 16),
              if (controller.pads[padIndex].keyboardShortcut != null) ...[
                Text(
                  'Current: ${controller.pads[padIndex].keyboardShortcut}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    controller.assignKeyboardShortcut(padIndex, null);
                    Get.back();
                  },
                  child: const Text('Remove Shortcut'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: Get.back, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  void _showMidiDevicesDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('MIDI Devices'),
        content: SizedBox(
          width: 300,
          child: Obx(() {
            final devices = controller.midiService.devices;
            final connected = controller.midiService.connectedDevice.value;
            final wsStatus = controller.sidecarService.wsConnectionStatus.value;
            final sidecarStatus = controller.sidecarService.sidecarStatus.value;

            // Show loading if not connected to WS yet
            if (wsStatus != 'Connected') {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Sidecar: $sidecarStatus'),
                  Text('Connection: $wsStatus'),
                  if (controller.sidecarService.lastError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.sidecarService.lastError.value,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              );
            }

            if (devices.isEmpty) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No MIDI devices found.'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: controller.midiService.refreshDevices,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) {
                    final d = devices[i];
                    final isConnected = connected?.id == d.id;
                    return ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.id),
                      trailing: isConnected
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () {
                        if (!isConnected) {
                          controller.midiService.connect(d);
                        } else {
                          controller.midiService.disconnect();
                        }
                      },
                    );
                  },
                ),
                const Divider(),
                TextButton.icon(
                  onPressed: controller.midiService.refreshDevices,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh List'),
                ),
              ],
            );
          }),
        ),
        actions: [
          TextButton(
            onPressed: controller.midiService.refreshDevices,
            child: const Text('Refresh'),
          ),
          TextButton(onPressed: Get.back, child: const Text('Close')),
        ],
      ),
    );
  }

  void _showAudioOutputDialog(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Audio Output Device'),
        content: SizedBox(
          width: 350,
          child: Obx(() {
            final devices = controller.audioService.outputDevices;
            final selected = controller.audioService.selectedDevice.value;

            if (devices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No audio output devices found.'),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (ctx, i) {
                final device = devices[i];
                final isSelected = selected?.id == device.id;
                final isDefault = device.isDefault;

                return ListTile(
                  title: Text(device.name),
                  subtitle: isDefault ? const Text('System Default') : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () async {
                    await controller.selectAudioDevice(device);
                  },
                );
              },
            );
          }),
        ),
        actions: [
          TextButton(
            onPressed: controller.audioService.refreshOutputDevices,
            child: const Text('Refresh'),
          ),
          TextButton(onPressed: Get.back, child: const Text('Close')),
        ],
      ),
    );
  }

  void _showMidiLearnDialog(int padIndex) {
    StreamSubscription? sub;
    Get.dialog(
      AlertDialog(
        title: const Text('Assign MIDI Trigger'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Press a key on your MIDI controller...'),
            const SizedBox(height: 16),
            Obx(() {
              final current = controller.pads[padIndex].midiNote;
              if (current != null) {
                return Column(
                  children: [
                    Text(
                      'Current: Note $current',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        controller.assignMidiNote(padIndex, null);
                        sub?.cancel();
                        Get.back();
                      },
                      child: const Text('Remove Assignment'),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              sub?.cancel();
              Get.back();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((_) => sub?.cancel());

    sub = controller.midiService.noteStream.listen((event) {
      if (event.type == MidiEventType.noteOn) {
        controller.assignMidiNote(padIndex, event.note);
        sub?.cancel();
        if (Get.isDialogOpen ?? false) Get.back();
      }
    });
  }

  void _showPadOptions(BuildContext context, int index, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        const PopupMenuItem(
          value: 'file',
          child: ListTile(
            leading: Icon(Icons.audio_file),
            title: Text('Assign File'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'keyboard',
          child: ListTile(
            leading: Icon(Icons.keyboard),
            title: Text('Keyboard Shortcut'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'midi',
          child: ListTile(
            leading: Icon(Icons.piano),
            title: Text('MIDI Trigger'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'routing',
          child: ListTile(
            leading: Icon(Icons.router),
            title: Text('Audio Routing'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'filters',
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Filters & DSP'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: ListTile(
            leading: Icon(Icons.clear),
            title: Text('Clear Pad'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    ).then((value) {
      if (value == 'file') controller.assignFileToPad(index);
      if (value == 'rename') controller.startRenamingPad(index);
      if (value == 'keyboard') _showKeyboardShortcutDialog(index);
      if (value == 'midi') _showMidiLearnDialog(index);
      if (value == 'routing') _showAudioRoutingDialog(index);
      if (value == 'filters') _showFilterDialog(index);
      if (value == 'clear') controller.clearPad(index);
    });
  }

  void _showAudioRoutingDialog(int index) {
    Get.dialog(
      AlertDialog(
        title: const Text('Audio Routing (Bus)'),
        content: SizedBox(
          width: 400,
          child: Obx(() {
            final devices = controller.audioService.outputDevices;
            final pad = controller.pads[index];
            final currentDeviceId = pad.deviceId;
            final currentChannels = pad.outputChannels ?? [];

            // Get channel count for selected device (or global default)
            final channelCount = controller.audioService.getDeviceChannels(
              currentDeviceId,
            );

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Select Output Device',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Global Default'),
                    subtitle: const Text(
                      'Use the system/global selected device',
                    ),
                    trailing: currentDeviceId == null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      controller.assignDeviceIdToPad(index, null);
                    },
                  ),
                  const Divider(),
                  ...devices.map((device) {
                    final isSelected = currentDeviceId == device.id;
                    return ListTile(
                      title: Text(device.name),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () {
                        controller.assignDeviceIdToPad(index, device.id);
                      },
                    );
                  }),
                  const SizedBox(height: 24),
                  const Text(
                    '2. Channel Mapping',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (channelCount <= 0)
                    const Text('No channels available for this device.')
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(channelCount, (i) {
                        final isSelected = currentChannels.contains(i);
                        return FilterChip(
                          label: Text('Ch ${i + 1}'),
                          selected: isSelected,
                          onSelected: (selected) {
                            final newList = List<int>.from(currentChannels);
                            if (selected) {
                              newList.add(i);
                            } else {
                              newList.remove(i);
                            }
                            newList.sort();
                            controller.assignOutputChannelsToPad(
                              index,
                              newList.isEmpty ? null : newList,
                            );
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            controller.assignOutputChannelsToPad(index, [0, 1]);
                          },
                          child: const Text('Stereo (1+2)'),
                        ),
                        TextButton(
                          onPressed: () {
                            controller.assignOutputChannelsToPad(index, null);
                          },
                          child: const Text('Reset to Default'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
        actions: [TextButton(onPressed: Get.back, child: const Text('Done'))],
      ),
    );
  }

  void _showFilterDialog(int index) {
    Get.dialog(
      AlertDialog(
        title: const Text('Filters & DSP'),
        content: SizedBox(
          width: 350,
          child: Obx(() {
            final pad = controller.pads[index];
            final currentType = pad.filterType;
            final currentFreq = pad.filterFrequency;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filter Type',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['none', 'lowpass', 'highpass'].map((type) {
                    return ChoiceChip(
                      label: Text(type.toUpperCase()),
                      selected: currentType == type,
                      onSelected: (val) {
                        if (val) {
                          controller.updateFilterForPad(
                            index,
                            type,
                            currentFreq,
                          );
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cutoff Frequency',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${currentFreq.toInt()} Hz',
                      style: const TextStyle(fontFamily: 'Courier'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: currentFreq,
                  min: 20.0,
                  max: 20000.0,
                  divisions: 100,
                  label: '${currentFreq.toInt()} Hz',
                  onChanged: currentType == 'none'
                      ? null
                      : (val) {
                          controller.updateFilterForPad(
                            index,
                            currentType,
                            val,
                          );
                        },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adjust cutoff to perform frequency sweeps.',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            );
          }),
        ),
        actions: [TextButton(onPressed: Get.back, child: const Text('Done'))],
      ),
    );
  }

  Material _pad(
    Color color,
    bool hasFile,
    int index,
    Pad pad,
    String fileName,
  ) {
    double? progress;
    if (hasFile) {
      final len = controller.audioService.getLength(pad.path!);
      if (len.inMilliseconds > 0) {
        final pos = controller.audioService.getPosition(pad.path!);
        progress = pos.inMilliseconds / len.inMilliseconds;
      } else {
        progress = 0.0;
      }
    }
    final isPlaying = hasFile && controller.audioService.isPlaying(pad.path!);
    final isPaused = hasFile && controller.audioService.isPaused(pad.path!);

    // Blend base color towards white when playing for a clear visual change.
    final baseColor = color.withOpacity(hasFile ? 1 : 0.4);
    final playingColor = Color.fromARGB(255, 3, 165, 0); // Light Blue 300
    final bgColor = isPlaying ? playingColor.withOpacity(0.95) : baseColor;

    // Timer text
    String timerText = '';
    if (hasFile && (isPlaying || isPaused)) {
      final pos = controller.audioService.getPosition(pad.path!);
      final len = controller.audioService.getLength(pad.path!);
      timerText = '${_formatDuration(pos)} / ${_formatDuration(len)}';
    }

    // --- Waveform Data ---
    final waveform = hasFile
        ? controller.audioService.getWaveform(pad.path!)
        : null;
    if (hasFile && waveform == null) {
      controller.audioService.loadWaveform(pad.path!);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Tap handling is now in parent GestureDetector based on Edit Mode
        onTap: null,
        onLongPress: null,
        child: Stack(
          children: [
            // Waveform Background
            if (hasFile && waveform != null)
              Positioned.fill(
                child: StreamBuilder<String>(
                  stream: controller.audioService.waveformUpdates,
                  builder: (context, snapshot) {
                    // Re-fetch waveform if update matches path (or always for now)
                    // Optimization: check snapshot.data == pad.path
                    final currentWave = controller.audioService.getWaveform(
                      pad.path!,
                    );
                    if (currentWave == null) return const SizedBox();

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: WaveformPainter(
                          data: currentWave,
                          color: Colors.white.withOpacity(0.2),
                          progress: progress ?? 0.0,
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Top-Left: Pad Name and Keyboard Shortcut
            Positioned(
              top: 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(() {
                    if (controller.editingPadIndex.value == index) {
                      return SizedBox(
                        width: 120,
                        height: 30,
                        child: TextField(
                          controller: controller.renamePadInputController,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              controller.savePadName(index, val.trim());
                            } else {
                              controller.cancelRenamingPad();
                            }
                          },
                          onTapOutside: (_) => controller.cancelRenamingPad(),
                        ),
                      );
                    } else {
                      return GestureDetector(
                        onTap: () => controller.startRenamingPad(index),
                        child: Text(
                          pad.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                  }),
                  if (controller.pads[index].keyboardShortcut != null ||
                      controller.pads[index].deviceId != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (controller.pads[index].keyboardShortcut != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              controller.pads[index].keyboardShortcut!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (controller.pads[index].deviceId != null)
                          Tooltip(
                            message: 'Routed to specific output',
                            child: Icon(
                              Icons.router,
                              size: 14,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Center: Icon (Play/Pause)
            Center(
              child: Icon(
                !hasFile
                    ? Icons.add
                    : (isPlaying && !isPaused ? Icons.pause : Icons.play_arrow),
                color: Colors.white.withOpacity(0.8),
                size: 48,
              ),
            ),
            // Bottom: Controls & Info
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (timerText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      timerText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (hasFile) ...[
                    SizedBox(
                      height: 20,
                      child: SliderTheme(
                        data: SliderTheme.of(Get.context!).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                          trackHeight: 2,
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withOpacity(0.2),
                        ),
                        child: Slider(
                          value: (progress ?? 0.0).clamp(0.0, 1.0),
                          onChanged: (v) => controller.seekPad(index, v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.replay,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => controller.restartPad(index),
                          tooltip: 'Restart',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.replay_5,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => controller.skipBackward(index),
                          tooltip: '-5s',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.forward_5,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => controller.skipForward(index),
                          tooltip: '+5s',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (isPlaying || isPaused)
                          IconButton(
                            icon: const Icon(
                              Icons.stop,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () => controller.stopPad(index),
                            tooltip: 'Stop',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Long-press to assign',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            // Top-Right: Controls (Loop & Delete)
            if (hasFile)
              Positioned(
                top: 4,
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Keyboard Shortcut Icon
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showKeyboardShortcutDialog(index),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.keyboard,
                            size: 20,
                            color:
                                controller.pads[index].keyboardShortcut != null
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                    // Loop Icon
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => controller.toggleLoop(index),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.loop,
                            size: 20,
                            color: controller.pads[index].isLooping
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                    // Delete Icon
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Get.dialog(
                            AlertDialog(
                              title: const Text('Clear Pad'),
                              content: const Text(
                                'Are you sure you want to remove the audio from this pad?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Get.back(),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    controller.clearPad(index);
                                    Get.back();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _showSettingsDialog(BuildContext context) {
    final urlCtrl = TextEditingController(text: controller.remoteEndpointUrl);
    final localIp = controller.localApiService.localIp.value;
    final apiEndpoint = 'http://$localIp:9696/api/v1/state';

    Get.dialog(
      AlertDialog(
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Local API Server',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildInfoTile('Local IP:', localIp),
            _buildInfoTile('Endpoint:', apiEndpoint, isCopyable: true),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Remote Webhook URL (POST)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                hintText: 'http://example.com/webhook',
                border: OutlineInputBorder(),
                helperText: 'App will POST state here every 1s',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              controller.updateRemoteEndpoint(urlCtrl.text.trim());
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, {bool isCopyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCopyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                if (Get.context != null) {
                  ScaffoldMessenger.of(Get.context!).showSnackBar(
                    const SnackBar(
                      content: Text('Endpoint copied to clipboard'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      width: 300,
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

// A lightweight master-level meter that attempts to read levels from audioService.
// Falls back to a subtle animated approximation when any pad is playing.
class _MasterAudioMeter extends StatefulWidget {
  final HomeController controller;
  const _MasterAudioMeter({required this.controller});

  @override
  State<_MasterAudioMeter> createState() => _MasterAudioMeterState();
}

class _MasterAudioMeterState extends State<_MasterAudioMeter> {
  Timer? _timer;
  double _levelL = 0.0, _levelR = 0.0;
  double _peakL = 0.0, _peakR = 0.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final levels = _readLevels();
    final newL = levels.$1.clamp(0.0, 1.0);
    final newR = levels.$2.clamp(0.0, 1.0);

    // Attack fast, decay slow
    const decay = 0.85;
    final nextL = newL > _levelL ? newL : _levelL * decay;
    final nextR = newR > _levelR ? newR : _levelR * decay;

    // Peak-hold decay
    final nextPeakL = math.max(newL, _peakL - 0.02);
    final nextPeakR = math.max(newR, _peakR - 0.02);

    if (!mounted) return;
    setState(() {
      _levelL = nextL;
      _levelR = nextR;
      _peakL = nextPeakL;
      _peakR = nextPeakR;
    });
  }

  // Try a few common shapes that an audio service might expose.
  (double, double) _readLevels() {
    final svc = widget.controller.audioService as dynamic;
    double l = 0.0, r = 0.0;

    // Try getMasterLevels(): [l, r] or {left/right}
    try {
      final fn = (svc.getMasterLevels as Function);
      final res = fn();
      if (res is List && res.isNotEmpty) {
        l = _numToDouble(res[0]);
        r = _numToDouble(res.length > 1 ? res[1] : res[0]);
        return (l, r);
      } else if (res is Map) {
        l = _numToDouble(res['left'] ?? res['l'] ?? res['L']);
        r = _numToDouble(res['right'] ?? res['r'] ?? res['R'] ?? l);
        return (l, r);
      }
    } catch (_) {
      // ignore
    }

    // Try fields masterRmsL/masterRmsR or masterPeakL/masterPeakR
    try {
      l = _numToDouble(svc.masterRmsL ?? svc.masterPeakL ?? svc.masterLevel);
      r = _numToDouble(
        svc.masterRmsR ?? svc.masterPeakR ?? svc.masterLevel ?? l,
      );
      if (l > 0 || r > 0) return (l, r);
    } catch (_) {
      // ignore
    }

    // Try getMasterLevel(): mono
    try {
      final fn = (svc.getMasterLevel as Function);
      final m = _numToDouble(fn());
      if (m > 0) return (m, m);
    } catch (_) {
      // ignore
    }

    // Fallback: If anything is playing, show a subtle animated approximation.
    final anyPlaying = _anyPadPlaying();
    if (!anyPlaying) return (0.0, 0.0);

    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final approxL = 0.35 + 0.25 * (0.5 + 0.5 * math.sin(t * 7.0));
    final approxR = 0.35 + 0.25 * (0.5 + 0.5 * math.sin(t * 8.2 + 1.3));
    return (approxL, approxR);
  }

  bool _anyPadPlaying() {
    try {
      for (final Pad p in widget.controller.pads) {
        final path = p.path;
        if (path != null && widget.controller.audioService.isPlaying(path)) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  double _numToDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

  Color _meterColor(double x, ColorScheme scheme) {
    if (x < 0.7) return Colors.greenAccent.shade400;
    if (x < 0.9) return Colors.orangeAccent.shade400;
    return Colors.redAccent.shade400;
  }

  Widget _buildBar(double level, double peak, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (_, c) {
        final h = c.maxHeight;
        final w = c.maxWidth;
        final fillH = h * level.clamp(0.0, 1.0);
        final peakY = h * (1.0 - peak.clamp(0.0, 1.0));

        return Stack(
          children: [
            // Track
            Container(
              width: w,
              decoration: BoxDecoration(
                color: scheme.surfaceVariant.withOpacity(0.55),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.6),
                  width: 1,
                ),
              ),
            ),
            // Fill
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 40),
                width: w,
                height: fillH,
                decoration: BoxDecoration(
                  color: _meterColor(level, scheme),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(6),
                  ),
                ),
              ),
            ),
            // Peak hold line
            Positioned(
              left: 0,
              right: 0,
              top: peakY - 1,
              height: 2,
              child: Container(color: scheme.onSurface.withOpacity(0.8)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.9),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Master',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildBar(_levelL, _peakL, scheme)),
                const SizedBox(width: 6),
                Expanded(child: _buildBar(_levelR, _peakR, scheme)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'L',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.7)),
              ),
              Text(
                'R',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double progress;

  WaveformPainter({
    required this.data,
    required this.color,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final playedPaint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    // Draw background/unplayed waveform
    _drawWave(canvas, size, paint, data);

    // Draw played portion overlay (optional, or just color difference)
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      _drawWave(canvas, size, playedPaint, data);
      canvas.restore();
    }
  }

  void _drawWave(Canvas canvas, Size size, Paint paint, List<double> waveData) {
    final width = size.width;
    final height = size.height;
    final center = height / 2;

    // We want to draw mirrored waveform
    final count = waveData.length;
    final step = width / count;

    for (int i = 0; i < count; i++) {
      final val = waveData[i];
      final x = i * step;
      // Amplitude scaling: max height is half container
      final amp = val * (height * 0.4);

      // Draw bar (or line)
      // canvas.drawLine(Offset(x, center - amp), Offset(x, center + amp), paint);

      // Rounded rect for cleaner look
      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + step / 2, center),
          width: step * 0.8,
          height: max(2.0, amp * 2),
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  double max(double a, double b) => a > b ? a : b;

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}
