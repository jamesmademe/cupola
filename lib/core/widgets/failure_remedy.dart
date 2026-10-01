import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
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
  const FailureRemedy._(this.service, this.reason, this.label);

  /// The remedy for [error] on [service], or null. See the class comment.
  static FailureRemedy? of(ServiceKey? service, Object? error) =>
      service == null
      ? null
      : forReason(service, classifyConnectionFailure(error));

  /// The remedy for a failure already classified as [reason], or null when
  /// `Retry` is the remedy.
  static FailureRemedy? forReason(
    ServiceKey service,
    ServiceFailureReason reason,
  ) {
    final label = describeFailure(service, reason).remedy;
    return label == null ? null : FailureRemedy._(service, reason, label);
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
  static void openConnectionForm(BuildContext context, ServiceKey service) {
    final lens = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(activeInstanceProvider(service))?.id;
    context.push(
      lens == null || lens.isEmpty
          ? ServiceRoutes.settingsFor(service)
          : ServiceRoutes.settingsForConnection(service, lens),
    );
  }

  final ServiceKey service;
  final ServiceFailureReason reason;

  /// The remedy's verb, which is the action's label: `Paste the key again`.
  final String label;

  /// Whether `Retry` stays beside the remedy as the second action. It does not
  /// for a refused key or an address the device will not dial
  /// ([failureRetryHelps]): the same request can only be refused again.
  bool get retryHelps =>
      failureRetryHelps(reason, credential: refusedCredentialOf(service));

  /// Applies the remedy: opens the connection form where the fix lives.
  void open(BuildContext context) => openConnectionForm(context, service);
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
ButtonStyle remedyFillStyle(BuildContext context, {bool compact = false}) {
  final room = CupolaRoom.of(context);
  return FilledButton.styleFrom(
    backgroundColor: room.toneAmberFill,
    foregroundColor: room.toneAmberInk,
    // Pinned: the desktop's compact density silently takes 8 off
    // `minimumSize`, and 44 declared measured 40.
    visualDensity: VisualDensity.standard,
    minimumSize: Size(compact ? 56 : 64, DesignTokens.sizeButtonM),
    padding: compact
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.md)
        : null,
  );
}
