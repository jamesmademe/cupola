import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// One choice offered by a [MediaDetailValueRow].
@immutable
class MediaDetailValueOption<T> {
  /// What is written when this option is picked.
  final T value;

  /// What the user reads. The server's own name for the thing, never a
  /// re-worded one: a quality profile called `Ultra-HD` is called that in
  /// Radarr's own UI and renaming it here breaks the only join the user has.
  final String label;

  const MediaDetailValueOption({required this.value, required this.label});
}

/// A field on a detail page, edited where it is read.
///
/// **Decision 25: a detail edits in place. There is no Edit page and no Edit
/// form anywhere in the app.** A field that lives in the Details grid is changed
/// from the Details grid — on a window by a select anchored to its own row, on a
/// phone by one [AppBottomSheet] carrying that one field. The ⋯ menu keeps
/// whole-item actions only (refresh, search, manual import, delete), so no field
/// is ever offered in two places at two densities.
///
/// The row that this replaced was in the deck's overflow *and* promoted into the
/// visible action band — `Quality profile: HD-1080p` sitting between `Manual
/// import` and `Delete`, which put a field edit among the verbs and left the
/// Details grid showing a value the user could not touch.
///
/// **A picker with no write behind it does not ship.** Pass [onChanged] null and
/// the row renders as a plain fact: no chevron, no button role, nothing that
/// says a tap would do something. A control that fails is worse than a readout
/// that is honest about being one.
///
/// [value] is resolved against [options]; a value that matches none of them —
/// including a null one, which is what a service that did not answer leaves
/// behind — reads `—`, never a blank and never a zero.
class MediaDetailValueRow<T> extends StatefulWidget {
  /// The field's name. Also the accessible name of the button.
  final String label;

  /// The value the service currently holds.
  final T? value;

  /// Every value the service will accept. Empty disables editing as surely as a
  /// null [onChanged] does — an empty picker is a dead end with an affordance.
  final List<MediaDetailValueOption<T>> options;

  /// The write. Awaited, so the row can show that it is in flight, and called
  /// only when the pick actually differs from [value] — a no-op write to a
  /// quality profile can still queue a library-wide upgrade sweep.
  final Future<void> Function(T value)? onChanged;

  /// The page's service accent. Never `colorScheme.primary`: that would put
  /// indigo on a Sonarr violet page, which is a second accent on one screen.
  final Color? accent;

  /// Spoken after the name and value, so a screen reader user knows the row is
  /// editable before opening it. Passed to [PressableScale] rather than wrapped
  /// around it: a button is a semantic boundary and a `Semantics(hint:)` placed
  /// *around* one is dropped on the floor.
  final String? hint;

  const MediaDetailValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
    this.accent,
    this.hint,
  });

  /// Minimum height of the tappable row.
  ///
  /// Declared here and honoured with a `ConstrainedBox` rather than a
  /// `minimumSize` on a Material button, because `VisualDensity.compact`
  /// silently defeats `minimumSize` — a control declaring 44 measures 40, and
  /// the declaration still reads as correct.
  static const double minRowHeight = 44;

  @override
  State<MediaDetailValueRow<T>> createState() => _MediaDetailValueRowState<T>();
}

class _MediaDetailValueRowState<T> extends State<MediaDetailValueRow<T>> {
  final MenuController _menu = MenuController();
  bool _busy = false;

  bool get _editable =>
      widget.onChanged != null && widget.options.isNotEmpty && !_busy;

  String get _valueText {
    for (final option in widget.options) {
      if (option.value == widget.value) return option.label;
    }
    // The source did not answer, or answered something this build does not know
    // how to name. Either way the honest render is a dash.
    return '—';
  }

