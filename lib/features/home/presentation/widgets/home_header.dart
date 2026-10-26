import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/core/widgets/screen_title.dart';

/// The top of the Home: the day, large, and under it the month and how many
/// services answered, which opens Stack.
///
/// The day is the page's title. The Home is not a place with a name to say,
/// it is today: "Thursday 8", and the month after it on the line below, where
/// the health of the stack is one more fact about today. Nothing is reserved
/// for Needs you here: before any service answered, the line says it is
/// checking and the page does not hold a gap for a banner that may not come.
///
/// The requester's has no health line (she reads no service) and carries her
/// account at its end, her way to Settings.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, this.trailing, this.showsHealth = true});

  /// At the end of the day's line: the requester's account.
  final Widget? trailing;

  /// Whether the month's line says how many services answered.
  final bool showsHealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final now = ref.watch(calendarClockProvider)();
    final day = '${weekdayName(now)} ${now.day}';
    final month = monthName(now);
    final health = showsHealth ? ref.watch(stackHealthProvider) : null;
    final line = health == null ? '' : homeHealthLine(health);

    final title = ScreenTitle(day);
    final monthStyle = AppType.body.copyWith(color: room.inkSecondary);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing case final end?)
            Row(
              children: [
                Expanded(child: title),
                end,
              ],
            )
          else
            title,
          if (line.isEmpty)
            // The same height as the line with the health on it, so the
            // first module stands where it does on every Home.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(month, style: monthStyle),
              ),
            )
          else
            Semantics(
              link: true,
              label: '$month. Stack: ${spokenHealthLine(health!)}',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => context.go(ServiceRoutes.stack),
                borderRadius: BorderRadius.circular(AppRadius.thumb),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  // One line of words with the light set in it, so at a large
                  // reading size it wraps as a sentence does: two texts in a
                  // row wrapped the health in a column of its own. The word
                  // joiner keeps the light with the figure after it.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text.rich(
                      TextSpan(
                        style: monthStyle,
                        children: [
                          TextSpan(text: '$month\u00A0· '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: _HealthDot(health: health),
                            ),
                          ),
                          TextSpan(text: '\u2060$line'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `12 of 12 answering`, `Checking 12 services` before anything answered,
/// `9 of 12 answering · 3 checking` while the slowest are still out, and away
/// from home `7 of 7 answering · 6 only at home` (J-Away-2): the services
/// not asked are out of the count and named after it. Empty when nothing set
/// up is asked anything.
String homeHealthLine(StackHealth health) {
  final configured = health.configured;
  if (configured == 0) return '';
  if (health.checking >= configured) {
    return 'Checking $configured ${configured == 1 ? 'service' : 'services'}';
  }
  return [
    health.headline!,
    if (health.checking > 0) '${health.checking} checking',
    if (health.onlyAtHome > 0)
      '${health.onlyAtHome} ${StateWord.onlyAtHome.inline}',
  ].join(dotSeparator);
}

/// [homeHealthLine] as a screen reader says it: `12 of 12 services
/// answering`.
String spokenHealthLine(StackHealth health) {
  final line = homeHealthLine(health);
  if (health.checking >= health.configured) return line;
  return line
      .replaceFirst(' answering', ' services answering')
      .replaceAll(dotSeparator, ', ');
}

/// The stack's light: green while everything answers, amber over a fault or
/// a server that timed out, red when a service did not answer, a ring while
/// the first answers are out.
class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.health});

  final StackHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final checking = health.checking >= health.configured;
    final tone = health.unreachable > 0
        ? StatusTone.error
        : health.degraded > 0 || health.faulted > 0 || health.stuck > 0
        ? StatusTone.warning
        : StatusTone.success;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checking
            ? null
            : statusToneColor(scheme, tone, surface: room.ground),
        border: checking ? Border.all(color: room.inkTertiary) : null,
      ),
    );
  }
}
