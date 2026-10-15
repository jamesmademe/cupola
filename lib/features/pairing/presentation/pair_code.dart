import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';

/// The code's place when there is no code: the same square, so what is under
/// it does not jump when the code arrives or leaves. Set up another device
/// and the invite shown in person both draw it.
class PairCodeSlot extends StatelessWidget {
  const PairCodeSlot({super.key, required this.child});

  /// The code's side, and the slot's.
  static const side = 232.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// `Closes in 1:52`, ticking each second to the code's end. Not a live
/// region: a reader walking the page hears the time it is on, and the end
/// says nothing new, because the page changes by itself.
class PairCountdown extends StatefulWidget {
  const PairCountdown({
    super.key,
    required this.closesAt,
    required this.now,
    required this.style,
  });

  final DateTime closesAt;
  final DateTime Function() now;
  final TextStyle style;

  @override
  State<PairCountdown> createState() => _PairCountdownState();
}

class _PairCountdownState extends State<PairCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: false,
    child: Text(
      pairCountdown(widget.closesAt.difference(widget.now())),
      textAlign: TextAlign.center,
      style: widget.style,
    ),
  );
}

/// What the code's place says once it is not a code: a line, why, and the
/// one button. Spoken once, as it changes.
class PairCodeOutcome extends StatelessWidget {
  const PairCodeOutcome({
    super.key,
    required this.title,
    required this.why,
    required this.primary,
  });

  final String title;
  final String why;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          container: true,
          liveRegion: true,
          label: '$title. $why',
          child: ExcludeSemantics(
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  why,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: CupolaThemeColors.of(context).dimText,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        primary,
      ],
    );
  }
}
