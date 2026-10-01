import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
///
/// ## `.failure`: the same leaf, told *why*
///
/// [ServiceOfflineState.failure] takes the service and the error a read threw,
/// and says what the classification says rather than assuming silence: the
/// title (`Radarr answered but refused the key`), glyph and tone come from
/// `describeFailure`, the sentence from `connectionFailureMessage` (or the
/// failure's own verbatim detail), and the address is the lens connection's
/// host. Red only when nothing answered; a refused key, a 5xx, a timeout or a
/// certificate is a **fault**, amber. It never prints the exception — a class
/// name and a library's message are diagnostics, and they were the whole
/// detail line of every failed load.
///
/// When the fault names a fix that lives in the connection's form
/// ([FailureRemedy]), the fix leads: `Paste the key again`, `Change the
/// address`, `Check the certificate` is the button in the fault's one amber
/// fill ([remedyFillStyle]), and Retry follows
/// as the text action only where the same request can still succeed. A
/// refused key or an address nothing was sent to has no Retry at all. Every
/// other cause keeps Retry first and `Settings` after it, because there the
/// next request may well answer: Retry in the amber fill for a fault, and a
/// ghost button in ink beside silence, never filled.

class ServiceOfflineState extends StatelessWidget {
  const ServiceOfflineState({
    super.key,
    required this.serviceName,
    required this.accent,
    required this.onRetry,
    this.since,
    this.onOpenSettings,
  }) : _service = null,
       _error = null;

  /// The leaf for a read of [service] that failed with [error], in the words
  /// the failure classification has for it. See the class comment.
  ///
  /// [onOpenSettings] defaults to [service]'s own connection form: a failed
  /// read is the moment the address or the key is most likely what changed.
  ServiceOfflineState.failure({
    super.key,
    required ServiceKey service,
    required Object error,
    required this.onRetry,
    this.since,
    this.onOpenSettings,
  }) : serviceName = service.title,
       accent = service.accent,
       _service = service,
       _error = error;

  /// The leaf for a service whose reachability probe came back failed: the
  /// plain leaf when nothing answered, and [ServiceOfflineState.failure]'s
  /// words when it answered with a refusal or a fault.
  ///
  /// The screens that gate on the probe used to draw the plain leaf for any
  /// failed summary, so a SABnzbd that refused the key read "SABnzbd did not
  /// answer" — red, about a server that had just answered.
  factory ServiceOfflineState.fromSummary({
    Key? key,
    required ServiceSummary summary,
    required VoidCallback onRetry,
    Duration? since,
    VoidCallback? onOpenSettings,
  }) {
    final service = summary.service;
    if (summary.isFault) {
      return ServiceOfflineState.failure(
        key: key,
        service: service,
        error:
            summary.failure ??
            ClassifiedFailure(
              summary.failureReason ?? ServiceFailureReason.unknown,
            ),
        onRetry: onRetry,
        since: since,
        onOpenSettings: onOpenSettings,
      );
    }
    return ServiceOfflineState(
      key: key,
      serviceName: service.title,
      accent: service.accent,
      onRetry: onRetry,
      since: since,
      onOpenSettings: onOpenSettings,
    );
  }

  final String serviceName;

  /// The service's accent, which this leaf no longer paints: a service's
  /// colour is registry data, and the glyph carries the state's tone instead.
  final Color accent;

  final VoidCallback onRetry;

  /// How long it has been quiet. Absent until something records a first-failure
  /// time; the sentence drops the span rather than inventing one.
  final Duration? since;

  /// The second half of "the action is the fix". Optional only because not
  /// every host has a router to push with.
  final VoidCallback? onOpenSettings;

