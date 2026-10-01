import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';

/// One grammar for the four ways a page can be wrong, none of which is an
/// error page.
///
/// A self-hosted stack fails in levels, and the app used to have a vocabulary
/// for exactly none of them: a service that did not answer, a sub-source inside
/// a service that did not answer, a poll that stopped coming back, and a page
/// that was already open when its service died all landed on the same red
/// full-page leaf — or on nothing at all. The leaf is the expensive mistake,
/// because it throws away the last readout the operator opened the app to see.
/// A box that has been dark for six minutes is *precisely* when the numbers it
/// reported seven minutes ago are worth reading.
///
/// So all four are a band above content that stays, and they differ only in
/// what the sentence says and which tone the glyph carries:
///
///  * [FaultBand.unreachable] — the service did not answer at all. Identity,
///    tabs and every readout below stay at full ink; the band names the age.
///  * [FaultBand.section] — the service answered, one source inside it did not.
///    Only that section falls back, and a figure that source owns reads `—`,
///    never `0`.
///  * [FaultBand.partial] — the service answered part of a read and not the
///    rest. Amber: something that just replied did not fail to answer.
///  * [FaultBand.stale] — nothing is broken, the poll stopped coming back.
///    **Warning**, not error, and no dismiss: it is a condition of the data,
///    not an event, and it is still true after you acknowledge it.
///  * [FaultBand.offlinePush] — a pushed page whose service died under it keeps
///    its last render. Only a region that is live *by definition* — an
///    interactive release search, whose results act on a grab — says so.
///
/// ## The three rules, which are the whole widget
///
/// 1. **Presence is the signal.** No fill, no border, the tone spent on exactly
///    one 16pt glyph and nowhere else. The band appearing at all is the alarm;
///    a page that shouts every time a home server is rebuilding is a page whose
///    shouting stops being read.
/// 2. **The recovery verb is never painted red.** Beside silence Retry,
///    Refresh and Settings are the primary ink: a red Retry makes the cure look
///    like the disease, and there is no reading of "try again" that is itself
///    alarming. An amber fault's remedy is the one fill a fault gets, the
///    compact amber fill ([remedyFillStyle]); every other verb stays ink.
/// 3. **Nothing is dimmed for being unreachable.** Dimming means *not
///    configured* everywhere else on this canvas, and the two states need
///    opposite responses — one is "go set this up", the other is "this is what
///    it said last". Draining the readout to 38% would answer the wrong one.
///
/// The band is a *line*, not a card, for the same reason [InlineErrorRetry] is:
/// a stack where something is down most Tuesdays cannot afford alarm chrome on
/// most Tuesdays.
class FaultBand extends StatelessWidget {
  /// Level 1 — the service did not answer at all.
  ///
  /// [since] is when it was last seen answering; it turns the sentence from a
  /// fact into a measurement ("has not answered for 6 minutes"), which is what
  /// tells the operator whether this is a restart or an outage. Under a minute,
  /// or absent entirely, the sentence drops the span rather than printing a
  /// number nobody can act on.
  ///
  /// [onOpenSettings] is the second half of "the action is the fix": Retry
  /// re-probes, and when the *address* is what changed no number of retries
  /// helps.
  FaultBand.unreachable({
    super.key,
    required String serviceName,
    Duration? since,
    required VoidCallback onRetry,
    VoidCallback? onOpenSettings,
  }) : tone = StatusTone.error,
       icon = Icons.cloud_off_rounded,
       message = _unreachableMessage(serviceName, since),
       primaryAction = FaultBandAction('Retry', onRetry),
       secondaryAction = onOpenSettings == null
           ? null
           : FaultBandAction('Settings', onOpenSettings);

