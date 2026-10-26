import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';

/// The ways in, in the order they save work: the Welcome's and the Home at
/// zero's, so the two say the same thing in the same words.
///
/// "Set up a service" starts with Seerr, because Seerr already knows the
/// user's Radarr and Sonarr with their keys. "I have a Seerr account" is the
/// household member's: their own account on someone else's Seerr. "Copy from
/// another device" comes last and quietest, a link in ink under the two
/// buttons: whoever copies already has Cupola somewhere, and the camera
/// pointed at the other device's code opens the copy without passing here, so
/// this door is mostly the way of a computer, which pastes the link.
///
/// "Explore a demo home", on the Welcome alone ([onDemo]), is the last link,
/// as quiet as the copy: the way for someone with no server yet to see what
/// Cupola does, and the one an App Store reviewer takes.
class SetupDoors extends StatelessWidget {
  const SetupDoors({
    super.key,
    required this.onSetUp,
    required this.onCopy,
    required this.onSignIn,
    this.onDemo,
    this.showLines,
  });

  /// Opens Connect, with Seerr proposed.
  final VoidCallback onSetUp;

  /// Opens the screen that copies everything from another device.
  final VoidCallback onCopy;

  /// Opens the sign-in with a Seerr account.
  final VoidCallback onSignIn;

  /// Opens the demo home, or null where the demo is not offered: anywhere
  /// but a Welcome with no connection.
  final VoidCallback? onDemo;

  /// Whether the lines under the doors are drawn; null leaves it to
  /// [showsLines]. A caller that knows how much room the doors have says.
  final bool? showLines;

  /// What the primary door leads with. Said under it rather than in it, so
  /// the button stays a verb.
  static const setUpHint =
      'Start with Seerr: it already knows your Radarr and Sonarr, keys '
      'included.';

  /// What the copy door is for, under it the same way.
  static const copyHint = 'Point the camera at the code on your other device';

  /// What the account door is for, under it the same way.
  static const signInHint = 'Sign in to ask for movies and series.';

  /// What the demo door is for, under it the same way.
  static const demoHint = 'No server needed. Nothing is saved.';

  /// Whether the doors' lines are drawn when the caller does not say
  /// ([SetupDoors.showLines]): not past the reading size where two buttons
  /// stop sharing a line (`OnboardingFooter`'s), where the three doors and
  /// their lines are taller than a short phone leaves under the ring and the
  /// doors are pinned there (15/10). Each line is still said, as its door's
  /// hint.
  ///
  /// The Welcome pins the doors under its claim and decides for itself,
  /// from the room it has (`OnboardingWelcome.roomForDoorLines`); the Home at
  /// zero scrolls, and takes this.
  static bool showsLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) <= 20;

  @override
  Widget build(BuildContext context) {
    final lines = showLines ?? showsLines(context);
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
        SizedBox(height: lines ? AppSpacing.md : AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: onCopy,
            style: _quietStyle(context),
            child: Semantics(
              hint: copyHint,
              child: const Text('Copy from another device'),
            ),
          ),
        ),
        if (lines) ...[
          const SizedBox(height: AppSpacing.xs),
          const _Hint(copyHint, align: TextAlign.center),
        ],
        if (onDemo case final onDemo?) ...[
          SizedBox(height: lines ? AppSpacing.sm : 0),
          Center(
            child: TextButton(
              onPressed: onDemo,
              style: _quietStyle(context),
              child: Semantics(
                hint: demoHint,
                child: const Text('Explore a demo home'),
              ),
            ),
          ),
          if (lines) ...[
            const SizedBox(height: AppSpacing.xs),
            const _Hint(demoHint, align: TextAlign.center),
          ],
        ],
      ],
    );
  }
}

/// The quiet doors' links, in ink. 44pt tall on iOS, its floor, rather than
/// the 48 Material pads every button to: on a 667pt phone at 1.4 times the
/// reading size the four doors otherwise cover the end of the Welcome's
/// sentence. Android keeps its 48dp.
ButtonStyle _quietStyle(BuildContext context) {
  final theme = Theme.of(context);
  return retryInkStyle(theme.colorScheme).copyWith(
    tapTargetSize: theme.platform == TargetPlatform.iOS
        ? MaterialTapTargetSize.shrinkWrap
        : null,
  );
}

/// A door's line under it, silent: the door already says it as its hint.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.align});

  final String text;

  /// Centred under the copy link, which is centred; flush with the buttons'
  /// edge under the two buttons.
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: CupolaThemeColors.of(context).dimText,
      ),
    ),
  );
}
