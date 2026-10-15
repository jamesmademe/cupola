import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// One notice of a flow that has steps, the quiet way a failure line is: the
/// glyph in its tone, the title, the sentence, and its verbs. Heard as one
/// sentence.
///
/// What a step of signing in to Seerr says when it stops, and what copying
/// from another device says when nothing arrived: a tone, a headline, a
/// sentence and the verbs that remedy it, and nothing else. The words are the
/// caller's (each flow keeps its own in one place), the tone is the five-arm
/// rule's: red only for a device or server that did not answer, amber for a
/// fault, blue for a step that is the person's own, never a fault.
///
/// The glyph follows the tone, so a notice read without colour still says
/// which kind it is: a cloud struck through for red, an `i` for blue, a
/// circled `!` for the rest. The verbs are [noticeAction]s.
class NoticeLine extends StatelessWidget {
  const NoticeLine({
    super.key,
    required this.tone,
    required this.title,
    this.sentence,
    this.actions = const [],
  });

  final StatusTone tone;

  /// What happened, in a line.
  final String title;

  /// What to do about it, or why, when the title leaves a question.
  final String? sentence;

  /// The verbs, in the order they are offered: [noticeAction]s.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ink = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surface,
    );
    final glyph = switch (tone) {
      StatusTone.error => Icons.cloud_off_rounded,
      StatusTone.info => Icons.info_outline_rounded,
      _ => Icons.error_outline_rounded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          // The whole notice as one sentence.
          label: sentence == null ? '$title.' : '$title. $sentence',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(glyph, size: 16, color: ink),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall!
                            .weight(FontWeight.w600)
                            .copyWith(color: ink),
                      ),
                      if (sentence case final sentence?)
                        Text(
                          sentence,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// A verb of a notice. [fill] is the tone of the notice it remedies, for the
/// one fill a notice gets: amber for a fault, ink otherwise. Without it, text
/// in ink.
Widget noticeAction(
  BuildContext context,
  String label,
  VoidCallback onPressed, {
  StatusTone? fill,
}) => Align(
  alignment: AlignmentDirectional.centerStart,
  child: fill != null
      ? FilledButton(
          onPressed: onPressed,
          style: remedyFillStyle(
            context,
            compact: true,
            fault: fill == StatusTone.warning,
          ),
          child: Text(label),
        )
      : TextButton(
          onPressed: onPressed,
          style: retryInkStyle(Theme.of(context).colorScheme),
          child: Text(label),
        ),
);
