import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A premium error state with an optional retry affordance.
///
/// Replaces the private, retry-less error widget inside [AsyncValueWidget].
/// When [onRetry] is provided a "Retry" button is shown, wired by callers
/// to their existing `ref.invalidate(...)` refresh path.
///
/// ## What the user reads first
///
/// The headline names what failed; [error] is demoted to a detail line beneath
/// it. It used to be the reverse in effect — "Something went wrong" said nothing,
/// so the raw `error.toString()` under it was the message, and on this app's
/// failures that is a Dio exception with a URL and a status code in it. That is
/// diagnostics, not an explanation, and it was the first thing the eye landed on.
///
/// ## The detail is a sentence, never the exception
///
/// The raw `error.toString()` survived as the detail line for a while, on the
/// argument that a self-hoster can act on "connection refused". What it
/// actually printed was a class name and a library's own apology — "DioException
/// [connection error]: The connection errored: Connection refused This
/// indicates an error which most likely cannot be solved by the library." — on
/// every failed load in the app. The detail now comes from the failure
/// classification ([connectionFailureSentence]): the same causes the connection
/// form names, without a service to name.
///
/// ## Tone follows the cause
///
/// Red only when nothing answered (or the failure cannot be attributed). A host
/// that answered — a rejected key, a 5xx, a timeout, a certificate — is a
/// **fault**, amber, because there is one concrete thing to go and fix; the
/// split is [failureIsFault], the same one `describeConnection` makes.
class AppErrorState extends StatelessWidget {
  /// How strongly an amber well is washed over the surface.
  static const double _faultWellAlpha = 0.16;

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  /// What could not be loaded, for the headline: "Couldn't load Radarr".
  ///
  /// Optional because a handful of callers sit on screens where the subject is
  /// already unambiguous; those fall back to naming the surface generically.
  final String? serviceName;

  const AppErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.serviceName,
  }) : compact = false;

  const AppErrorState.compact({
    super.key,
    required this.error,
    this.onRetry,
    this.serviceName,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = failureIsFault(classifyConnectionFailure(error))
        ? StatusTone.warning
        : StatusTone.error;
    // Red keeps its `error-container` well; amber gets its own tone as a wash,
    // and each glyph is walked against the well it actually sits on.
    final Color well;
    final Color glyph;
    if (tone == StatusTone.error) {
      well = colorScheme.errorContainer;
      glyph = statusToneColor(colorScheme, tone, surface: well);
    } else {
      well = Color.alphaBlend(
        statusToneFill(colorScheme, tone).withValues(alpha: _faultWellAlpha),
        colorScheme.surface,
      );
      glyph = statusToneColor(
        colorScheme,
        tone,
        surface: colorScheme.surface,
        tintAlpha: _faultWellAlpha,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: well, shape: BoxShape.circle),
              child: Icon(
                Icons.error_outline_rounded,
                size: compact ? 26 : 32,
                color: glyph,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              serviceName == null
                  ? "Couldn't load this"
                  : "Couldn't load $serviceName",
              style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            // The detail, not the message: one step down the type ladder and a
            // step dimmer, so the sentence above it is what gets read. Plain
            // words from the classification — see the class comment.
            Text(
              connectionFailureSentence(error),
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.extension<CupolaThemeColors>()?.dimText ??
                    colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
