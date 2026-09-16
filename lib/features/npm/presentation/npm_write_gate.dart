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
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: tone, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    access.bandMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              // Only the "we could not ask" state has anything to retry. A
              // view-only account is not a transient failure and offering to
              // re-check it would suggest the answer might change.
              if (access.state == NpmWriteAccessState.unknown)
                TextButton(
                  onPressed: () => ref.invalidate(npmAccountProvider),
                  child: const Text('Check again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

    return Semantics(
      button: true,
      // The hint, not the label: the control is still "Renew", and a screen
      // reader that read "Renew, requires an admin account" as one name would
      // be unable to say the name on its own.
      hint: allowed ? null : access.hint,
      child: TextButton(
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
        child: Text(label),
      ),
    );
  }
}
