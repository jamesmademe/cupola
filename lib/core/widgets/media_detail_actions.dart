import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// One row of the actions overflow sheet.
///
/// [MediaOverflowAction.destructive] is a separate constructor rather than a
/// flag because it changes where the row *lands*: the sheet sorts every
/// destructive action below a divider, last, furthest from where the thumb
/// arrives. Delete used to sit roughly ten points from Manual Import in an
/// undifferentiated `spaceAround` row, told apart by hue alone.
@immutable
class MediaOverflowAction {
  final String label;
  final IconData icon;

  /// Null disables the row. Kept rather than omitted when a host wants the
  /// action visible but unavailable; most callers simply omit it instead.
  final VoidCallback? onInvoke;

  final bool isDestructive;

  const MediaOverflowAction({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = false;

  const MediaOverflowAction.destructive({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = true;
}

/// Shows the non-promoted actions for a media detail page.
///
/// [title] is the media title, shown as the sheet's subtitle. [actions] are
/// rendered in the order given, with one exception the sheet enforces itself:
/// every [MediaOverflowAction.destructive] is moved below a divider at the
/// bottom, so a caller cannot accidentally seat Delete beside Import.
///
/// **Haptics live here, once.** Each service screen used to fire its own, and
/// they had drifted: Radarr fired `selectionClick` on both searches and
/// `mediumImpact` before Delete while Sonarr and Lidarr fired nothing at all.
/// The sheet is the tap target now, so the sheet owns the feedback: a
/// destructive row gets `mediumImpact`, everything else `selectionClick`, and
/// [PressableScale]'s own light impact is suppressed so exactly one fires.
///
/// **Where there is room** ([AppBreakpoints.sheetsAreDialogs]) the actions
/// are a menu under [anchor], the button that asked (the page's ⋯), in the
/// same order with the same divider before the destructive ones: a list of
/// actions is the pointer's popover, never a dialog. Without an anchor they
/// stay a sheet, which is a dialog there.
Future<void> showMediaDetailActions(
  BuildContext context, {
  required Color accent,
  required String title,
  required List<MediaOverflowAction> actions,
  BuildContext? anchor,
}) {
  final safe = actions.where((action) => action.label.isNotEmpty).toList();
  if (anchor != null && AppBreakpoints.sheetsAreDialogs(context)) {
    return _showMenu(anchor, safe);
  }

  return AppBottomSheet.show<void>(
    context: context,
    title: 'Actions',
    subtitle: title,
    icon: Icons.more_horiz_rounded,
    accent: accent,
    builder: (sheetContext) => _MediaOverflowRows(actions: safe),
  );
}

/// [actions] as the theme's menu under [anchor]: the ordinary ones, a
/// divider, the destructive ones; a row with no invoker is drawn off.
Future<void> _showMenu(
  BuildContext anchor,
  List<MediaOverflowAction> actions,
) async {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(anchor, rootOverlay: true).context.findRenderObject()!
          as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final ordinary = [
    for (final a in actions)
      if (!a.isDestructive) a,
  ];
  final destructive = [
    for (final a in actions)
      if (a.isDestructive) a,
  ];
  PopupMenuItem<MediaOverflowAction> item(MediaOverflowAction action) =>
      PopupMenuItem(
        value: action,
        enabled: action.onInvoke != null,
        child: Row(
          children: [
            Icon(action.icon, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(action.label)),
          ],
        ),
      );
  final chosen = await showMenu<MediaOverflowAction>(
    context: anchor,
    useRootNavigator: true,
    // Under the button, lined up with whichever of its edges is nearer the
    // window's: the ⋯ at the page's top right opens leftwards.
    position: RelativeRect.fromRect(
      Rect.fromLTRB(
        rect.left,
        rect.bottom + AppSpacing.xs,
        rect.right,
        rect.bottom + AppSpacing.xs,
      ),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final action in ordinary) item(action),
      if (ordinary.isNotEmpty && destructive.isNotEmpty)
        const PopupMenuDivider(),
      for (final action in destructive) item(action),
    ],
  );
  if (chosen == null) return;
  if (chosen.isDestructive) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.selectionClick();
  }
  chosen.onInvoke?.call();
}

/// The sheet's rows, and the one thing they share: a sheet spends itself on a
/// single action.
///
/// The rows sit on a route that pops *before* the action runs, and a
/// [MediaOverflowAction] is a bare [VoidCallback], so the host learns about a
/// tap only once it has already started the work, and cannot refuse a second
/// one. Two fingers landing on Manual import and Delete in the same frame is
/// enough: both rows fire, both pop, and the second pop takes the detail page
/// with it while a delete is already in flight. The guard belongs here, where
/// the sheet knows it has been used.
class _MediaOverflowRows extends StatefulWidget {
  final List<MediaOverflowAction> actions;

  const _MediaOverflowRows({required this.actions});

  @override
  State<_MediaOverflowRows> createState() => _MediaOverflowRowsState();
}

class _MediaOverflowRowsState extends State<_MediaOverflowRows> {
  bool _spent = false;

  void _invoke(MediaOverflowAction action) {
    if (_spent) return;
    setState(() => _spent = true);
    if (action.isDestructive) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    Navigator.of(context).pop();
    action.onInvoke!();
  }

  @override
  Widget build(BuildContext context) {
    final ordinary = widget.actions.where((action) => !action.isDestructive);
    final destructive = widget.actions.where((action) => action.isDestructive);

    Widget row(MediaOverflowAction action) => _MediaOverflowRow(
      action: action,
      onInvoke: action.onInvoke == null || _spent
          ? null
          : () => _invoke(action),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in ordinary) row(action),
        if (destructive.isNotEmpty && ordinary.isNotEmpty)
          Divider(
            height: AppSpacing.xl,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        for (final action in destructive) row(action),
      ],
    );
  }
}

class _MediaOverflowRow extends StatelessWidget {
  final MediaOverflowAction action;

  /// Null disables the row: either the action carries no invoker, or the sheet
  /// has already been spent on another one.
  final VoidCallback? onInvoke;

  const _MediaOverflowRow({required this.action, required this.onInvoke});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onInvoke != null;
    // One ink for every row. A destructive one is set apart by where it sits:
    // below the divider, last, and by its haptic, never by red: red means
    // unreachable and nothing else, and the confirmation says what goes.
    final glyphColor = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    final labelColor = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return PressableScale(
      // Exactly one haptic per row, fired below.
      haptic: false,
      semanticLabel: action.label,
      excludeChildSemantics: true,
      onTap: onInvoke,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
        child: Row(
          children: [
            Icon(
              action.icon,
              size: ActionStateGlyph.glyphSize,
              color: glyphColor,
            ),
            const SizedBox(width: AppSpacing.md),
            // A full-width labelled row cannot truncate, which is what retires
            // the 58pt captions that ellipsised to "Inter…" / "Auto…".
            Expanded(
              child: Text(
                action.label,
                style: theme.textTheme.bodyLarge!
                    .weight(FontWeight.w600)
                    .copyWith(color: labelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