  /// Level 1, when the service **answered**: the read failed with a refusal
  /// or a fault — a refused key, a 5xx, a reply nobody can read.
  ///
  /// Amber, never [FaultBand.unreachable]'s red: the service is there, and
  /// telling the user it did not answer sends them to check a box that just
  /// replied. [reason] is the classification; the sentence names who and
  /// what, in the service's own word for what it refused (`key`, `sign-in`,
  /// `token`), and the readout below stays at full ink for the same reason it
  /// does under silence.
  ///
  /// **The remedy leads.** When the classification names a fix in the
  /// connection's form (`Paste the key again`, `Sign in again`, `Check the
  /// address`) it is the first verb, in the amber fill, and opens
  /// [onOpenSettings] or, without one, the form of the connection the lens
  /// rests on ([FailureRemedy]) for the service [serviceName] starts by
  /// naming. Retry follows only where the same request can still succeed
  /// ([failureRetryHelps]). With no such fix Retry is the remedy, in the
  /// amber fill, and `Settings` follows when there is a way in.
  ///
  /// [gateway] names what answered in front of the service when that is the
  /// fault ([ServiceFailureReason.accessGateway]): `Cloudflare Access answered
  /// instead of Radarr` · *Add a service token*.
  factory FaultBand.fault({
    Key? key,
    required String serviceName,
    required ServiceFailureReason reason,
    required VoidCallback onRetry,
    VoidCallback? onOpenSettings,
    AccessGatewayAnswer? gateway,
  }) {
    final service = FailureRemedy.serviceNamedBy(serviceName);
    final credential = service == null
        ? kRefusedCredential
        : refusedCredentialOf(service);
    final remedy = failureRemedy(
      reason,
      credential: credential,
      gateway: gateway,
    );
    final formRemedy = service == null
        ? null
        : FailureRemedy.forReason(service, reason, gateway: gateway);
    final FaultBandAction? fix = remedy == null
        ? null
        : onOpenSettings != null
        ? FaultBandAction.remedy(remedy, onOpenSettings)
        : formRemedy == null
        ? null
        : FaultBandAction._form(formRemedy);
    return FaultBand._raw(
      key: key,
      tone: failureTone(reason),
      icon: failureIcon(reason),
      message:
          '${failureHeadline(reason, subject: serviceName, credential: credential, gateway: gateway)}. '
          'Everything below is what it said last.',
      primaryAction: fix ?? FaultBandAction.remedy('Retry', onRetry),
      secondaryAction: fix != null
          ? (failureRetryHelps(reason, credential: credential)
                ? FaultBandAction('Retry', onRetry)
                : null)
          : onOpenSettings == null
          ? null
          : FaultBandAction('Settings', onOpenSettings),
    );
  }

  const FaultBand._raw({
    super.key,
    required this.tone,
    required this.icon,
    required this.message,
    required this.primaryAction,
    this.secondaryAction,
  });

  /// Level 2 — the service answered; one source inside it did not.
  ///
  /// The sentence is the caller's because only the caller knows the
  /// relationship: *"Radarr is answering. qBittorrent, the download client it
  /// hands grabs to, is not — so the queue is missing from this page."* names
  /// which figures are absent and why, which a generic string cannot. Pair it
  /// with `ServiceKpi.unavailable` so the figures that source owns read `—`.
  FaultBand.section({
    super.key,
    required this.message,
    required VoidCallback onRetry,
    VoidCallback? onOpenSettings,
  }) : tone = StatusTone.error,
       icon = Icons.link_off_rounded,
       primaryAction = FaultBandAction('Retry', onRetry),
       secondaryAction = onOpenSettings == null
           ? null
           : FaultBandAction('Settings', onOpenSettings);

  /// Level 2, when the service answered **part** of a read: the first pages
  /// of a paged list came back and a later one did not, or one of several
  /// sources a list merges failed while the rest answered.
  ///
  /// Amber, never [FaultBand.section]'s red: the service is there — it just
  /// answered — so "did not answer" would be a claim about a host that
  /// replied. The sentence is the caller's, because only the caller knows how
  /// much arrived: *"Seerr returned 50 of 300 users; later pages are
  /// unavailable."* Pair it with a count that names what is shown ("50 shown")
  /// rather than a total.
  FaultBand.partial({
    super.key,
    required this.message,
    required VoidCallback onRetry,
  }) : tone = StatusTone.warning,
       icon = Icons.playlist_remove_rounded,
       // Asking for the rest again is this fault's remedy: the amber fill.
       primaryAction = FaultBandAction.remedy('Retry', onRetry),
       secondaryAction = null;

  /// Level 3 — the poll stopped coming back.
  ///
  /// Warning, not error: nothing is unreachable and nothing failed, the figures
  /// are simply older than they should be. And **no dismiss** — a stale reading
  /// is a property of the data, still true the instant after it is
  /// acknowledged, so a dismiss would only teach the user to hide it.
  ///
  /// Rows under this band trade their time-left for the sample's age: a
  /// progress bar that is not advancing must not look live.
  FaultBand.stale({
    super.key,
    required Duration age,
    required String detail,
    required VoidCallback onRefresh,
  }) : tone = StatusTone.warning,
       icon = Icons.history_toggle_off_rounded,
       message = _staleMessage(age, detail),
       primaryAction = FaultBandAction('Refresh', onRefresh),
       secondaryAction = null;

