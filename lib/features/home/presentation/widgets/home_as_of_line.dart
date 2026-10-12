import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/home_last_known.dart';

/// The Home's one line about a cold start: `As of 20:53 · checking now` under
/// the header while any module draws its last known state, gone once the last
/// of them is live (P-t1-words).
///
/// One line for the page rather than a mark on each module: the modules turn
/// live within a second or two of each other, and a mark on each would be six
/// marks blinking out one by one. It folds away instead of vanishing, so the
/// modules under it rise by its height once and smoothly.
class HomeAsOfLine extends ConsumerWidget {
  const HomeAsOfLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marks = ref.watch(homeLastKnownMarksProvider);
    final now = ref.watch(calendarClockProvider);
    return ListenableBuilder(
      listenable: marks,
      builder: (context, _) {
        final words = homeAsOfWords(marks.marks, now: now());
        final room = CupolaRoom.of(context);
        return AnimatedSize(
          duration: AppAnimation.standard,
          curve: AppAnimation.standardCurve,
          alignment: Alignment.topCenter,
          child: words == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.xs,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      words,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
