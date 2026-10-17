import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

// Building blocks shared by Settings and the pad/mixer dialogs.

/// A titled card of rows, separated by dividers.
class PanelGroup extends StatelessWidget {
  const PanelGroup({
    super.key,
    required this.title,
    this.description,
    this.action,
    required this.children,
  });

  final String title;
  final String? description;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!, style: text.bodySmall?.copyWith(color: muted)),
          ],
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + hint on one side, a control on the other; stacks when narrow.
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.title,
    this.hint,
    required this.control,
  });
  final String title;
  final String? hint;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!, style: text.bodySmall?.copyWith(color: muted)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 440) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: 16),
              control,
            ],
          );
        },
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'Running':
    case 'Connected':
      return const Color(0xFF2E9E5B);
    case 'Starting':
    case 'Connecting':
      return const Color(0xFFD08A00);
    case 'Not Started':
    case 'Stopped':
    case 'Disconnected':
      return const Color(0xFF8A8F98);
    default:
      return const Color(0xFFD64545); // Error and anything unexpected
  }
}

class PanelEmpty extends StatelessWidget {
  const PanelEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.busy = false,
  });
  final IconData icon;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(icon, size: 28, color: muted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}

class CopyButton extends StatefulWidget {
  const CopyButton(this.value, {super.key});
  final String value;

  @override
  State<CopyButton> createState() => CopyButtonState();
}

class CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _copied ? 'Copied' : 'Copy',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        _copied ? Icons.check : Icons.copy_outlined,
        size: 18,
        color: _copied ? const Color(0xFF2E9E5B) : null,
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: widget.value));
        setState(() => _copied = true);
        _reset?.cancel();
        _reset = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _copied = false);
        });
      },
    );
  }
}

/// A read-only value (mono-spaced, selectable) with an optional copy button.
class PanelValue extends StatelessWidget {
  const PanelValue({
    super.key,
    required this.label,
    required this.value,
    this.copyable = false,
  });
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontFamilyFallback: [
                      'Consolas',
                      'DejaVu Sans Mono',
                      'Courier New',
                      'monospace',
                    ],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (copyable) CopyButton(value) else const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Dialog shell ───────────────────────────────────────────────────────────

/// The common look of every dialog: a titled header with a close button, a
/// scrolling body, and an optional footer of actions. Settings uses the same
/// pieces, so all dialogs feel like one app.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.actions = const [],
    this.maxWidth = 480,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.all(screen.width < 600 ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: Get.back,
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for confirmation; resolves true if the user confirms.
Future<bool> confirmDialog({
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData? icon,
}) async {
  final scheme = Get.context != null
      ? Theme.of(Get.context!).colorScheme
      : null;
  final result = await Get.dialog<bool>(
    AppDialog(
      title: title,
      icon: icon ?? (destructive ? Icons.delete_outline : Icons.help_outline),
      maxWidth: 420,
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive && scheme != null
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Get.back(result: true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message),
    ),
  );
  return result ?? false;
}

/// Asks for a line of text; resolves to the trimmed text, or null if cancelled.
Future<String?> promptDialog({
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
  IconData? icon,
}) {
  final controller = TextEditingController(text: initial);
  void submit() {
    final value = controller.text.trim();
    if (value.isNotEmpty) Get.back(result: value);
  }

  return Get.dialog<String>(
    AppDialog(
      title: title,
      icon: icon ?? Icons.edit_outlined,
      maxWidth: 420,
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, _) => FilledButton(
            onPressed: v.text.trim().isEmpty ? null : submit,
            child: Text(confirmLabel),
          ),
        ),
      ],
      child: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (_) => submit(),
      ),
    ),
  );
}
