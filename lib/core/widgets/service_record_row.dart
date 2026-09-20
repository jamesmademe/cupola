import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// One record in a service tab's list: a tone-walked glyph, a title over a
/// dim detail line, and a figure on the trailing edge.
///
/// Extracted from the Plex and Jellyfin tab screens, where the same seventy
/// lines were written twice, character for character, in a single pass. Three
/// things in it are load-bearing and all three are the kind that drift apart
/// once there are two copies: the colour comes from [statusToneColor] rather
/// than a raw `AppColors` arm, so the tone is walked for contrast against the
/// surface it lands on; the title and the figure go through [AppTheme]'s named
/// roles rather than a bare `TextStyle(fontSize:)`, which never reaches the
/// `wght` axis of the bundled variable Inter and renders Regular whatever
/// weight it asks for; and the row speaks **one** sentence, with
/// [ExcludeSemantics] silencing the parts, which is what keeps a screen reader
/// from reading a title, a detail and a number as three unrelated nodes.
///
/// Not every row in the app is this row. A variant whose detail wraps freely,
/// or whose figure sits on a different type role, is a different row and says
/// so by staying where it is — NZBGet's is exactly that and is deliberately
/// left alone.
class ServiceRecordRow extends StatelessWidget {
  const ServiceRecordRow({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.semanticLabel,
  });

  final IconData icon;
  final StatusTone tone;
  final String title;
  final String detail;
  final String trailing;

  /// The whole sentence the row speaks. The parts are silenced beneath it.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(theme.colorScheme, tone);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  trailing,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTheme.data(theme.brightness).copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
