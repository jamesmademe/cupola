import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';

/// Says, once per screen, what this account cannot do.
///
/// **Informational, never amber.** A permission is configuration, not a fault:
/// nothing has failed, nothing is down, and the user may well have signed in
/// with the view-only account on purpose. Amber here would put the screen's
/// alarm colour on the one thing that is working as intended, and would compete
/// with the rows that genuinely are broken. Blue is the tone for a fact the
/// screen needs you to know (decision 14 · 34).
///
/// Shaped like `InlineErrorRetry` deliberately — same card, same rhythm — so
/// the two read as one family of page-level notices rather than as two
/// inventions.
class NpmAccessBand extends ConsumerWidget {
  const NpmAccessBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(npmWriteAccessProvider);
    if (!access.showBand) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    // The band is a tinted container, so its ink is measured against that
    // composite rather than against the page.
    final tone = statusToneColor(
      colorScheme,
      StatusTone.info,
      surface: colorScheme.surface,
    );

    return Semantics(
      container: true,
      // `liveRegion` is deliberately off: this is the standing state of the
      // connection, not an event. It is read when the user reaches it.
      label: access.bandMessage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(color: tone.withValues(alpha: 0.45)),
          ),
          child: _bandLayout(
            context,
            message: ExcludeSemantics(
              child: Text(
                access.bandMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
            icon: Icon(Icons.info_outline_rounded, color: tone, size: 20),
            // Only the "we could not ask" state has anything to retry. A
            // view-only account is not a transient failure and offering to
            // re-check it would suggest the answer might change.
            action: access.state == NpmWriteAccessState.unknown
                ? TextButton(
                    onPressed: () => ref.invalidate(npmAccountProvider),
                    child: const Text('Check again'),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Above this scaled size, the band's button goes on its own line.
///
/// A `Row` of icon, sentence and button overflowed by 138pt at a 3x reading
/// size: a `TextButton` is not flexible, so "Check again" laid out at three
/// times its normal width simply took more room than the card had and the
/// `Expanded` beside it could not give any more away. Shrinking the button is
/// not an option — it is a 44pt target with a name that has to stay readable —
/// so past this size the layout stacks instead.
///
/// 20 logical pixels is `bodySmall` (12) grown by about 1.6x, the same clamp
/// `TextScaleMetrics.defaultMaxScaleFactor` uses for the boxes it grows. Below
/// it the band reads as the board draws it; above it, the sentence takes the
/// full width and the button sits under it, right-aligned.
const double _bandStackThreshold = 20;

/// The band's inside: a row until the text is too big for one, then a column.
Widget _bandLayout(
  BuildContext context, {
  required Widget icon,
  required Widget message,
  required Widget? action,
}) {
  final row = Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      icon,
      // A token, not the bare 10 this layout carried through both arms while
      // spending `AppSpacing` on everything around it. `sm` is the gap the rest
      // of the page puts between a status glyph and the sentence it marks.
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: message),
    ],
  );

  if (action == null) return row;

  final stacked =
      MediaQuery.textScalerOf(context).scale(12) > _bandStackThreshold;
  if (!stacked) {
    return Row(
      children: [
        icon,
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: message),
        action,
      ],
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      row,
      const SizedBox(height: AppSpacing.xs),
      Align(alignment: Alignment.centerRight, child: action),
    ],
  );
}

/// Whether [resource] may be written, and — when it may not — the answer the
/// user gets instead of the action.
///
/// Returns false **after** showing the toast, so the call site reads
/// `if (!npmWriteAllowed(...)) return;`. The control that called it stays on
/// screen, keeps its target and keeps its label: hiding a control hides the
/// fact, and the fact is why this screen knows anything about accounts at all.
bool npmWriteAllowed(
  BuildContext context,
  WidgetRef ref,
  NpmResource resource,
) {
  final access = ref.read(npmWriteAccessProvider);
  if (access.canManage(resource)) return true;
  SnackBarHelper.info(context, switch (access.state) {
    NpmWriteAccessState.viewOnly =>
      'This Nginx Proxy Manager account is view-only — sign in as an admin in '
          'Settings › Connections to change this.',
    NpmWriteAccessState.checking =>
      'Still checking what this account is allowed to change.',
    _ =>
      'Cupola could not read this account\'s permissions, so it is holding '
          'changes back.',
  });
  return false;
}

/// A write drawn as a text button, dimmed but reachable when it is not allowed.
///
/// **Never `Semantics(enabled: false)`.** A disabled node drops off the screen
/// reader's path entirely, which takes the control *and* the explanation away
/// from the one user who cannot see that it is greyed out. The button keeps its
/// full target and its name, gains the hint, and answers on tap.
class NpmWriteButton extends ConsumerWidget {
  const NpmWriteButton({
    super.key,
    required this.resource,
    required this.label,
    required this.onPressed,
  });

  final NpmResource resource;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(npmWriteAccessProvider);
    final allowed = access.canManage(resource);
    final colorScheme = Theme.of(context).colorScheme;

    final hint = allowed ? null : access.hint;

    return TextButton(
      style: allowed
          ? null
          : TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.6,
              ),
            ),
      onPressed: () {
        if (!npmWriteAllowed(context, ref, resource)) return;
        onPressed();
      },
      // The annotation goes on the **child**, inside the button, and that is
      // the whole fix. `ButtonStyleButton` publishes `Semantics(container:
      // true, button: true)`, which is a semantic boundary: a `Semantics(hint:)`
      // wrapped around the button lands on a second, non-actionable node above
      // it, the screen reader focuses the inner one, and the reason the control
      // is attenuated is never spoken — to the one user this widget exists for.
      // From here the hint merges into the button's own node alongside the
      // label, the way `CrossServiceAction` passes `semanticHint` into the
      // tappable rather than around it: one node, named "Renew", hinted
      // "requires an admin account", still tappable.
      //
      // The hint and not the label, deliberately: a reader that said "Renew,
      // requires an admin account" as one name could not say the name alone.
      child: Semantics(hint: hint, child: Text(label)),
    );
  }
}
