import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

/// A reusable tag/chip widget for displaying metadata labels.
///
/// Used in detail screens to show year, status, runtime, etc.
/// Follows Material Design 3 styling guidelines.
///
/// [color] is the chip's tone and paints the wash and the hairline as given.
/// The label and the glyph are that tone walked through [ServiceTheme.onTint]
/// against the composite they actually land on: raw, Radarr's amber on its own
/// 12% tint measured about 1.8:1 on the light scaffold.
class TagChip extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  /// The ground the chip sits on, which the label is measured against.
  /// Defaults to [ColorScheme.surface]; a chip inside a card passes the card's
  /// container.
  final Color? surface;

  const TagChip({
    super.key,
    required this.text,
    this.color,
    this.icon,
    this.surface,
  });

  static const double _tintAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.primary;
    final ink = ServiceTheme.onTint(
      effectiveColor,
      surface: surface ?? colorScheme.surface,
      tintAlpha: _tintAlpha,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: _tintAlpha),
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: ink),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall!
                .weight(FontWeight.w600)
                .copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// A genre chip specifically styled for movie/TV genres.
class GenreChip extends StatelessWidget {
  final String genre;

  const GenreChip({super.key, required this.genre});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        genre,
        style: Theme.of(context).textTheme.labelSmall!
            .weight(FontWeight.w500)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