  /// Set by [ServiceOfflineState.failure] only.
  final ServiceKey? _service;
  final Object? _error;

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      final span = since == null ? null : formatElapsedSpan(since!);
      return _OfflineLeaf(
        icon: failureIcon(ServiceFailureReason.unreachable),
        // The plain leaf says "did not answer" in its title, so its glyph
        // carries that state's tone: red, walked against the page. It used to
        // carry the service's light, which is the neutral lamp, and the one
        // state red exists for drew the only grey glyph among the failures.
        glyphColor: statusToneColor(
          Theme.of(context).colorScheme,
          failureTone(ServiceFailureReason.unreachable),
        ),
        title: failureHeadline(
          ServiceFailureReason.unreachable,
          subject: serviceName,
        ),
        body: span == null
            ? 'Anything it holds is missing from this page.'
            : 'It has not answered for $span. Anything it holds is missing '
                  'from this page.',
        primary: _LeafAction.retry(onRetry),
        fault: false,
        secondary: onOpenSettings == null
            ? null
            : _LeafAction('Settings', onOpenSettings!),
      );
    }

    final reason = classifyConnectionFailure(_error);
    final presentation = describeFailure(service, reason, subject: serviceName);
    final span = since == null ? null : formatElapsedSpan(since!);
    final silent = presentation.didNotAnswer;
    final message =
        connectionFailureDetail(_error) ??
        connectionFailureMessage(service, reason);
    final remedy = FailureRemedy.forReason(service, reason);

    return Consumer(
      builder: (context, ref, _) {
        final host = service.extractHost(
          ref.watch(activeInstanceProvider(service))?.url,
        );
        // The connection's own form, the lens's: after a failed read the
        // address or the key is the likeliest thing to have changed.
        void openForm() => onOpenSettings != null
            ? onOpenSettings!()
            : FailureRemedy.openConnectionForm(context, service);
        return _OfflineLeaf(
          icon: presentation.icon,
          // Red for silence, amber for a fault; walked, never raw.
          glyphColor: statusToneColor(
            Theme.of(context).colorScheme,
            presentation.tone,
          ),
          // What happened, naming who: `Radarr did not answer`, `Radarr
          // answered but refused the key`.
          title: presentation.headline,
          address: host == null || host.isEmpty ? null : host,
          body: [
            if (silent && span != null) 'It has not answered for $span.',
            message,
          ].join(' '),
          // The remedy leads when the fix lives in the form (`Paste the key
          // again`), with Retry after it only where retrying can still help.
          // Otherwise Retry leads and the plain way in follows.
          primary: remedy == null
              ? _LeafAction.retry(onRetry)
              : _LeafAction(remedy.label, openForm),
          fault: !silent,
          secondary: remedy == null
              ? _LeafAction('Settings', openForm)
              : remedy.retryHelps
              ? _LeafAction(Lexicon.retry, onRetry)
              : null,
        );
      },
    );
  }
}

/// One of the leaf's two actions.
class _LeafAction {
  const _LeafAction(this.label, this.onPressed) : isRetry = false;

  const _LeafAction.retry(this.onPressed)
    : label = Lexicon.retry,
      isRetry = true;

  final String label;
  final VoidCallback onPressed;

  /// Retry as the first action carries its glyph; a remedy is its verb alone.
  final bool isRetry;
}

class _OfflineLeaf extends StatelessWidget {
  const _OfflineLeaf({
    required this.icon,
    required this.glyphColor,
    required this.title,
    required this.body,
    required this.primary,
    required this.fault,
    this.secondary,
    this.address,
  });

  final IconData icon;
  final Color glyphColor;
  final String title;

  /// Which server this is about, when a connection names one.
  final String? address;
  final String body;

  /// The filled button: Retry, or the remedy when the form holds the fix.
  final _LeafAction primary;

  /// The text action after it: `Settings`, or Retry beside a remedy.
  final _LeafAction? secondary;

  /// Whether this is a fault (amber) rather than silence (red), which decides
  /// whether the first action is the amber fill or a ghost.
  final bool fault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: [title, ?address, body].join('. '),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No fill behind it. Presence is the signal, and a page that has
              // already emptied itself does not need a second announcement in
              // a tinted circle — the glyph alone carries the tone, measured
              // against the ground it sits on.
              ExcludeSemantics(child: Icon(icon, size: 32, color: glyphColor)),
              const SizedBox(height: AppSpacing.lg),
              ExcludeSemantics(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              if (address != null) ...[
                const SizedBox(height: AppSpacing.xs),
                ExcludeSemantics(
                  child: Text(
                    address!,
                    style: AppTheme.chrome(
                      context,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
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
              // A wrap rather than a row: `Check the certificate` beside Retry
              // does not fit a narrow pane on one line.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // The remedy of a fault, the form's fix or Retry when retrying
                  // is the fix, is the fault's one amber fill. Retry beside
                  // silence is a ghost in ink: never filled, never red.
                  if (primary.isRetry && !fault)
                    OutlinedButton.icon(
                      onPressed: primary.onPressed,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(primary.label),
                    )
                  else if (primary.isRetry)
                    FilledButton.icon(
                      onPressed: primary.onPressed,
                      style: remedyFillStyle(context),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(primary.label),
                    )
                  else
                    FilledButton(
                      onPressed: primary.onPressed,
                      style: remedyFillStyle(context),
                      child: Text(primary.label),
                    ),
                  if (secondary case final secondary?)
                    // A text action, not a second filled button: there is one
                    // thing to try first and one thing to try if it fails, and
                    // two equal buttons would not say which.
                    TextButton(
                      onPressed: secondary.onPressed,
                      style: TextButton.styleFrom(
                        // Never the error tone: painting the recovery in the
                        // fault's own colour makes the cure look like the
                        // disease.
                        foregroundColor: colorScheme.primary,
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(56, 44),
                      ),
                      child: Text(secondary.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
