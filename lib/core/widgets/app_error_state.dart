import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';

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
/// Red only when nothing answered. A host that answered — a refused key, a
/// 5xx, a timeout after connecting, a reply nobody can read, a certificate — is
/// a **fault**, amber, because there is one concrete thing to go and fix; and
/// so is a failure nobody can attribute, because "did not answer" is a claim
/// about the host that nothing supports. The split is [failureTone], the same
/// one every other failure surface makes.
///
/// The state is said in words as well as tone: the classified label (`Did not
/// answer`, `Refused the key`) sits under the headline in the state's tone,
/// which is the one place the tone reaches text. There is **no well** behind
/// the glyph — the brand book's Presence Rule: a fault is a quiet line, and a
/// red fill is the disease drawn as chrome. The glyph alone carries the tone,
/// measured against the ground it sits on.
class AppErrorState extends StatelessWidget {
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
    final reason = classifyConnectionFailure(error);
    // Walked against the ground the glyph and the label actually sit on: the
    // page, with nothing behind them.
    final toneInk = statusToneColor(colorScheme, failureTone(reason));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failureIcon(reason), size: compact ? 26 : 32, color: toneInk),
            const SizedBox(height: AppSpacing.lg),
            Text(
              serviceName == null
                  ? "Couldn't load this"
                  : "Couldn't load $serviceName",
              style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            // The state in its tone: the one word on this leaf that is red,
            // and only when nothing answered.
            Text(
              failureLabel(reason),
              style: theme.textTheme.labelMedium
                  ?.weight(FontWeight.w600)
                  .copyWith(color: toneInk),
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
