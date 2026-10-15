import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// The ways in, in the order they save work: the Welcome's and the Home at
/// zero's, so the two say the same thing in the same words.
///
/// "Set up a service" starts with Seerr, because Seerr already knows the
/// user's Radarr and Sonarr with their keys. "I have a Seerr account" is the
/// household member's: their own account on someone else's Seerr. The third
/// the design names (copying everything from another device) arrives with the
/// work that keeps it: a door the app cannot keep yet is not drawn.
class SetupDoors extends StatelessWidget {
  const SetupDoors({super.key, required this.onSetUp, required this.onSignIn});

  /// Opens Connect, with Seerr proposed.
  final VoidCallback onSetUp;

  /// Opens the sign-in with a Seerr account.
  final VoidCallback onSignIn;

  /// What the primary door leads with. Said under it rather than in it, so
  /// the button stays a verb.
  static const setUpHint =
      'Start with Seerr: it already knows your Radarr and Sonarr, keys '
      'included.';

  /// What the account door is for, under it the same way.
  static const signInHint = 'Sign in to ask for movies and series.';

  /// Whether the doors' lines are drawn: not past the reading size where
  /// two buttons stop sharing a line (`OnboardingFooter`'s), where the two
  /// doors and their lines are taller than a short phone leaves under the
  /// ring and the doors are pinned there (15/10). Each line is still said,
  /// as its door's hint.
  static bool showsLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) <= 20;

  @override
  Widget build(BuildContext context) {
    final lines = showsLines(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: onSetUp,
          // On the label, which the button merges: a hint wrapped around the
          // button is dropped.
          child: Semantics(
            hint: setUpHint,
            child: const Text('Set up a service'),
          ),
        ),
        if (lines) ...[
          const SizedBox(height: AppSpacing.sm),
          const _Hint(setUpHint),
        ],
        SizedBox(height: lines ? AppSpacing.lg : AppSpacing.sm),
        OutlinedButton(
          onPressed: onSignIn,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(64, 44),
          ),
          child: Semantics(
            hint: signInHint,
            child: const Text('I have a Seerr account'),
          ),
        ),
        if (lines) ...[
          const SizedBox(height: AppSpacing.sm),
          const _Hint(signInHint),
        ],
      ],
    );
  }
}

/// A door's line under it, silent: the door already says it as its hint.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: CupolaThemeColors.of(context).dimText,
      ),
    ),
  );
}
