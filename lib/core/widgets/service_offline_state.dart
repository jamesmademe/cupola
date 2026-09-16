import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/sample_age.dart';

/// The leaf for a configured service that did not answer, where there is
/// genuinely nothing else to draw.
///
/// Distinct from `NotConfiguredPlaceholder` (no URL or credential saved) — that
/// state asks the user to go and set something up, this one reports that
/// something already set up has gone quiet. The two are not interchangeable and
/// the app must never dim for the second: dimming means *not configured*
/// everywhere else on this canvas.
///
/// ## Use `FaultBand.unreachable` instead, wherever you can
///
/// This widget is the fallback, not the answer. A page that has *any* retained
/// readout — a queue from two minutes ago, an array that was already degraded,
/// a version string — owes the operator that readout at full ink with a
/// [FaultBand] above it, because the last thing the box said before it went
/// dark is precisely what they opened the app to see. Replacing the page
/// throws it away. This leaf is for the cold open, where the service has never
/// answered in this session and there is nothing behind the band.
///
/// ## What changed in the copy
///
/// It used to offer troubleshooting — *"Cupola can't reach the server. Check
/// that X is running and that the URL in Settings is reachable."* That is a
/// checklist for a first-time setup, printed at a user who has already set the
/// service up and mostly knows why it is down. The design states a fact and an
/// age instead, because the age is the only thing here the user does not
/// already know: thirty seconds is a restart, forty minutes is an outage, and
/// those are different decisions. And it gives the second action the fact
/// implies — when the *address* is what changed, no number of retries helps.
class ServiceOfflineState extends StatelessWidget {
  const ServiceOfflineState({
    super.key,
    required this.serviceName,
    required this.accent,
    required this.onRetry,
    this.since,
    this.onOpenSettings,
  });

  final String serviceName;
  final Color accent;
  final VoidCallback onRetry;

  /// How long it has been quiet. Absent until something records a first-failure
  /// time; the sentence drops the span rather than inventing one.
  final Duration? since;

  /// The second half of "the action is the fix". Optional only because not
  /// every host has a router to push with.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final span = since == null ? null : formatElapsedSpan(since!);
    final body = span == null
        ? 'No response. Anything it holds is missing from this page.'
        : 'No response for $span. Anything it holds is missing from this page.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: '$serviceName did not answer. $body',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No fill behind it. Presence is the signal, and a page that has
              // already emptied itself does not need a second announcement in
              // a tinted circle — the glyph alone carries the tone, measured
              // against the ground it sits on.
              ExcludeSemantics(
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 32,
                  color: ServiceTheme.onTint(
                    accent,
                    surface: colorScheme.surface,
                    tintAlpha: 0,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ExcludeSemantics(
                child: Text(
                  '$serviceName did not answer',
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ExcludeSemantics(
                child: Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                  if (onOpenSettings != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    // A text action, not a second filled button: there is one
                    // thing to try first and one thing to try if it fails, and
                    // two equal buttons would not say which.
                    TextButton(
                      onPressed: onOpenSettings,
                      style: TextButton.styleFrom(
                        // Never the error tone: painting the recovery in the
                        // fault's own colour makes the cure look like the
                        // disease.
                        foregroundColor: colorScheme.primary,
                        minimumSize: const Size(56, 44),
                      ),
                      child: const Text('Settings'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
