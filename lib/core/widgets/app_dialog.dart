import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// A toggleable option (checkbox) shown inside [showAppConfirmDialog].
///
/// An option that makes the action irreversible (*Delete files*) says so in
/// its own [subtitle], in the same ink as every other line of the dialog. It
/// used to take a `danger` flag that turned the option red and raised a red
/// *cannot be undone* banner; red means unreachable and nothing else, so the
/// flag went with it.
class AppConfirmOption {
  final String key;
  final String label;
  final String? subtitle;
  final bool initialValue;

  const AppConfirmOption({
    required this.key,
    required this.label,
    this.subtitle,
    this.initialValue = false,
  });
}

/// Result of [showAppConfirmDialog].
class AppConfirmResult {
  final bool confirmed;
  final Map<String, bool> options;

  const AppConfirmResult({required this.confirmed, this.options = const {}});

  static const cancelled = AppConfirmResult(confirmed: false);

  bool option(String key) => options[key] ?? false;
}

/// The confirm label for the options as they currently stand: `checked(key)`
/// reads one of them.
typedef AppConfirmLabelFor = String Function(bool Function(String key) checked);

/// One canonical confirmation dialog for the whole app, and one style of it.
///
/// Title, an optional sentence, optional [options] (checkboxes, e.g. the
/// "delete files" / "add exclusion" toggles used when removing media), and a
/// Cancel / confirm pair. The confirm is always the theme's own `FilledButton`.
///
/// **A destructive confirmation is not red.** Red in the tone rule means
/// unreachable and nothing else, not "irreversible", not "careful". A delete
/// used to fill its button red, turn its title and glyph red and add a red
/// *cannot be undone* banner; now the weight is carried by words:
///
/// - [confirmLabel] is a verb that names what will happen: *Delete job*,
///   *Take down*, *Remove from Radarr*, never *Confirm*, *OK*, *Yes* or a bare
///   *Delete*. `test/core/theme/neutral_destructive_test.dart` scans `lib/`
///   for that, and for any button or dialog painted with the error colour.
/// - When an option changes what the action does, [confirmLabelFor] rewrites
///   the label as it is ticked (*Delete movie* → *Delete movie and files*), so
///   the button always says the whole of it. [confirmLabel] stays required and
///   is asserted to be what [confirmLabelFor] returns for the options' initial
///   values, so the call site reads true at a glance.
/// - If the action cannot be undone, one neutral sentence says so, in
///   [message], or in the subtitle of the option that makes it so.
///
/// There is no `destructive` flag any more: once it stopped painting red it
/// did nothing true. Call sites that want a haptic already fire it themselves
/// before the dialog opens.
Future<AppConfirmResult> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String? message,
  IconData? icon,
  AppConfirmLabelFor? confirmLabelFor,
  String cancelLabel = 'Cancel',
  List<AppConfirmOption> options = const [],
  bool useRootNavigator = true,
}) async {
  final values = {for (final o in options) o.key: o.initialValue};
  assert(
    confirmLabelFor == null ||
        confirmLabelFor((key) => values[key] ?? false) == confirmLabel,
    'confirmLabel must be the label confirmLabelFor gives the initial options',
  );

  final result = await showDialog<AppConfirmResult>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final label =
            confirmLabelFor?.call((key) => values[key] ?? false) ??
            confirmLabel;

        return AlertDialog(
          title: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: colorScheme.onSurface),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  title,
                  // An `AlertDialog` title sits *above* the scrollable content,
                  // so an unbounded one grows the dialog until the buttons
                  // leave the viewport: there is no scroll to reach them by.
                  // Callers still cap the interpolated title; this is the floor
                  // under them.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge!.weight(FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null && message.isNotEmpty)
                Text(message, style: theme.textTheme.bodyMedium),
              if (options.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final opt in options)
                  CheckboxListTile(
                    value: values[opt.key] ?? false,
                    onChanged: (v) =>
                        setState(() => values[opt.key] = v ?? false),
                    title: Text(opt.label),
                    // The secondary ink, as every subtitle: `bodySmall`
                    // alone carried the primary ink.
                    subtitle: opt.subtitle == null
                        ? null
                        : Text(
                            opt.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
            ],
          ),
          // A label that names the action (*Remove and delete files*) often
          // no longer fits beside Cancel on a phone, and the pair stacks. The
          // confirm goes on top (Material's stacked order), rather than
          // Cancel floating above it.
          actionsOverflowDirection: VerticalDirection.up,
          actionsOverflowButtonSpacing: AppSpacing.sm,
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(AppConfirmResult.cancelled),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(AppConfirmResult(confirmed: true, options: Map.of(values))),
              child: Text(label),
            ),
          ],
        );
      },
    ),
  );

  return result ?? AppConfirmResult.cancelled;
}

/// The heavier gate: a confirmation whose button stays inert until [phrase] (
/// a hostname, a domain) is typed out.
///
/// For the few actions whose blast radius leaves the device or cannot be
/// reached back from it: shutting a TrueNAS host down, taking an NPM proxy host
/// offline for everyone who uses it. A tap is calibrated for "are you sure";
/// typing the name answers "do you know which one", which is the question that
/// actually goes wrong on a small screen. Matching is trimmed and
/// case-insensitive, because hostnames are, and demanding exact case would
/// only teach people to copy-paste past the check.
///
/// It is [showAppConfirmDialog] with a text field: the same title row, the same
/// neutral `FilledButton` and a [confirmLabel] held to the same rule. The two
/// copies it replaces each painted the button red and put an amber warning
/// glyph above the title: a fault tone on a dialog nothing had gone wrong in.
Future<bool> showAppTypedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
  IconData? icon,
  bool useRootNavigator = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) => _TypedConfirmDialog(
      title: title,
      message: message,
      phrase: phrase,
      confirmLabel: confirmLabel,
      icon: icon,
    ),
  );
  return confirmed ?? false;
}

/// The body of [showAppTypedConfirmDialog]. A widget of its own so the text
/// controller lives exactly as long as the field: the two copies it replaced
/// disposed theirs the moment the dialog's future completed, while the exit
/// transition was still rebuilding the field that listens to it.
class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.phrase,
    required this.confirmLabel,
    this.icon,
  });

  final String title;
  final String message;
  final String phrase;
  final String confirmLabel;
  final IconData? icon;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
  }

  void _update() {
    final matches =
        _controller.text.trim().toLowerCase() ==
        widget.phrase.trim().toLowerCase();
    if (matches != _matches) setState(() => _matches = matches);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_update)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = widget.icon;
    return AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: colorScheme.onSurface),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge!.weight(FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: SelectableText(
              widget.phrase,
              style: theme.textTheme.bodyMedium?.weight(FontWeight.w600),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Type it to confirm'),
          ),
        ],
      ),
      // Stacked like the plain confirm: the confirm on top.
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          // On the child, not around the button: a disabled `FilledButton`
          // publishes no hint of its own, and a `Semantics(hint:)` wrapped
          // around a button is dropped.
          child: Semantics(
            hint: _matches ? null : 'Type ${widget.phrase} above to enable',
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
