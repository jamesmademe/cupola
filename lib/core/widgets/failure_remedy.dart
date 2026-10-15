import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The fix a failure names, and the way to it.
///
/// [failureRemedy] says *what* fixes a fault: `Paste the key again`, `Change
/// the address`, `Check the certificate`. This turns it into the control that
/// applies it, so every failure state offers the same remedy for the same
/// cause without a screen wiring one: the words, the connection form that
/// holds the fix, and whether `Retry` still belongs beside it ([retryHelps]).
///
/// There is none ([FailureRemedy.of] returns null) when `Retry` is the remedy
/// (nothing answered, a 5xx, a timeout) and when no service is known: a state
/// that cannot say whose form to open keeps `Retry` and offers no door it
/// cannot open.
@immutable
class FailureRemedy {
  const FailureRemedy._(
    this.service,
    this.reason,
    this.label, {
    this.instanceId,
    this.gateway,
  });

  /// The remedy for [error] on [service], or null. See the class comment.
  ///
  /// [instanceId] names the connection the failed read went to, when the
  /// caller knows it; without one the remedy opens the lens's.
  static FailureRemedy? of(
    ServiceKey? service,
    Object? error, {
    String? instanceId,
  }) => service == null
      ? null
      : forReason(
          service,
          classifyConnectionFailure(error),
          instanceId: instanceId,
          gateway: accessGatewayOf(error),
        );

  /// The remedy for a failure already classified as [reason], or null when
  /// `Retry` is the remedy. [gateway] names what answered in front of the
  /// service, for an [ServiceFailureReason.accessGateway].
  static FailureRemedy? forReason(
    ServiceKey service,
    ServiceFailureReason reason, {
    String? instanceId,
    AccessGatewayAnswer? gateway,
  }) {
    final label = describeFailure(service, reason, gateway: gateway).remedy;
    return label == null
        ? null
        : FailureRemedy._(
            service,
            reason,
            label,
            instanceId: instanceId,
            gateway: gateway,
          );
  }

  /// The service [text] starts by naming, or null.
  ///
  /// A failure state that was handed words rather than a service still knows
  /// whose failure it is, because the classification's words start with the
  /// subject: a display name (`Radarr`, `Seerr issues`, `Radarr 4K`) or a
  /// section's sentence (`Unraid answered but refused the key, so its shares
  /// are not shown.`). No title is the start of another, so the first match is
  /// the only one; words that name no service, or several (`Radarr, Sonarr`),
  /// name none.
  static ServiceKey? serviceNamedBy(String? text) {
    final words = text?.trim();
    if (words == null || words.isEmpty) return null;
    for (final service in ServiceKey.values) {
      if (words == service.title || words.startsWith('${service.title} ')) {
        return service;
      }
    }
    return null;
  }

  /// Opens [service]'s connection form: the one the lens rests on, so a key
  /// refused by a second Radarr is pasted into the second Radarr's form, which
  /// is the connection a page reads unless its link named another.
  ///
  /// [access] opens it on the Access row with that choice made.
  static void openConnectionForm(
    BuildContext context,
    ServiceKey service, {
    AccessKind? access,
    bool away = false,
  }) {
    final lens = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(activeInstanceProvider(service))?.id;
    context.push(
      ServiceRoutes.settingsForConnection(
        service,
        lens ?? '',
        access: access,
        away: away,
      ),
    );
  }

  final ServiceKey service;
  final ServiceFailureReason reason;

  /// The connection whose form holds the fix, or null for the lens's.
  final String? instanceId;

  /// What answered in front of the service, when that is the fault: which
  /// gateway, and whether it was sent the access it asks for. [open] lands on
  /// the connection form's Access row with the choice this gateway wants
  /// ([access]).
  final AccessGatewayAnswer? gateway;

  /// The Access choice the form opens on, for a gateway in front of the
  /// service: Cloudflare Access for Access, Password for a password prompt or
  /// a sign-in page. Null for every other fault, whose fix is elsewhere in
  /// the form.
  AccessKind? get access => reason == ServiceFailureReason.accessGateway
      ? accessKindForGateway(service, gateway)
      : null;

  /// The remedy's verb, which is the action's label: `Paste the key again`.
  final String label;

  /// Whether `Retry` stays beside the remedy as the second action. It does not
  /// for a refused key or an address the device will not dial
  /// ([failureRetryHelps]): the same request can only be refused again.
  bool get retryHelps =>
      failureRetryHelps(reason, credential: refusedCredentialOf(service));

  /// Whether this fixes a **fault** ([failureIsFault]), and so wears the
  /// fault's amber fill. Signing in again after a Seerr session ended is the
  /// person's own step, blue: its remedy is the ink fill.
  bool get isFault => failureIsFault(reason);

