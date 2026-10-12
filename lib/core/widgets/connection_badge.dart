import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

/// The name of the connection a row came off, in the app's one shape for it.
///
/// The rule this widget exists to keep in one place: a connection is named
/// **only when there is more than one to tell apart**. Callers pass an empty
/// [label] for a service with a single connection and get nothing back: a
/// stack with one Radarr must not grow a badge naming the only Radarr there is.
/// That is the same rule `ServiceConnectionRow` follows on the Connections
/// screen and `ServiceMatrixCell` follows on the Portal.
///
/// Tinted by the service accent and set in the micro role as the connection is
/// named, never recased, since the name is the user's, matching the badge
/// the global search puts on a section heading. Search can say it once per
/// section because one leg queries one server; the Activity feed interleaves
/// connections inside one service group, so its badge belongs on the row.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    super.key,
    required this.label,
    required this.accent,
    this.surface,
  });

  /// The connection's name, or empty to render nothing.
  final String label;

  final Color accent;

  /// The ground the badge sits on, defaulting to [ColorScheme.surface]. The
  /// label is the accent walked against its 14% wash over this, so a badge on a
  /// card passes the card's container.
  final Color? surface;

  static const double _tintAlpha = 0.14;
  static const double _edgeAlpha = 0.34;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();

    final ink = ServiceTheme.onTint(
      accent,
      surface: surface ?? Theme.of(context).colorScheme.surface,
      tintAlpha: _tintAlpha,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: _tintAlpha),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXs2),
        border: Border.all(color: accent.withValues(alpha: _edgeAlpha)),
      ),
      child: Text(label, style: AppTheme.chrome(context, color: ink)),
    );
  }
}
