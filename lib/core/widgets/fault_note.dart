import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A failure sentence with no recovery verb of its own: the smallest member of
/// the family [FaultBand] and [InlineErrorRetry] belong to, for the places that
/// already offer the retry somewhere else — a form sheet whose submit button is
/// the retry, a purchase the user starts again by tapping a tier.
///
/// It follows the same presence rule. The tone is spent on one 16pt glyph and
/// nowhere else, and the sentence is `onSurfaceVariant`. The sites it replaced
/// painted the whole sentence in the error red, which put the alarm colour on
/// the words and, on paper, measured under 4.5:1 as text.
///
/// The two constructors are the two arms a failed call can land on:
///
///  * [FaultNote.unreachable] — the source did not answer, so the glyph is red,
///    the one thing red means in a status. A load that never came back is this.
///  * [FaultNote.fault] — the source answered and said no, or the operation
///    failed after it started. Amber, because nothing is unreachable.
///
/// [surface] is the ground the note sits on, which the glyph is walked against;
/// it defaults to [ColorScheme.surface]. Pass the sheet or card it is in.
class FaultNote extends StatelessWidget {
  /// The source did not answer.
  const FaultNote.unreachable({super.key, required this.message, this.surface})
    : _tone = StatusTone.error,
      _icon = Icons.error_outline_rounded;

  /// The source answered with a failure.
  const FaultNote.fault({super.key, required this.message, this.surface})
    : _tone = StatusTone.warning,
      _icon = Icons.warning_amber_rounded;

  final String message;
  final Color? surface;
  final StatusTone _tone;
  final IconData _icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Decorative: the sentence beside it says what happened.
        ExcludeSemantics(
          child: Icon(
            _icon,
            size: 16,
            color: statusToneColor(colorScheme, _tone, surface: surface),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
