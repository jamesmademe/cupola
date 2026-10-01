import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A failure state with the remedy that fits its cause.
///
/// Replaces the private, retry-less error widget inside [AsyncValueWidget].
/// When [onRetry] is provided a "Retry" button is shown, wired by callers
/// to their existing `ref.invalidate(...)` refresh path, unless the cause has
/// a remedy that retrying cannot stand in for (see *The remedy leads*).
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
///
/// ## The remedy leads
///
/// When the failure names a fix that lives in the connection's form, and
/// [serviceName] says whose connection it is, that fix is the primary action
/// ([FailureRemedy]), in the fault's one amber fill ([remedyFillStyle]): `Paste the key again` for a refused key, `Change the
/// address` for an `http://` address the device would not dial, `Check the
/// address` or `Check the certificate` when the server answered from the wrong
/// place or with a certificate Cupola does not trust. It opens the form. Retry
/// follows as the text action only where the same request can still succeed;
/// a refused key or an address nothing was sent to can only be refused again,
/// so there it is left out. A refused sign-in keeps it, because a ban for too
/// many attempts runs out. Every caller gets this from the error and the name
/// it already passes. A state that cannot name the service keeps Retry,
/// and nothing else, because it cannot say whose form to open.
///
/// Retry alone is the remedy too: in the amber fill for a fault (a 5xx, a
/// timeout), and a ghost button in ink beside silence, never filled.
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
  ServiceKey? get _service => FailureRemedy.serviceNamedBy(serviceName);

  String _headline(ServiceFailureReason reason) {
    final service = _service;
    if (service != null) return describeFailure(service, reason).headline;
    final headline = failureHeadline(reason, subject: 'the server');
    return headline[0].toUpperCase() + headline.substring(1);
  }

  /// The sentence under the headline, or null when it would say the same
  /// thing again: a failure nobody can attribute has nothing to add to "The
  /// request to Radarr did not complete" unless it carries its own words.
  ///
  /// Beside a remedy button the sentence stops at the fact: "Check them in
  /// Settings." would say the button again in words.
  static String? _detail(
    Object error,
    ServiceFailureReason reason, {
    required bool remedyBeside,
  }) {
    final own = connectionFailureDetail(error);
    if (own != null && own.trim().isNotEmpty) return own;
    if (reason == ServiceFailureReason.unknown) return null;
    return connectionFailureSentence(error, remedyBeside: remedyBeside);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = classifyConnectionFailure(error);
    final remedy = FailureRemedy.of(_service, error);
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
            if (_detail(error, reason, remedyBeside: remedy != null)
                case final detail?) ...[
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
            if (_actions(context, reason, remedy) case final actions?) ...[
              const SizedBox(height: AppSpacing.xl),
              actions,
            ],
          ],
        ),
      ),
    );
  }

  /// The remedy in the amber fill and Retry as the text action beside it, or
  /// Retry alone when there is no remedy. See *The remedy leads*.
  Widget? _actions(
    BuildContext context,
    ServiceFailureReason reason,
    FailureRemedy? remedy,
  ) {
    final retry = onRetry;
    if (remedy == null) {
      if (retry == null) return null;
      const glyph = Icon(Icons.refresh_rounded, size: 18);
      const label = Text(Lexicon.retry);
      // Retry is the remedy here. Of a fault it takes the fault's one amber
      // fill; beside silence it is a ghost in ink, never filled and never red,
      // because a red cure looks like the disease.
      return failureIsFault(reason)
          ? FilledButton.icon(
              onPressed: retry,
              style: remedyFillStyle(context),
              icon: glyph,
              label: label,
            )
          : OutlinedButton.icon(onPressed: retry, icon: glyph, label: label);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton(
          onPressed: () => remedy.open(context),
          style: remedyFillStyle(context),
          child: Text(remedy.label),
        ),
        // Text in ink: the fault has one fill, and it is on the remedy. The
        // theme's text button keeps the 44pt floor.
        if (retry != null && remedy.retryHelps)
          TextButton(onPressed: retry, child: const Text(Lexicon.retry)),
      ],
    );
  }
}
