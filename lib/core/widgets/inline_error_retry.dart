import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';

/// Inline error placeholder with a retry action, so a failed section reads as a
/// failure rather than as an endless loading shimmer.
///
/// Every service dashboard grows sections that load independently, and a
/// section that fails must not take the whole page down: this card sits in the
/// slot the content would have occupied and offers the retry right there.
///
/// The default constructor sizes itself to its message. Use
/// [InlineErrorRetry.fixedHeight] where the card replaces a fixed-height slot
/// (a carousel row) and a self-sizing card would make the page jump.
class InlineErrorRetry extends StatelessWidget {
  const InlineErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
  }) : _height = null;

  /// A card locked to [_fixedHeight], for slots whose height must not change
  /// between the loading, loaded and failed states.
  const InlineErrorRetry.fixedHeight({
    super.key,
    required this.message,
    required this.onRetry,
  }) : _height = _fixedHeight;

  /// Height of the [InlineErrorRetry.fixedHeight] variant.
  static const double _fixedHeight = 120;

  final String message;
  final VoidCallback onRetry;

  /// `null` for the self-sizing default; [_fixedHeight] for the fixed variant.
  final double? _height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: _height,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
