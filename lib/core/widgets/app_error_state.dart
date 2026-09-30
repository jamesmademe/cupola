import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
/// The state is said once, in words and tone together: the headline is set in
/// the state's tone (`Radarr did not answer` in red, `Radarr answered but
/// refused the key` in amber), and the sentence under it says why or what to
/// do instead of repeating it. There is **no well** behind
/// the glyph — the brand book's Presence Rule: a fault is a quiet line, and a
/// red fill is the disease drawn as chrome. The glyph alone carries the tone,
/// measured against the ground it sits on.
class AppErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  /// Who the headline names: `Radarr did not answer`, `Radarr answered but
  /// refused the key`.
  ///
  /// A page may pass more than the service (`Seerr issues`, `Bazarr
  /// history`); the headline names the service it starts with, because the
  /// service is what did or did not answer. Optional because a handful of
  /// callers sit on screens where the subject is already unambiguous; those,
  /// and a name that is no service, fall back to naming the server.
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

  /// The service [serviceName] names, when it names one.
  ServiceKey? get _service {
    final name = serviceName?.trim();
    if (name == null || name.isEmpty) return null;
    for (final service in ServiceKey.values) {
      if (name == service.title || name.startsWith('${service.title} ')) {
        return service;
      }
    }
    return null;
  }

  String _headline(ServiceFailureReason reason) {
    final service = _service;
    if (service != null) return describeFailure(service, reason).headline;
    final headline = failureHeadline(reason, subject: 'the server');
    return headline[0].toUpperCase() + headline.substring(1);
  }

  /// The sentence under the headline, or null when it would say the same
  /// thing again: a failure nobody can attribute has nothing to add to "The
  /// request to Radarr did not complete" unless it carries its own words.
  static String? _detail(Object error, ServiceFailureReason reason) {
    final own = connectionFailureDetail(error);
    if (own != null && own.trim().isNotEmpty) return own;
    if (reason == ServiceFailureReason.unknown) return null;
    return connectionFailureSentence(error);
  }

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
            // What happened, naming who, in the tone of the state — the
            // brand book's fault sentence, said once: the classification's
            // headline, never "Couldn't load Radarr", and red only when
            // nothing answered.
            Text(
              _headline(reason),
              style: theme.textTheme.titleMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: toneInk),
              textAlign: TextAlign.center,
            ),
            // Why, or what to do: one step down the type ladder and a step
            // dimmer. Plain words from the classification — see the class
            // comment — and left out when they would only restate the
            // headline.
            if (_detail(error, reason) case final detail?) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      theme.extension<CupolaThemeColors>()?.dimText ??
                      colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
