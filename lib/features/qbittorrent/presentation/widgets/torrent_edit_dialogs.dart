import 'package:flutter/material.dart';

Future<String?> showEditCategoryDialog(
  BuildContext context, {
  required String currentCategory,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TorrentFieldDialog<String>(
      title: 'Set category',
      initialText: currentCategory,
      labelText: 'Category',
      hintText: 'Leave empty to clear',
      resultOf: (raw) => raw,
    ),
  );
}

Future<List<String>?> showEditTagsDialog(
  BuildContext context, {
  required List<String> currentTags,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TorrentFieldDialog<List<String>>(
      title: 'Set tags',
      initialText: currentTags.join(', '),
      labelText: 'Tags (comma-separated)',
      hintText: 'e.g. 4k, italian, dubbed',
      resultOf: _tagsOf,
    ),
  );
}

List<String> _tagsOf(String raw) => raw
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList(growable: false);

class SpeedLimitResult {
  final int? bytesPerSecond;
  const SpeedLimitResult._(this.bytesPerSecond);
  static const noChange = SpeedLimitResult._(null);
  factory SpeedLimitResult.kbps(int kbps) => SpeedLimitResult._(kbps * 1024);
}

Future<SpeedLimitResult?> showSpeedLimitDialog(
  BuildContext context, {
  required String title,
  required int currentLimitBytes,
}) {
  return showDialog<SpeedLimitResult>(
    context: context,
    builder: (_) => _TorrentFieldDialog<SpeedLimitResult>(
      title: title,
      initialText: currentLimitBytes > 0
          ? (currentLimitBytes / 1024).toStringAsFixed(0)
          : '',
      labelText: 'Limit (KB/s)',
      hintText: '0 = no limit',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      resultOf: _speedLimitOf,
    ),
  );
}

SpeedLimitResult _speedLimitOf(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const SpeedLimitResult._(0);
  final kbps = double.tryParse(trimmed.replaceAll(',', '.'));
  if (kbps == null || kbps < 0) return SpeedLimitResult.noChange;
  return kbps == 0
      ? const SpeedLimitResult._(0)
      : SpeedLimitResult._((kbps * 1024).round());
}

/// One text field, Cancel and Save, for a value the torrent's page edits.
///
/// The field's controller lives in this [State], so it is disposed with the
/// route's content: after the exit transition, never while the dialog is still
/// on screen fading out (a `showDialog` future completes as the route pops,
/// well before the transition ends).
class _TorrentFieldDialog<T> extends StatefulWidget {
  const _TorrentFieldDialog({
    required this.title,
    required this.initialText,
    required this.labelText,
    required this.hintText,
    required this.resultOf,
    this.keyboardType,
  });

  final String title;
  final String initialText;
  final String labelText;
  final String hintText;
  final TextInputType? keyboardType;

  /// What Save and the keyboard's Done hand back for what was typed.
  final T Function(String raw) resultOf;

  @override
  State<_TorrentFieldDialog<T>> createState() => _TorrentFieldDialogState<T>();
}

class _TorrentFieldDialogState<T> extends State<_TorrentFieldDialog<T>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(widget.resultOf(_controller.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
