import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/sample_age.dart';

/// When the shell last refreshed everything.
///
/// Set by the refresh action rather than by any individual fetch: the label
/// says "refreshed", meaning the whole window was told to, which is a different
/// fact from when some provider happened to settle.
final lastRefreshedAtProvider = StateProvider<DateTime?>((ref) => null);

/// A coarse clock, so the age label cannot sit there being wrong.
///
/// Thirty seconds, and the label is bucketed to the minute ([formatSampleAge]):
/// a tick can never land in the middle of a change the eye would catch, and the
/// label costs one rebuild every half minute instead of one a second.
///
/// A UI clock, not a poller, and allowlisted as such in
/// `test/core/no_ungated_polling_test.dart`: it touches no network, and gating
/// it would save nothing while making the one thing this label owes the user —
/// being right when they look at it — wrong after the first hidden minute.
final _ageClockProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (i) => i),
);

/// How fresh the window's sample is, in the deck beside the Jump pill.
///
/// This used to be the third figure of a 26pt status bar at the foot of the
/// window. The other three things that bar printed were already on screen —
/// the fleet count in the deck, the queue in Activity and the inspector, the
/// key hints on the controls that own them — so the bar went and this, the
/// only fact it owned, moved next to the counts it qualifies. Draws nothing
/// until the window has been refreshed once: an age nobody measured is not
/// "just now".
class ShellFreshness extends ConsumerWidget {
  const ShellFreshness({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshedAt = ref.watch(lastRefreshedAtProvider);
    if (refreshedAt == null) return const SizedBox.shrink();
    // Watched for its ticks alone: the age is computed from the clock, so
    // without this the label would only re-age when something else moved.
    ref.watch(_ageClockProvider);
    return Text(
      'Refreshed ${formatSampleAge(refreshedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.chrome(
        context,
        size: 11,
        weight: FontWeight.w500,
        color: CupolaThemeColors.of(context).dimText,
        height: 1.22,
      ),
    );
  }
}
