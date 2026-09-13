import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// When the shell last refreshed everything, for the status bar's third figure.
///
/// Set by the refresh action rather than by any individual fetch: the line says
/// "refreshed", meaning the whole window was told to, which is a different fact
/// from when some provider happened to settle.
final lastRefreshedAtProvider = StateProvider<DateTime?>((ref) => null);

/// A coarse clock, so the age label cannot sit there being wrong.
///
/// Thirty seconds, and the label is bucketed to the minute — a tick can never
/// land in the middle of a change the eye would catch, and the bar costs one
/// rebuild every half minute instead of one a second.
///
/// A UI clock, not a poller, and allowlisted as such in
/// `test/core/no_ungated_polling_test.dart`: it touches no network, and gating
/// it would save nothing while making the one thing this label owes the user —
/// being right when they look at it — wrong after the first hidden minute.
final _ageClockProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (i) => i),
);

/// The 26pt foot of the window: three facts and the keys, all muted.
///
/// Everything here is also somewhere else — the stack aggregate is the deck's
/// and the alert band's, the queue is Activity's and the inspector's — because
/// a status bar is a *reminder*, not a source. Nothing lives only here, so
/// nothing is lost when a window is too short to show it.
class ShellStatusBar extends ConsumerWidget {
  const ShellStatusBar({super.key});

  static const double height = 26;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = AppBreakpoints.isCompactDesktop(context);
    final health = ref.watch(stackHealthProvider);
    final queue = ref.watch(globalNowItemsProvider).asData?.value;
    final refreshedAt = ref.watch(lastRefreshedAtProvider);
    // Watched for its ticks alone: the age label is computed from the clock, so
    // without this the bar would only re-age when something else moved.
    ref.watch(_ageClockProvider);

    final active = queue?.items.length ?? 0;
    final stalled =
        queue?.items.where((item) => item.status.hasWarning).length ?? 0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
        child: Row(
          children: [
            // One flexible group, not three flexible children: a `Flexible`
            // takes a *share of the free space* even when its child is smaller
            // than that share, so three of them plus a `Spacer` split the width
            // four ways and parked the key hints in the middle of the bar.
            // Grouped, the figures take everything the keys do not need and
            // ellipsize among themselves.
            Flexible(
              child: Row(
                children: [
                  Flexible(child: _Figure(health.sentence)),
                  if (queue != null) ...[
                    const SizedBox(width: AppSpacing.lg + 2),
                    Flexible(
                      child: _Figure(
                        stalled == 0
                            ? 'Queue $active'
                            : 'Queue $active · $stalled stalled',
                      ),
                    ),
                  ],
                  if (refreshedAt != null && !compact) ...[
                    const SizedBox(width: AppSpacing.lg + 2),
                    Flexible(child: _Figure(_age(refreshedAt))),
                  ],
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.lg),
              _Figure(
                '${ShellShortcuts.commandDeck} jump · '
                '${ShellShortcuts.inspector} inspector · '
                '${ShellShortcuts.refreshAll} refresh all',
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bucketed on purpose: see [_ageClockProvider].
  static String _age(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Refreshed just now';
    if (minutes < 60) return 'Refreshed $minutes min ago';
    final hours = minutes ~/ 60;
    return 'Refreshed $hours h ago';
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.22,
      color: AppColors.onSurfaceDimDark,
    ),
  );
}