  /// Level 4 — the page loaded, then the service died under it.
  ///
  /// The render stays: it is the last true thing the app knows. Only a region
  /// that is live by definition falls back, and the caller decides which —
  /// an interactive release list four minutes old is not a release list any
  /// more, because Grab would act on it.
  ///
  /// [onOpen] is the jump into the service's own page, labelled with its name.
  FaultBand.offlinePush({
    super.key,
    required String serviceName,
    required VoidCallback onRetry,
    VoidCallback? onOpen,
  }) : tone = StatusTone.error,
       icon = Icons.cloud_off_rounded,
       message =
           '$serviceName stopped answering while this page was open. '
           'Everything here is the last render; a write will fail until it '
           'is back.',
       primaryAction = FaultBandAction('Retry', onRetry),
       secondaryAction = onOpen == null
           ? null
           : FaultBandAction('Open $serviceName', onOpen);

  /// Which tone the single glyph carries. Never reaches anything else.
  @visibleForTesting
  final StatusTone tone;

  final IconData icon;

  /// The sentence, and the accessible label for the whole band.
  final String message;

  /// The recovery verb. Always present — a band with nothing to do about it is
  /// a band that should not be on the screen.
  final FaultBandAction primaryAction;

  /// The second half of "the action is the fix", where there is one: Settings
  /// when the address may be what changed, the service's own page when the
  /// answer is to go look at it. `null` on [FaultBand.stale], which has exactly
  /// one thing to offer and no dismiss.
  final FaultBandAction? secondaryAction;

  static String _unreachableMessage(String serviceName, Duration? since) {
    final span = since == null ? null : formatElapsedSpan(since);
    if (span == null) {
      return '$serviceName did not answer. Everything below is what it '
          'said last.';
    }
    return '$serviceName has not answered for $span. Everything below is '
        'what it said last.';
  }

  static String _staleMessage(Duration age, String detail) {
    final spoken = formatDurationAge(age);
    // "These figures are just now" is not a sentence; under a minute the band
    // has nothing worth saying and the caller should not be showing it, but a
    // clock that ticks backwards across a poll must not produce one either.
    final lead = spoken == 'just now'
        ? 'These figures have stopped updating.'
        : 'These figures are $spoken.';
    return '$lead $detail';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Rule 1: the tone lands here and nowhere else. Walked against the ground
    // it is drawn on, because raw error measures about 3.4:1 on the light
    // scaffold and raw warning about 1.4:1 — and with no fill behind it this
    // glyph is the entire signal.
    final alarm = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surface,
    );

    final actions = <FaultBandAction>[primaryAction, ?secondaryAction];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Semantics(
        container: true,
        // Each action stays its own reachable control; this node owns the
        // sentence, so the band reads as one statement followed by its verbs
        // rather than as three unrelated fragments.
        explicitChildNodes: true,
        // Announced when it appears, which is the moment it matters. Not routed
        // through `announce()` as well: that would read it twice.
        liveRegion: true,
        label: message,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 16, color: alarm)),
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
            for (final action in actions)
              if (action.fill)
                // Rule 2: an amber fault's remedy, the one fill it gets.
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: FilledButton(
                    onPressed: () => action._press(context),
                    style: remedyFillStyle(context, compact: true),
                    child: Text(action.label),
                  ),
                )
              else
                TextButton(
                  onPressed: () => action._press(context),
                  style: TextButton.styleFrom(
                    // Rule 2.
                    foregroundColor: colorScheme.primary,
                    // 44pt on iOS / 48dp on Android is the floor, and these
                    // buttons share a row with body text that would otherwise
                    // size them. Standard density, pinned: compact silently
                    // takes 8 off `minimumSize`, and 44 declared measured 40.
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(56, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  child: Text(action.label),
                ),
          ],
        ),
      ),
    );
  }
}

/// A verb and what it does.
///
/// A label and a callback rather than a `Widget`: the band owns rule 2 — the
/// recovery verb is never painted red, and only an amber fault's remedy is
/// filled — and a caller that could hand in its own styled button would be
/// able to break it from outside.
@immutable
class FaultBandAction {
  /// A verb in ink.
  const FaultBandAction(this.label, VoidCallback this.onPressed)
    : fill = false,
      _remedy = null;

  /// An amber fault's remedy, which the band draws in the amber fill.
  const FaultBandAction.remedy(this.label, VoidCallback this.onPressed)
    : fill = true,
      _remedy = null;

  /// The form's fix, which the band opens itself when the caller gave it no
  /// way in of its own.
  FaultBandAction._form(FailureRemedy remedy)
    : label = remedy.label,
      onPressed = null,
      fill = true,
      _remedy = remedy;

  final String label;

  /// What the verb does. Null only for a form remedy the band opens itself.
  final VoidCallback? onPressed;

  /// Whether this is an amber fault's remedy, drawn in the amber fill.
  final bool fill;

  final FailureRemedy? _remedy;

  void _press(BuildContext context) {
    final press = onPressed;
    if (press != null) {
      press();
    } else {
      _remedy!.open(context);
    }
  }
}