  /// Applies the remedy: opens the connection form where the fix lives, the
  /// named connection's when there is one and the lens's otherwise, on its
  /// Access row for a gateway and on its empty address away for a
  /// connection only at home.
  void open(BuildContext context) {
    final named = instanceId;
    final away = reason == ServiceFailureReason.onlyAtHome;
    if (named == null || named.isEmpty) {
      openConnectionForm(context, service, access: access, away: away);
    } else {
      context.push(
        ServiceRoutes.settingsForConnection(
          service,
          named,
          access: access,
          away: away,
        ),
      );
    }
  }
}

/// The one fill a fault gets: the remedy of an **amber** fault, in
/// `tone.amber-fill` under `tone.amber-ink` (the brand book's Presence Rule).
///
/// The remedy is the form's fix when there is one (`Paste the key again`) and
/// Retry when retrying is the fix (a 5xx, a timeout). Nothing else wears it:
/// Retry beside a red line is a ghost in ink, the other verbs stay text in
/// ink, and the ink button is for ordinary primaries. The ink is the token
/// drawn for this fill, so it does not need measuring at runtime;
/// `failure_remedy_test.dart` measures it in both rooms.
///
/// [compact] is the line's control (`InlineErrorRetry`, `FaultBand`): the
/// same 44pt floor with the line's narrower padding, so it sits in a row of
/// body text without crowding it.
///
/// [fault] false is the remedy of a step that is not a fault (a Seerr session
/// that ended, blue): the same control in the ink of an ordinary primary,
/// because an amber fill beside a blue glyph says something is broken.
ButtonStyle remedyFillStyle(
  BuildContext context, {
  bool compact = false,
  bool fault = true,
}) {
  final room = CupolaRoom.of(context);
  return FilledButton.styleFrom(
    backgroundColor: fault ? room.toneAmberFill : null,
    foregroundColor: fault ? room.toneAmberInk : null,
    // Pinned: the desktop's compact density silently takes 8 off
    // `minimumSize`, and 44 declared measured 40.
    visualDensity: VisualDensity.standard,
    minimumSize: Size(compact ? 56 : 64, DesignTokens.sizeButtonM),
    padding: compact
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.md)
        : null,
  );
}

/// The verbs a failure **line** offers, in order: the remedy in the amber fill
/// ([remedyFillStyle]) with `Retry` after it, text in ink, only where the same
/// request can still succeed ([FailureRemedy.retryHelps]); with no remedy,
/// `Retry` alone, in the amber fill for a fault ([fault]) because retrying is
/// then the fix, and text in ink beside silence, never filled and never red.
///
/// The one policy [InlineErrorRetry] and the search lane's fault card both
/// draw, so a line cannot offer a Retry the cause rules out, or leave out the
/// remedy it names. Every verb keeps its 44pt target at standard density.
///
/// [subject] names the server the verbs act on, for a screen with several of
/// these lines (`Retry Radarr`, `Add a service token for Radarr`): heard
/// seven times, a bare `Retry` cannot say which server it will ask again.
List<Widget> failureLineVerbs(
  BuildContext context, {
  required FailureRemedy? remedy,
  required bool fault,
  required VoidCallback onRetry,
  String? subject,
}) {
  final retry = Text(
    Lexicon.retry,
    semanticsLabel: subject == null ? null : '${Lexicon.retry} $subject',
  );
  final remedyLabel = remedy == null
      ? null
      : Text(
          remedy.label,
          semanticsLabel: subject == null
              ? null
              : '${remedy.label} for $subject',
        );
  return [
    // Away from home, a connection only at home is a setup, not a fault: its
    // remedy (`Add an address away`) is text in ink, never a fill.
    if (remedy != null && remedy.reason == ServiceFailureReason.onlyAtHome)
      TextButton(
        onPressed: () => remedy.open(context),
        style: retryInkStyle(Theme.of(context).colorScheme),
        child: remedyLabel!,
      )
    else if (remedy != null)
      FilledButton(
        onPressed: () => remedy.open(context),
        style: remedyFillStyle(context, compact: true, fault: remedy.isFault),
        child: remedyLabel!,
      ),
    if (remedy == null && fault)
      FilledButton(
        onPressed: onRetry,
        style: remedyFillStyle(context, compact: true),
        child: retry,
      )
    else if (remedy == null || remedy.retryHelps)
      TextButton(
        onPressed: onRetry,
        style: retryInkStyle(Theme.of(context).colorScheme),
        child: retry,
      ),
  ];
}

/// `Retry` as text in ink on a failure line: the primary ink, never a tone.
ButtonStyle retryInkStyle(ColorScheme colorScheme) => TextButton.styleFrom(
  // Brand primary, never the error tone: a red cure looks like the disease.
  foregroundColor: colorScheme.primary,
  // 44pt on iOS / 48dp on Android is the floor, and this button shares its
  // row with body text that would otherwise size it. Standard density,
  // pinned: compact silently takes 8 off `minimumSize`, and 44 declared
  // measured 40.
  visualDensity: VisualDensity.standard,
  minimumSize: const Size(56, 44),
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
);
