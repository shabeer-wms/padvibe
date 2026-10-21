import 'dart:math' as math;
import 'dart:async'; // added
import 'package:padvibe/app/core/layout/breakpoints.dart';
import 'package:padvibe/app/core/utils/formatters.dart';
import 'package:padvibe/app/data/pad_model.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:padvibe/app/service/midi_interface_service.dart'; // updated
import '../controllers/home_controller.dart';
import 'package:padvibe/app/core/widgets/panels.dart';
import 'mixer/fader_dialog.dart';
import 'pad_settings/pad_settings_dialog.dart';
import 'settings/settings_dialog.dart';

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
    return Formatters.formatRemaining(secs);
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
                                final text = Formatters.formatRemaining(secs);
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
    final expanded = WindowSize.of(context).isExpanded;
    return Scaffold(
      appBar: _appBar(context),
      endDrawer: expanded
          ? null
          : Drawer(
              width: 340,
              child: SafeArea(
                child: _buildMasterMonitor(context, docked: false),
              ),
            ),
      body: Focus(
        autofocus: true,
        focusNode: controller.focusNode,
        onKeyEvent: (node, event) {
          // IMPORTANT: Ignore shortcuts if we are currently editing a pad name
          if (controller.editingPadIndex.value != -1) {
            return KeyEventResult.ignored;
          }

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
                        // Reactive to pad list mutations (toggle loop, assign file, etc.)
                        controller.pads.length;
                        // Reactive to play/pause state changes
                        controller.audioService.activeHandles.length;
                        // Reactive to manual seeks while paused
                        controller.forceUpdate.value;
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Obx(() {
                                const spacing = 12.0;
                                final cols = responsiveGridColumns(
                                  width: constraints.maxWidth,
                                  preferred: controller.gridColumns.value,
                                );
                                final childAspect = 4 / 3;

                                final foregroundIndices = <int>[];
                                final backgroundIndices = <int>[];

                                for (
                                  int i = 0;
                                  i < controller.pads.length;
                                  i++
                                ) {
                                  if (controller.pads[i].isBackground) {
                                    backgroundIndices.add(i);
                                  } else {
                                    foregroundIndices.add(i);
                                  }
                                }

                                return CustomScrollView(
                                  slivers: [
                                    if (foregroundIndices.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8.0,
                                          ),
                                          child: Text(
                                            'FOREGROUND PADS',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: cols,
                                              mainAxisSpacing: spacing,
                                              crossAxisSpacing: spacing,
                                              childAspectRatio: childAspect,
                                            ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) {
                                            final index = foregroundIndices[i];
                                            return _buildPadItem(
                                              context,
                                              index,
                                              colors,
                                            );
                                          },
                                          childCount: foregroundIndices.length,
                                        ),
                                      ),
                                    ],
                                    if (backgroundIndices.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 24.0,
                                            bottom: 8.0,
                                          ),
                                          child: Text(
                                            'BACKGROUND PADS (API EXCLUDED)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: cols,
                                              mainAxisSpacing: spacing,
                                              crossAxisSpacing: spacing,
                                              childAspectRatio: childAspect,
                                            ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) {
                                            final index = backgroundIndices[i];
                                            return _buildPadItem(
                                              context,
                                              index,
                                              colors,
                                            );
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
              if (expanded) _buildMasterMonitor(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPadItem(BuildContext context, int index, List<Color> colors) {
    final pad = controller.pads[index];
    final color = colors[index % colors.length];
    final hasFile = pad.path != null;
    final fileName = hasFile ? pad.path!.split('/').last : 'Empty';

    return DropTarget(
      onDragDone: (detail) {
        if (detail.files.isEmpty) return;
        final f = detail.files.first;
        if (!HomeController.isSupportedAudioFile(f.name)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unsupported file type: ${f.name}')),
          );
          return;
        }
        controller.assignFilePathToPad(index, f.path);
      },
      child: _pad(color, hasFile, index, pad, fileName, context),
    );
  }

  AppBar _appBar(BuildContext context) {
    final size = WindowSize.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          const Text('PadVibe'),
        ],
      ),
      actions: [
        // Engine status; opens Diagnostics.
        Obx(() {
          final connected =
              controller.sidecarService.wsConnectionStatus.value == 'Connected';
          final color = connected
              ? const Color(0xFF2E9E5B)
              : (controller.sidecarService.sidecarStatus.value == 'Error'
                    ? const Color(0xFFD64545)
                    : const Color(0xFFD08A00));
          final label = connected ? 'Engine ready' : 'Engine starting…';
          return Tooltip(
            message: label,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => SettingsDialog.show(
                controller,
                section: SettingsSection.diagnostics,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!size.isCompact) ...[
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        if (!size.isCompact) ...[
          IconButton(
            tooltip: 'Floating timer',
            icon: const Icon(Icons.picture_in_picture_alt_outlined),
            onPressed: () => _toggleTimerOverlay(context),
          ),
          IconButton(
            tooltip: 'Audio output',
            icon: const Icon(Icons.volume_up_outlined),
            onPressed: () =>
                SettingsDialog.show(controller, section: SettingsSection.audio),
          ),
          IconButton(
            tooltip: 'MIDI devices',
            icon: const Icon(Icons.piano_outlined),
            onPressed: () =>
                SettingsDialog.show(controller, section: SettingsSection.midi),
          ),
        ],
        // Below the expanded breakpoint the mixer lives in a side drawer.
        if (!size.isExpanded)
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Mixer',
              icon: const Icon(Icons.tune),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => SettingsDialog.show(controller),
        ),
        if (size.isCompact)
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'timer':
                  _toggleTimerOverlay(context);
                case 'audio':
                  SettingsDialog.show(
                    controller,
                    section: SettingsSection.audio,
                  );
                case 'midi':
                  SettingsDialog.show(
                    controller,
                    section: SettingsSection.midi,
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'timer',
                child: ListTile(
                  leading: Icon(Icons.picture_in_picture_alt_outlined),
                  title: Text('Floating timer'),
                ),
              ),
              PopupMenuItem(
                value: 'audio',
                child: ListTile(
                  leading: Icon(Icons.volume_up_outlined),
                  title: Text('Audio output'),
                ),
              ),
              PopupMenuItem(
                value: 'midi',
                child: ListTile(
                  leading: Icon(Icons.piano_outlined),
                  title: Text('MIDI devices'),
                ),
              ),
            ],
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _toggleTimerOverlay(BuildContext context) {
    if (_timerOverlay == null) {
      _showTimerOverlay(context);
    } else {
      _hideTimerOverlay();
    }
  }

  Widget _buildBottomPanel(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
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
                            onDoubleTap: () => _renameTab(index),
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
          SizedBox(width: narrow ? 8 : 16),
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
                  narrow
                      ? Formatters.formatRemaining(secs)
                      : 'Remaining: ${Formatters.formatRemaining(secs)}',
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
          SizedBox(width: narrow ? 4 : 16),
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

  Widget _buildMasterMonitor(BuildContext context, {bool docked = true}) {
    return Container(
      width: docked ? 320 : null,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: docked
            ? Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              )
            : null,
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

  Future<void> _showAddTabDialog(BuildContext context) async {
    final name = await promptDialog(
      title: 'New tab',
      label: 'Tab name',
      confirmLabel: 'Add',
      icon: Icons.tab,
    );
    if (name != null) controller.addTab(name);
  }

  Future<void> _renameTab(int index) async {
    final name = await promptDialog(
      title: 'Rename tab',
      label: 'Tab name',
      initial: controller.groups[index].name,
      icon: Icons.tab,
    );
    if (name != null) controller.renameTab(index, name);
  }

  void _showTabOptions(BuildContext context, int index, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: const [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'rename') {
        await _renameTab(index);
      } else if (value == 'delete') {
        final ok = await confirmDialog(
          title: 'Delete tab?',
          message:
              'All pads in “${controller.groups[index].name}” and their audio will be removed.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) controller.deleteTab(index);
      }
    });
  }

  /// Right-click menu: the few things you do all the time. Everything else
  /// lives in the pad settings dialog.
  void _showPadOptions(BuildContext context, int index, Offset position) {
    final hasFile = controller.pads[index].path != null;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'file',
          child: ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: Text(hasFile ? 'Replace file…' : 'Assign file…'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Pad settings…'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        if (hasFile) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'clear',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Clear pad', style: TextStyle(color: Colors.red)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        ],
      ],
    ).then((value) {
      switch (value) {
        case 'file':
          controller.assignFileToPad(index);
        case 'rename':
          controller.startRenamingPad(index);
        case 'settings':
          PadSettingsDialog.show(controller, index);
        case 'clear':
          _confirmClearPad(index);
      }
    });
  }

  Future<void> _confirmClearPad(int index) async {
    final pad = controller.pads[index];
    final ok = await confirmDialog(
      title: 'Clear ${pad.name}?',
      message:
          'The audio is removed from this pad and its copy in the PadVibe library is deleted. Your original file is not touched.',
      confirmLabel: 'Clear pad',
      destructive: true,
    );
    if (ok) controller.clearPad(index);
  }

  Material _pad(
    Color color,
    bool hasFile,
    int index,
    Pad pad,
    String fileName,
    BuildContext context,
  ) {
    final isPlaying = hasFile && controller.audioService.isPlaying(pad.path!);
    final isPaused = hasFile && controller.audioService.isPaused(pad.path!);

    // Every pad keeps its palette color: assigned pads are vivid with white
    // text, empty pads are a soft tint of the same color so the grid stays
    // colorful and the two states are still easy to tell apart.
    final scheme = Theme.of(context).colorScheme;
    final accent = HSLColor.fromColor(
      color,
    ).withSaturation(0.72).withLightness(0.46).toColor();
    final bgColor = !hasFile
        ? Color.alphaBlend(accent.withValues(alpha: 0.5), scheme.surface)
        : (isPlaying ? const Color(0xFF1E9E48) : accent);
    final fg = hasFile ? Colors.white : scheme.onSurface;
    final fgMuted = hasFile ? Colors.white70 : scheme.onSurfaceVariant;
    final iconColor = hasFile ? Colors.white : accent;

    // --- Waveform Data ---
    final waveform = hasFile
        ? controller.audioService.getWaveform(pad.path!)
        : null;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: hasFile
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
        child: LayoutBuilder(
          builder: (context, box) {
            // Small tiles (narrow windows / many columns) drop secondary chrome.
            final small = box.maxWidth < 200 || box.maxHeight < 150;
            return Stack(
              children: [
                // Waveform Background
                if (hasFile && waveform != null)
                  Positioned.fill(
                    child: StreamBuilder<String>(
                      stream: controller.audioService.waveformUpdates,
                      builder: (context, snapshot) {
                        final currentWave = controller.audioService.getWaveform(
                          pad.path!,
                        );
                        if (currentWave == null) return const SizedBox();

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _PadWaveform(
                            path: pad.path!,
                            controller: controller,
                            data: currentWave,
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
                              onTapOutside: (_) =>
                                  controller.cancelRenamingPad(),
                            ),
                          );
                        } else {
                          return GestureDetector(
                            onTap: () => controller.startRenamingPad(index),
                            child: Text(
                              pad.name,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontSize: small ? 14 : 16,
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
                // Center: Icon (Play/Pause) or Loading Indicator
                Center(
                  child: pad.isLoading
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          !hasFile
                              ? Icons.add
                              : (isPlaying && !isPaused
                                    ? Icons.pause
                                    : Icons.play_arrow),
                          color: iconColor.withValues(
                            alpha: hasFile ? 0.85 : 0.9,
                          ),
                          size: small ? 30 : 44,
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
                        style: TextStyle(color: fgMuted, fontSize: 13),
                      ),
                      if (hasFile)
                        _PadProgressWidget(
                          path: pad.path!,
                          controller: controller,
                          index: index,
                          compact: small,
                        )
                      else if (!small)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Long-press to assign',
                            style: TextStyle(
                              color: fgMuted.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
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
                        // Keyboard Shortcut Icon (hidden on small tiles)
                        if (!small)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => PadSettingsDialog.show(
                                controller,
                                index,
                                tab: PadSettingsTab.triggers,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(small ? 5 : 8),
                                child: Icon(
                                  Icons.keyboard,
                                  size: small ? 18 : 20,
                                  color:
                                      controller.pads[index].keyboardShortcut !=
                                          null
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
                              padding: EdgeInsets.all(small ? 5 : 8),
                              child: Icon(
                                Icons.loop,
                                size: small ? 18 : 20,
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
                              _confirmClearPad(index);
                            },
                            child: Padding(
                              padding: EdgeInsets.all(small ? 5 : 8),
                              child: Icon(
                                Icons.delete_outline,
                                size: small ? 18 : 20,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddFaderDialog(BuildContext context) async {
    final name = await promptDialog(
      title: 'New fader',
      label: 'Fader name',
      confirmLabel: 'Create',
      icon: Icons.linear_scale,
    );
    if (name != null) controller.addFader(name);
  }

  void _showFaderSettings(BuildContext context, int index) =>
      FaderDialog.show(controller, index);
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
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
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
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
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
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Icon(
                  Icons.settings,
                  size: 10,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
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
    const riseFactor = 1.0; // Instant rise

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
    if (_peakHoldCounter > 60) {
      // Hold for ~1 sec
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
              Obx(
                () => Text(
                  '${(widget.controller.audioService.masterVolume.value * 100).toInt()}%',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 10,
                    fontFamily: "Courier",
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 18,
                          ),
                          activeTrackColor: scheme.primary,
                          inactiveTrackColor: scheme.surfaceContainerHighest,
                          thumbColor: scheme.primary,
                        ),
                        child: Slider(
                          value:
                              widget.controller.audioService.masterVolume.value,
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
                              child: _LEDMeterBar(
                                level: _displayedL,
                                peak: _peakHoldL,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "L",
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Right Meter
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _LEDMeterBar(
                                level: _displayedR,
                                peak: _peakHoldR,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "R",
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
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
                        BoxShadow(
                          color: scheme.onSurface.withValues(alpha: 0.3),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

              // Grid lines overlay for "segments" feel
              Column(
                children: List.generate(
                  12,
                  (index) => Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: scheme.surface.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The pad's waveform with a white playhead: the part already played is
/// brighter and a white line marks the current position while it plays.
class _PadWaveform extends StatefulWidget {
  final String path;
  final HomeController controller;
  final List<double> data;

  const _PadWaveform({
    required this.path,
    required this.controller,
    required this.data,
  });

  @override
  State<_PadWaveform> createState() => _PadWaveformState();
}

class _PadWaveformState extends State<_PadWaveform> {
  Timer? _timer;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final svc = widget.controller.audioService;
    final active = svc.isPlaying(widget.path) || svc.isPaused(widget.path);
    final len = svc.getLength(widget.path);
    final next = active && len.inMilliseconds > 0
        ? (svc.getPosition(widget.path).inMilliseconds / len.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;
    if (next != _progress) setState(() => _progress = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(
        data: widget.data,
        color: Colors.white.withValues(alpha: 0.2),
        progress: _progress,
      ),
    );
  }
}

class _PadProgressWidget extends StatefulWidget {
  final String path;
  final HomeController controller;
  final int index;

  /// Small tiles show only the time and seek bar; the skip/restart buttons
  /// would not fit.
  final bool compact;

  const _PadProgressWidget({
    required this.path,
    required this.controller,
    required this.index,
    this.compact = false,
  });

  @override
  State<_PadProgressWidget> createState() => _PadProgressWidgetState();
}

class _PadProgressWidgetState extends State<_PadProgressWidget> {
  Timer? _timer;
  double _progress = 0.0;
  String _timerText = '';
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final svc = widget.controller.audioService;
    final len = svc.getLength(widget.path);
    final pos = svc.getPosition(widget.path);
    final isPlaying = svc.isPlaying(widget.path);
    final isPaused = svc.isPaused(widget.path);
    final active = isPlaying || isPaused;

    final newProgress = len.inMilliseconds > 0
        ? (pos.inMilliseconds / len.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final newTimerText = active
        ? '${Formatters.formatDuration(pos)} / ${Formatters.formatDuration(len)}'
        : '';

    if (newProgress != _progress ||
        newTimerText != _timerText ||
        active != _isActive) {
      setState(() {
        _progress = newProgress;
        _timerText = newTimerText;
        _isActive = active;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final index = widget.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_timerText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _timerText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 4),
        SizedBox(
          height: 20,
          child: SliderTheme(
            data: SliderTheme.of(Get.context!).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              trackHeight: 2,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _progress.clamp(0.0, 1.0),
              onChanged: (v) => controller.seekPad(index, v),
            ),
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay, color: Colors.white, size: 20),
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
                if (_isActive)
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.white, size: 20),
                    onPressed: () => controller.stopPad(index),
                    tooltip: 'Stop',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ],
      ],
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
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    // Draw background/unplayed waveform
    _drawWave(canvas, size, paint, data);

    // Draw played portion overlay (optional, or just color difference)
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      _drawWave(canvas, size, playedPaint, data);
      canvas.restore();

      // White playhead: a line across the whole tile with a small cap on top.
      final x = (size.width * progress).clamp(1.0, size.width - 1.0);
      final line = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0;
      canvas.drawShadow(
        Path()..addRect(Rect.fromLTWH(x - 1, 0, 2, size.height)),
        Colors.black,
        2.0,
        false,
      );
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawCircle(Offset(x, 4), 4, line);
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
