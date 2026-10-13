import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// The ways in, in the order they save work: the Welcome's and the Home at
/// zero's, so the two say the same thing in the same words.
///
/// One door for now, "Set up a service", which starts with Seerr because Seerr
/// already knows the user's Radarr and Sonarr with their keys. The other two
/// the design names (copying everything from another device, and signing in
/// with a Seerr account) arrive with the work that keeps them: a door the app
/// cannot keep yet is not drawn.
class SetupDoors extends StatelessWidget {
  const SetupDoors({super.key, required this.onSetUp});

  /// Opens Connect, with Seerr proposed.
  final VoidCallback onSetUp;

  /// What the primary door leads with. Said under it rather than in it, so
  /// the button stays a verb.
  static const setUpHint =
      'Start with Seerr: it already knows your Radarr and Sonarr, keys '
      'included.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        const SizedBox(height: AppSpacing.sm),
        ExcludeSemantics(
          child: Text(
            setUpHint,
            style: theme.textTheme.bodySmall!.copyWith(
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        ),
      ],
    );
  }
}
