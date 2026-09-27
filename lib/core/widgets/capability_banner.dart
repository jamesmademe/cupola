import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// What this credential cannot do, said once, at the top of the page.
///
/// The same line as [InlineErrorRetry] and [FaultBand] — no fill, no border,
/// one 16pt glyph, a sentence in `onSurfaceVariant`, one verb in brand
/// primary — in the one tone none of them uses.
///
/// ## Why it is blue
///
/// Because nothing is wrong. An Unraid key issued without write scope, a
/// TrueNAS token that can only read, a Jellyfin account with no admin policy,
/// an NPM login with a view-only role: in every case the credential is working
/// exactly as it was created, and the app is reporting a **configuration fact**.
/// Amber would put it in the same bucket as a stalled transfer and a failing
/// indexer, which is a category error the user pays for — they would go looking
/// for a fault that does not exist. Under the tone rule blue is "informational",
/// and this is the definition of it.
///
/// It is also why the banner does not dismiss. There is nothing to acknowledge:
/// the scope is still what it is a second later, and the controls below are
/// still dimmed. The only thing that changes it is a new key, which is what the
/// action offers.
///
/// ## What it does not do
///
/// It does not hide the writes it describes, and it does not stop the readouts.
/// A read-only connection still reads perfectly well, so the page keeps
/// refreshing and every write below dims to 38% through [CapabilityGatedAction]
/// while staying reachable. The banner exists so that dimming has an
/// explanation the user can find without pressing anything.
class CapabilityBanner extends StatelessWidget {
  const CapabilityBanner({
    super.key,
    required this.message,
    required this.onFix,
    this.actionLabel = 'Update the key',
  });

  /// What this credential cannot do, in the user's terms and in its own words:
  /// *"This Unraid key can read. Start, stop and update need a key with write
  /// scope."* Two sentences — what it can do, then what it cannot — because a
  /// banner that only lists the refusals reads as breakage.
  ///
  /// The caller writes it: the scope names differ per service and a generic
  /// "limited permissions" would tell nobody which setting to change.
  final String message;

  /// The fix. Lands on the page where that connection's credential is replaced.
  final VoidCallback onFix;

  /// Overridable for the services whose credential is not a key — NPM hands out
  /// a *role*, and "Update the key" would send the user looking for a field
  /// that does not exist.
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // `StatusTone.info`, resolved through the same walk every other tone takes:
    // raw blue measures about 3.3:1 on the light scaffold, and with no fill
    // behind it this glyph is the only thing carrying the tone.
    final glyph = statusToneColor(
      colorScheme,
      StatusTone.info,
      surface: colorScheme.surface,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Semantics(
        container: true,
        // The fix stays its own control; this node owns the sentence.
        explicitChildNodes: true,
        // Announced when it appears — it changes what every control below it
        // will do, which is worth hearing before pressing one.
        liveRegion: true,
        label: message,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.key_outlined, size: 16, color: glyph),
            ),
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
              onPressed: onFix,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                // No `VisualDensity.compact`: it silently takes 8 off
                // `minimumSize`, and 44 declared measured 40.
                minimumSize: const Size(56, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