  Future<void> _write(T picked) async {
    if (picked == widget.value) return;
    final write = widget.onChanged;
    if (write == null) return;

    setState(() => _busy = true);
    try {
      await write(picked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSheet() async {
    HapticFeedback.selectionClick();
    final picked = await showMediaValueSheet<T>(
      context,
      title: widget.label,
      value: widget.value,
      options: widget.options,
      accent: widget.accent,
      currentLabel: _valueText,
    );
    if (picked != null) await _write(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;

    final labelText = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // The same dense metadata label the fact grid uses, so an editable field
      // and a read-only one are the same kind of thing until you reach for them.
      style: theme.textTheme.labelSmall!
          .weight(FontWeight.w700)
          .copyWith(color: colorScheme.onSurfaceVariant),
    );

    final valueText = Text(
      _valueText,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall!
          .weight(FontWeight.w600)
          .copyWith(color: _valueText == '—' ? dim : colorScheme.onSurface),
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [labelText, const SizedBox(height: 2), valueText],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: ActionStateGlyph.spinnerSize,
              height: ActionStateGlyph.spinnerSize,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (widget.onChanged != null && widget.options.isNotEmpty)
            Icon(
              Icons.expand_more_rounded,
              size: ActionStateGlyph.glyphSize,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    // Read-only: a plain fact, with no button role and no chevron to promise one.
    // Not `Semantics(enabled: false)` either — there is simply no control here.
    if (widget.onChanged == null || widget.options.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: MediaDetailValueRow.minRowHeight,
        ),
        child: content,
      );
    }

    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: MediaDetailValueRow.minRowHeight,
      ),
      child: PressableScale(
        onTap: _editable
            ? () {
                if (AppBreakpoints.isDesktopShell) {
                  _menu.isOpen ? _menu.close() : _menu.open();
                } else {
                  _openSheet();
                }
              }
            : null,
        semanticLabel: widget.label,
        semanticValue: _valueText,
        semanticHint: widget.hint,
        excludeChildSemantics: true,
        child: content,
      ),
    );

    if (!AppBreakpoints.isDesktopShell) return row;

    // A window gets the select on the row itself: a sheet sliding up from the
    // bottom of a 1440pt window to offer four words is a phone gesture wearing a
    // desktop coat.
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: AppSpacing.xs),
        ),
      ),
      menuChildren: [
        for (final option in widget.options)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: MediaValueOptionRow(
                label: option.label,
                isSelected: option.value == widget.value,
                accent: widget.accent,
                onTap: () {
                  _menu.close();
                  _write(option.value);
                },
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => child!,
      child: row,
    );
  }
}

/// Opens the one-field sheet decision 25 puts behind a value row on a phone.
///
/// One field per sheet, deliberately: a sheet carrying four selects is an Edit
/// form with a drag handle, which is the thing this replaces.
///
/// Returns the picked option, or null if the sheet was dismissed. The caller
/// decides whether a pick equal to the current value is worth a write — it is
/// not, and [MediaDetailValueRow] swallows it.
Future<MediaDetailValueOption<T>?> showMediaValueSheet<T>(
  BuildContext context, {
  required String title,
  required T? value,
  required List<MediaDetailValueOption<T>> options,
  required String currentLabel,
  Color? accent,
  IconData icon = Icons.tune_rounded,
}) {
  if (options.isEmpty) return Future<MediaDetailValueOption<T>?>.value();

  return AppBottomSheet.show<MediaDetailValueOption<T>>(
    context: context,
    title: title,
    // Not the bare name: the selected row already says it, and two nodes reading
    // 'HD-1080p' is one stop too many for a screen reader.
    subtitle: 'Currently $currentLabel',
    icon: icon,
    accent: accent,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          MediaValueOptionRow(
            label: option.label,
            isSelected: option.value == value,
            accent: accent,
            onTap: () => Navigator.of(
              sheetContext,
            ).pop<MediaDetailValueOption<T>>(option),
          ),
      ],
    ),
  );
}

/// One option in a value picker, on either surface.
///
/// Through [PressableScale] rather than a `ListTile`: that widget is the sole
/// home of the press-scale, the haptic, the Reduce Motion check *and* the button
/// role plus accessible name, and a ~48pt row floods its own ink splash — a
/// flooded ripple reads as selection rather than as a touch, which is precisely
/// the wrong signal on a row where one sibling genuinely *is* selected.
class MediaValueOptionRow extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? accent;
  final VoidCallback onTap;

  const MediaValueOptionRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  /// Tall enough for a thumb on a phone and for a pointer on a window; the same
  /// height the app's other action rows use.
  static const double rowHeight = HeaderActionRow.buttonHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;
    final selectedInk = ServiceTheme.onTint(
      accentColor,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      semanticValue: isSelected ? 'Selected' : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: rowHeight),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: ActionStateGlyph.glyphSize,
              color: isSelected ? selectedInk : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: isSelected
                    ? theme.textTheme.bodyLarge!
                          .weight(FontWeight.w700)
                          .copyWith(color: selectedInk)
                    : theme.textTheme.bodyLarge!.weight(FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
