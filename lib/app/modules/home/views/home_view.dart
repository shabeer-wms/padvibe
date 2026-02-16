import 'dart:math' as math;
import 'dart:async'; // added
import 'package:padvibe/app/data/pad_model.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:padvibe/app/service/midi_interface_service.dart'; // updated
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
                          ).colorScheme.surface.withValues(alpha: 0.98),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.primary.withValues(alpha: 0.35),
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
                                    color: accent.withValues(
                                      alpha: blinking ? 1.0 : 0.45,
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
                                      color: Theme.of(ctx).colorScheme.onSurface
                                          .withValues(alpha: 0.6),
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
          // IMPORTANT: Ignore shortcuts if we are currently editing a pad name
          if (controller.editingPadIndex.value != -1) return KeyEventResult.ignored;

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
        child: GestureDetector(
          onTap: () => controller.focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Obx(() {
                      // Read the ticker to trigger rebuilds for progress bars.
                      controller.remainingSeconds.value;
                      controller.heartbeat.value; // Ensures background pads update too
                      // Also observe active handles for immediate play/pause updates
                      controller.audioService.activeHandles.length;
                      // Also observe manual force updates (e.g. seeking while paused)
                      controller.forceUpdate.value;
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Obx(() {
                              const spacing = 12.0;
                              final cols = controller.gridColumns.value;
                              final childAspect = 4 / 3;

                              final foregroundIndices = <int>[];
                              final backgroundIndices = <int>[];

                              for (int i = 0; i < controller.pads.length; i++) {
                                if (controller.pads[i].isBackground) {
                                  backgroundIndices.add(i);
                                } else {
                                  foregroundIndices.add(i);
                                }
                              }

                              return CustomScrollView(
                                slivers: [
                                  if (foregroundIndices.isNotEmpty) ...[
                                    const SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(vertical: 8.0),
                                        child: Text(
                                          'FOREGROUND PADS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.2,
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SliverGrid(
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cols,
                                        mainAxisSpacing: spacing,
                                        crossAxisSpacing: spacing,
                                        childAspectRatio: childAspect,
                                      ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) {
                                          final index = foregroundIndices[i];
                                          return _buildPadItem(context, index, colors);
                                        },
                                        childCount: foregroundIndices.length,
                                      ),
                                    ),
                                  ],
                                  if (backgroundIndices.isNotEmpty) ...[
                                    const SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 24.0, bottom: 8.0),
                                        child: Text(
                                          'BACKGROUND PADS (API EXCLUDED)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.2,
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SliverGrid(
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cols,
                                        mainAxisSpacing: spacing,
                                        crossAxisSpacing: spacing,
                                        childAspectRatio: childAspect,
                                      ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) {
                                          final index = backgroundIndices[i];
                                          return _buildPadItem(context, index, colors);
                                        },
                                        childCount: backgroundIndices.length,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            });
                          },
                        ),
                      );
                    }),
                  ),
                  _buildBottomPanel(context),
                ],
              ),
            ),
            _buildMasterMonitor(context),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildPadItem(BuildContext context, int index, List<Color> colors) {
    final pad = controller.pads[index].obs;
    final color = colors[index % colors.length];
    final hasFile = pad.value.path != null;
    final fileName = hasFile ? pad.value.path!.split('/').last : 'Empty';

    return Obx(
      () => DropTarget(
        onDragDone: (detail) {
          if (detail.files.isEmpty) return;
          final f = detail.files.first;
          if (!f.name.toLowerCase().endsWith('.mp3') &&
              !f.name.toLowerCase().endsWith('.wav') &&
              !f.name.toLowerCase().endsWith('.ogg') &&
              !f.name.toLowerCase().endsWith('.flac') &&
              !f.name.toLowerCase().endsWith('.aac') &&
              !f.name.toLowerCase().endsWith('.m4a')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Unsupported file type: ${f.name}')),
            );
            return;
          }
          controller.assignFilePathToPad(index, f.path);
        },
        child: _pad(
          color,
          hasFile,
          index,
          pad.value,
          fileName,
          context,
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
          tooltip: 'Power',
          icon: const Icon(Icons.power_settings_new),
          onPressed: () {
            if (_timerOverlay == null) {
              _showTimerOverlay(context);
            } else {
              _hideTimerOverlay();
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Tabs section
          Expanded(
            child: Obx(() {
              return Row(
                children: [
                  // Tabs
                  Flexible(
                    child: ListView.separated(
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Add tab button
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddTabDialog(context),
                    tooltip: 'Add Tab',
                    iconSize: 20,
                  ),
                ],
              );
            }),
          ),
          const SizedBox(width: 16),
          // Timer display with icon
          Obx(() {
            final secs = controller.remainingSeconds.value;
            final accent = _urgencyColor(context, secs);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, color: accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Remaining: ${_formatRemaining(secs)}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            );
          }),
          const SizedBox(width: 16),
          // Stop All button
          IconButton(
            tooltip: 'Stop all',
            icon: const Icon(Icons.stop_circle),
            onPressed: controller.stopAll,
            iconSize: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildMasterMonitor(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MixerPanel(
              controller: controller,
              onAddFader: () => _showAddFaderDialog(context),
              onFaderSettings: (index) => _showFaderSettings(context, index),
            ),
          ),
          _MasterAudioMeter(controller: controller),
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
            Future.delayed(const Duration(milliseconds: 100), () {
              if (context.mounted) {
                _showRenameTabPopover(context, index, position);
              }
            });
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
            Future.delayed(const Duration(milliseconds: 100), () {
              if (context.mounted) {
                _showDeleteTabConfirmation(context, index);
              }
            });
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
    final focusNode = FocusNode();
    Get.dialog(
      GestureDetector(
        onTap: () => focusNode.requestFocus(),
        child: KeyboardListener(
          autofocus: true,
          focusNode: focusNode..requestFocus(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent) {
              final key = event.logicalKey;
              
              // Skip modifier keys alone
              if (key == LogicalKeyboardKey.shiftLeft || 
                  key == LogicalKeyboardKey.shiftRight ||
                  key == LogicalKeyboardKey.controlLeft ||
                  key == LogicalKeyboardKey.controlRight ||
                  key == LogicalKeyboardKey.altLeft ||
                  key == LogicalKeyboardKey.altRight ||
                  key == LogicalKeyboardKey.metaLeft ||
                  key == LogicalKeyboardKey.metaRight) {
                return;
              }

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

  void _showPadVolumeSettings(int index) {
    Get.dialog(
      AlertDialog(
        title: const Text('Individual Pad Volume'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() {
              final pad = controller.pads[index];
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Volume:'),
                      Text('${(pad.volume * 100).toInt()}%'),
                    ],
                  ),
                  Slider(
                    value: pad.volume,
                    onChanged: (val) => controller.updatePadVolume(index, val),
                  ),
                  if (pad.faderId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Note: Linked to Mixer Fader',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(Get.context!).colorScheme.secondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Done')),
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
                      'Current: ${MidiNoteEvent.getDisplayNameForId(current)}',
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
      bool isTrigger = false;
      if (event.type == MidiEventType.noteOn) {
        isTrigger = true;
      } else if (event.type == MidiEventType.controlChange &&
          event.velocity > 0) {
        isTrigger = true;
      }

      if (isTrigger) {
        controller.assignMidiNote(padIndex, event.triggerId);
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
          value: 'vol_midi',
          child: ListTile(
            leading: Icon(Icons.volume_up),
            title: Text('Individual Volume'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'background',
          child: ListTile(
            leading: Icon(
              controller.pads[index].isBackground
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            title: const Text('Background Pad'),
            subtitle: const Text('Exclude from Local API'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'mixer',
          child: ListTile(
            leading: Icon(Icons.linear_scale),
            title: Text('Mixer Fader'),
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
      if (value == 'vol_midi') _showPadVolumeSettings(index);
      if (value == 'background') controller.toggleBackground(index);
      if (value == 'mixer') _showFaderAssignmentDialog(index);
      if (value == 'routing') _showAudioRoutingDialog(index);
      if (value == 'filters') _showFilterDialog(index);
      if (value == 'clear') controller.clearPad(index);
    });
  }

  void _showFaderAssignmentDialog(int index) {
    Get.dialog(
      AlertDialog(
        title: const Text('Assign to Mixer Fader'),
        content: SizedBox(
          width: 300,
          child: Obx(() {
            if (controller.faders.isEmpty) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No faders created yet.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Get.back();
                      _showAddFaderDialog(Get.context!);
                    },
                    child: const Text('Create Fader'),
                  ),
                ],
              );
            }

            final currentFaderId = controller.pads[index].faderId;

            return ListView.builder(
              shrinkWrap: true,
              itemCount: controller.faders.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return ListTile(
                    title: const Text('None (Individual Volume)'),
                    trailing: currentFaderId == null
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      controller.assignPadToFader(index, null);
                      Get.back();
                    },
                  );
                }
                final fader = controller.faders[i - 1];
                final isSelected = currentFaderId == fader.id;
                return ListTile(
                  title: Text(fader.name),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    controller.assignPadToFader(index, fader.id);
                    Get.back();
                  },
                );
              },
            );
          }),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
        ],
      ),
    );
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
    BuildContext context,
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
    final baseColor = color.withValues(alpha: hasFile ? 1 : 0.4);
    final playingColor = const Color.fromARGB(255, 3, 165, 0); // Light Blue 300
    final bgColor = isPlaying ? playingColor.withValues(alpha: 0.95) : baseColor;

    // Timer text
    String timerText = '';
    if (hasFile && (isPlaying || isPaused)) {
      final pos = controller.audioService.getPosition(pad.path!);
      final len = controller.audioService.getLength(pad.path!);
      timerText = '${_formatDuration(pos)} / ${_formatDuration(len)}';
    }

    // --- Waveform Data ---
    final waveform = hasFile ? controller.audioService.getWaveform(pad.path!) : null;
    if (hasFile && waveform == null) {
      controller.audioService.loadWaveform(pad.path!);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          controller.focusNode.requestFocus();
          if (hasFile) controller.playPad(index);
        },
        onLongPress: () {
          controller.focusNode.requestFocus();
          controller.assignFileToPad(index);
        },
        onSecondaryTapUp: (details) {
          controller.focusNode.requestFocus();
          _showPadOptions(context, index, details.globalPosition);
        },
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
                          color: Colors.white.withValues(alpha: 0.2),
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
                      controller.pads[index].deviceId != null ||
                      controller.pads[index].faderId != null ||
                      controller.pads[index].isBackground) ...[
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
                              color: Colors.white.withValues(alpha: 0.2),
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
                        if (controller.pads[index].faderId != null)
                          Tooltip(
                            message: 'Linked to Mixer Fader',
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.linear_scale,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        if (controller.pads[index].isBackground)
                          Tooltip(
                            message: 'Background Pad (API Excluded)',
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.visibility_off,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        if (controller.pads[index].deviceId != null)
                          Tooltip(
                            message: 'Routed to specific output',
                            child: Icon(
                              Icons.router,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.6),
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
                color: Colors.white.withValues(alpha: 0.8),
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
                          overlayColor: Colors.white.withValues(alpha: 0.2),
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
                                : Colors.white.withValues(alpha: 0.4),
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
                                : Colors.white.withValues(alpha: 0.4),
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
                            color: Colors.white.withValues(alpha: 0.6),
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
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Sidecar Diagnostics',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Obx(() => _buildInfoTile('Status:', controller.sidecarService.sidecarStatus.value)),
            Obx(() => _buildInfoTile('WS:', controller.sidecarService.wsConnectionStatus.value)),
            Obx(() {
              final err = controller.sidecarService.lastError.value;
              return err.isNotEmpty 
                ? _buildInfoTile('Last Error:', err)
                : const SizedBox.shrink();
            }),
            _buildInfoTile(
              'Logs:', 
              controller.sidecarService.logFilePath,
              isCopyable: true,
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

  void _showAddFaderDialog(BuildContext context) {
    final textCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Add Fader'),
        content: TextField(
          controller: textCtrl,
          decoration: const InputDecoration(hintText: 'Fader Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (textCtrl.text.isNotEmpty) {
                controller.addFader(textCtrl.text);
                Get.back();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showFaderSettings(BuildContext context, int index) {
    final fader = controller.faders[index];
    StreamSubscription? sub;
    
    Get.dialog(
      AlertDialog(
        title: Text('Fader: ${fader.name}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assign MIDI CC to this fader:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Obx(() {
                  final currentCc = controller.faders[index].midiCc;
                  return Column(
                    children: [
                      Text(
                        currentCc != null ? 'Assigned: ${MidiNoteEvent.getDisplayNameForId(currentCc)}' : 'No CC assigned',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (currentCc != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => controller.assignFaderMidiCc(index, null),
                          child: const Text('Remove Assignment'),
                        ),
                      ],
                    ],
                  );
                }),
                const SizedBox(height: 8),
                const Center(child: Text('Move a hardware fader to assign...', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic))),
                const Divider(height: 32),
                const Text('Manage Linked Pads:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Obx(() {
                  final pads = controller.pads;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(pads.length, (pIdx) {
                      final p = pads[pIdx];
                      final isLinked = p.faderId == fader.id;
                      return ChoiceChip(
                        label: Text(p.name, style: const TextStyle(fontSize: 10)),
                        selected: isLinked,
                        onSelected: (val) {
                          controller.assignPadToFader(pIdx, val ? fader.id : null);
                        },
                      );
                    }),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              sub?.cancel();
              Get.back();
            },
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              sub?.cancel();
              controller.removeFader(index);
              Get.back();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Fader'),
          ),
        ],
      ),
    ).then((_) => sub?.cancel());

    sub = controller.midiService.noteStream.listen((event) {
      if (event.type == MidiEventType.controlChange) {
        controller.assignFaderMidiCc(index, event.triggerId);
        sub?.cancel();
        if (Get.isDialogOpen ?? false) Get.back();
      }
    });
  }
}

class _MixerPanel extends StatelessWidget {
  final HomeController controller;
  final VoidCallback onAddFader;
  final Function(int) onFaderSettings;

  const _MixerPanel({
    required this.controller,
    required this.onAddFader,
    required this.onFaderSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MIXER',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onAddFader,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Obx(() {
            if (controller.faders.isEmpty) {
              return Center(
                child: Text(
                  'No faders',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 10),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: controller.faders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final fader = controller.faders[index];
                return _FaderWidget(
                  index: index,
                  fader: fader,
                  controller: controller,
                  onSettings: () => onFaderSettings(index),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _FaderWidget extends StatelessWidget {
  final int index;
  final Fader fader;
  final HomeController controller;
  final VoidCallback onSettings;

  const _FaderWidget({
    required this.index,
    required this.fader,
    required this.controller,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: onSettings,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    fader.name.toUpperCase(),
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Icon(Icons.settings, size: 10, color: scheme.onSurface.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 120,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: scheme.secondary,
                thumbColor: scheme.secondary,
              ),
              child: Slider(
                value: fader.volume,
                onChanged: (val) => controller.updateFaderVolume(index, val),
              ),
            ),
          ),
        ),
        if (fader.midiCc != null)
          Text(
            MidiNoteEvent.getDisplayNameForId(fader.midiCc!),
            style: TextStyle(fontSize: 8, color: scheme.primary),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

// A production-quality master meter with fader
class _MasterAudioMeter extends StatefulWidget {
  final HomeController controller;
  const _MasterAudioMeter({required this.controller});

  @override
  State<_MasterAudioMeter> createState() => _MasterAudioMeterState();
}

class _MasterAudioMeterState extends State<_MasterAudioMeter> {
  // We use a timer for smooth decay animation of the meter bars
  Timer? _timer;
  double _displayedL = 0.0;
  double _displayedR = 0.0;
  double _peakHoldL = 0.0;
  double _peakHoldR = 0.0;
  
  // For peak hold reset
  int _peakHoldCounter = 0;

  @override
  void initState() {
    super.initState();
    // 60 FPS animation loop for smooth meter decay
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    // Read current instantaneous peaks from service
    final svc = widget.controller.audioService;
    // We use peak values for the main bar as they are safer for digital clipping detection
    // RMS could be an inner darker bar if desired, but let's stick to Peak for main visibility.
    final targetL = svc.masterPeakL.value; 
    final targetR = svc.masterPeakR.value;

    // Decay settings
    const decayFactor = 0.85; // How fast the bar drops
    const riseFactor = 1.0;   // Instant rise

    // Apply ballistics
    if (targetL >= _displayedL) {
      _displayedL = _displayedL + (targetL - _displayedL) * riseFactor;
    } else {
      _displayedL *= decayFactor;
    }

    if (targetR >= _displayedR) {
      _displayedR = _displayedR + (targetR - _displayedR) * riseFactor;
    } else {
      _displayedR *= decayFactor;
    }

    // Peak Hold logic (drops slowly after a hold time)
    if (_displayedL > _peakHoldL) {
      _peakHoldL = _displayedL;
      _peakHoldCounter = 0;
    }
    if (_displayedR > _peakHoldR) {
      _peakHoldR = _displayedR;
      _peakHoldCounter = 0;
    }

    _peakHoldCounter++;
    if (_peakHoldCounter > 60) { // Hold for ~1 sec
      _peakHoldL *= 0.95;
      _peakHoldR *= 0.95;
    }
    
    // Clamp
    if (_displayedL < 0.001) _displayedL = 0;
    if (_displayedR < 0.001) _displayedR = 0;

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 130, // Wider to accommodate fader
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface, // Use theme surface color
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MASTER',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
               // Numerical readout of volume
               Obx(() => Text(
                 '${(widget.controller.audioService.masterVolume.value * 100).toInt()}%',
                 style: TextStyle(
                   color: scheme.onSurface, 
                   fontSize: 10, 
                   fontFamily: "Courier",
                   fontWeight: FontWeight.bold,
                 ),
               )),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fader Section
                SizedBox(
                  width: 32,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Obx(() {
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                            elevation: 2,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                          activeTrackColor: scheme.primary,
                          inactiveTrackColor: scheme.surfaceContainerHighest,
                          thumbColor: scheme.primary,
                        ),
                        child: Slider(
                          value: widget.controller.audioService.masterVolume.value,
                          onChanged: (val) {
                            widget.controller.audioService.setMasterVolume(val);
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 16),
                // Meters Section
                Expanded(
                  child: Row(
                    children: [
                      // Left Meter
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _LEDMeterBar(level: _displayedL, peak: _peakHoldL),
                            ),
                            const SizedBox(height: 4),
                            Text("L", style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Right Meter
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _LEDMeterBar(level: _displayedR, peak: _peakHoldR),
                            ),
                            const SizedBox(height: 4),
                            Text("R", style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LEDMeterBar extends StatelessWidget {
  final double level;
  final double peak;

  const _LEDMeterBar({required this.level, required this.peak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Segmented look
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxH = constraints.maxHeight;
        
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Background Track
              Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              
              // Draw gradient/segments
              Container(
                height: maxH * level.clamp(0.0, 1.0),
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF43A047), // Darker green for light UI
                      Color(0xFFFBC02D), // Darker amber
                      Color(0xFFE53935), // Darker red
                    ],
                    stops: [0.6, 0.85, 1.0],
                    tileMode: TileMode.clamp,
                  ),
                ),
              ),

              // Peak Hold Indicator
              if (peak > 0.01)
                Positioned(
                  bottom: maxH * peak.clamp(0.0, 1.0) - 1,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: scheme.onSurface,
                      boxShadow: [
                        BoxShadow(color: scheme.onSurface.withValues(alpha: 0.3), blurRadius: 2),
                      ],
                    ),
                  ),
                ),
                
              // Grid lines overlay for "segments" feel
              Column(
                children: List.generate(12, (index) => Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.surface.withValues(alpha: 0.8), 
                          width: 1.5
                        ),
                      ),
                    ),
                  ),
                )),
              ),
            ],
          ),
        );
      },
    );
  }
}

// WaveformPainter kept as is...
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
      ..color = color.withValues(alpha: 0.9)
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
