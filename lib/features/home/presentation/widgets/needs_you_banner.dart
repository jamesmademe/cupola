import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// Needs you, the operator's first module: one line that says what is wrong,
/// how many more things are, and the way in.
///
/// Absent while nothing is: the date line above already answers "12 of 12
/// answering", and a band that is there on every open is one nobody reads on
/// the day it matters. Absent, too, before anything answered: the page does
/// not hold a gap for it.
///
/// One target, as drawn. A service that did not answer leads, in red, and
/// the line is its Retry; otherwise the largest group of equal faults leads,
/// in amber, and the line is Review, which opens Activity's Needs you, where
/// every fault is on its card with its way out. The line never runs a remedy
/// itself.
class NeedsYouBanner extends ConsumerWidget {
  const NeedsYouBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final silent = ref.watch(unreachableServicesProvider);
    final checkedAt = ref.watch(stackHealthProvider.select((h) => h.checkedAt));
    final read = ref.watch(dashboardDecisionsProvider);
    final now = ref.watch(calendarClockProvider)();
    final needs = needsYouOf(
      silent: silent,
      decisions: read.decisions,
      now: now,
      silentAt: checkedAt,
      silentSince: silentSinceOf(
        silent,
        ref.read(silenceClockProvider),
        ref.watch(currentSettingsProvider),
      ),
      silenceScope: ref.watch(stackSilenceProvider).scopeOf(silent),
      // Only the queues' walk: every group is folded from it, and a history
      // page read whole or not says nothing about how many imports are
      // blocked.
      floor:
          ref
              .watch(dashboardDecisionSourceProvider(DecisionSource.queue))
              .value
              ?.coverage
              .isFloor ??
          false,
      moreFloor: read.coverage.isFloor,
    );
    if (needs == null) return const SizedBox.shrink();

    return NeedsYouLine(
      needs: needs,
      onTap: needs.leadsWithSilence
          ? () => retryDashboardServices(ref, needs.silent)
          // Every fault and its way out is on one page; the lead is the
          // first card there.
          : () => context.go(ServiceRoutes.activityNeedsYou),
    );
  }
}

/// Since when every one of [services] has not answered: the latest time any
/// of them went silent, a service being silent from when the last of its
/// connections stopped answering. Null when any silence is not on record,
/// which says nothing rather than a time that is only part of the truth.
@visibleForTesting
DateTime? silentSinceOf(
  List<ServiceKey> services,
  SilenceClock clock,
  SettingsModel settings,
) {
  DateTime? latest;
  for (final service in services) {
    final connections = settings.configuredInstancesOf(service);
    if (connections.isEmpty) return null;
    for (final connection in connections) {
      final since = clock.since(silenceKey(service, connection.id));
      if (since == null) return null;
      if (latest == null || since.isAfter(latest)) latest = since;
    }
  }
  return latest;
}

/// The line itself, given what it says: the glyph in the tone of the lead,
/// the sentence, `+2` when more things need the person, and the control's
/// word at its end.
class NeedsYouLine extends StatelessWidget {
  const NeedsYouLine({super.key, required this.needs, required this.onTap});

  final NeedsYou needs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final glyph = statusToneColor(
      scheme,
      needs.leadsWithSilence ? StatusTone.error : StatusTone.warning,
      surface: room.slab,
    );
    final glyphIcon = Icon(
      needs.leadsWithSilence
          ? Icons.cloud_off_rounded
          : Icons.warning_amber_rounded,
      size: 18,
      color: glyph,
    );
    const gap = SizedBox(width: AppSpacing.md);
    final sentence = Expanded(
      child: Text(needs.line, style: AppType.body.copyWith(color: room.ink)),
    );
    final chip = needs.more <= 0
        ? null
        : [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: room.fillStrong,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                needs.moreLabel,
                style: AppType.caption
                    .weight(FontWeight.w600)
                    .copyWith(color: room.inkSecondary),
              ),
            ),
          ];
    final action = Text(
      needs.action,
      style: AppType.body.weight(FontWeight.w600).copyWith(color: room.ink),
    );
    // At a large reading size the sentence takes the line and the count and
    // the way in go under it: beside them it broke inside its words.
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Semantics(
        // Announced when it appears, the moment it matters.
        liveRegion: true,
        child: PressableScale(
          onTap: onTap,
          semanticLabel: needs.spoken,
          excludeChildSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: room.door,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: room.hair),
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [glyphIcon, gap, sentence],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [...?chip, gap, action],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      glyphIcon,
                      gap,
                      sentence,
                      if (chip != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        ...chip,
                      ],
                      gap,
                      action,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
