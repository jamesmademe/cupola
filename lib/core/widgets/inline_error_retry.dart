import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';

/// Inline failure notice with a retry action, so a failed section reads as a
/// failure rather than as an endless loading shimmer.
///
/// Every service dashboard grows sections that load independently, and a
/// section that fails must not take the whole page down: this line sits in the
/// slot the content would have occupied and offers the retry right there.
///
/// The default constructor sizes itself to its message. Use
/// [InlineErrorRetry.fixedHeight] where the notice replaces a fixed-height slot
/// (a carousel row) and a self-sizing one would make the page jump.
///
/// ## Why it is a line and not a card
///
/// It used to be a filled, bordered card: `errorContainer` at 40% behind an
/// `error` stroke at 50%, with the sentence in `onErrorContainer`. That is the
/// chrome of an alarm, and in a self-hosted stack a section that did not load
/// is a Tuesday — the download client is rebuilding, the indexer is rate
/// limited, the box is off. A page that shouts on every open is a page whose
/// shouting stops being read.
///
/// So the notice keeps its **presence** as the signal and gives up its volume:
/// no fill, no border, the sentence in `onSurfaceVariant`, and the error tone
/// spent on exactly one 16pt glyph. Three rules govern every failure surface in
/// the app and this widget is the smallest of them:
///
///  1. presence is the signal — no fill, no border, the error tone on the glyph
///     and nowhere else;
///  2. the recovery verb is never painted in the error tone — a red Retry makes
///     the cure look like the disease, so it is the primary ink;
///  3. nothing is dimmed for being unreachable, because dimming means *not
///     configured* everywhere else on this canvas.
///
/// [CapabilityBanner] is deliberately the same shape in a different tone: a
/// credential that may only read is configuration, not a fault. It could not
/// have copied this widget while this widget still carried error chrome.
///
/// ## Tone follows the cause
///
/// The [error] that failed is required, and the glyph takes the
/// classification's tone and glyph: red only when nothing answered, amber for
/// a refusal or any other failure that did answer. It used to be optional,
/// and every section that left it out stayed red for any failure — a refused
/// key read exactly like a switched-off box. Word the [message] from the same
/// classification (`sectionFailureMessage`), so the glyph and the sentence
/// cannot disagree.
class InlineErrorRetry extends StatelessWidget {
  const InlineErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
    required this.error,
  }) : _height = null;

  /// A notice locked to [_fixedHeight], for slots whose height must not change
  /// between the loading, loaded and failed states.
  const InlineErrorRetry.fixedHeight({
    super.key,
    required this.message,
    required this.onRetry,
    required this.error,
  }) : _height = _fixedHeight;

  /// Height of the [InlineErrorRetry.fixedHeight] variant.
  static const double _fixedHeight = 120;

  final String message;
  final VoidCallback onRetry;

  /// What failed, classified for the glyph's tone. See the class comment. A
  /// null is a failure nobody can attribute: amber, never read as silence.
  final Object? error;

  /// `null` for the self-sizing default; [_fixedHeight] for the fixed variant.
  final double? _height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = classifyConnectionFailure(error);

    // Walked against the surface itself, because the raw error red measures
    // around 3.4:1 on the light scaffold, and with the fill gone this glyph is
    // the only thing carrying the tone. A graphical object owes 3:1 and has no
    // coloured text beside it to lean on.
    final alarm = statusToneColor(
      colorScheme,
      failureTone(reason),
      surface: colorScheme.surface,
    );
    final glyph = failureIcon(reason);

    return Container(
      width: double.infinity,
      height: _height,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        container: true,
        // Retry stays its own control; this node owns the sentence only.
        explicitChildNodes: true,
        // Announced when it appears, which is the moment it matters. Not routed
        // through `announce()` as well: that double-reads on iOS.
        liveRegion: true,
        label: message,
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(glyph, size: 16, color: alarm)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                // Rule 2. Brand primary, never the error tone.
                foregroundColor: colorScheme.primary,
                // 44pt on iOS / 48dp on Android is the floor, and this button
                // shares its row with body text that would otherwise size it.
                // No `VisualDensity.compact`: it silently takes 8 off
                // `minimumSize`, and 44 declared measured 40.
                minimumSize: const Size(56, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
