import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// Runs a [TransmissionClient] mutation with the shared plumbing: resolve the
/// client, await [action], invalidate [invalidate] providers and report the
/// outcome. Returns whether the mutation was accepted.
///
/// Simpler than its NZBGet counterpart, and for a reason worth recording:
/// NZBGet signals a refused command by answering HTTP 200 with `{"result":
/// false}`, so its wrapper has to inspect the return value. Transmission never
/// does that. A refusal comes back as a `result` string that is not
/// `"success"`, and [TransmissionClient] has already turned that into a thrown
/// [TransmissionException] carrying the server's own words. So "did it work" is
/// exactly "did it throw", and there is no `_isRejection` equivalent to get
/// wrong.
///
/// The flip side, and the reason [invalidate] is not optional in practice:
/// Transmission's write methods return an empty `arguments` with no per-id
/// outcome and no echo of what was applied. Re-reading is the only way to know
/// what actually happened, so every caller passes the providers that answer
/// that question.
///
/// Transmission keeps its Basic credentials in the `Authorization` header and
/// never in the URL, and [TransmissionException.message] is always either a
/// static sentence or the server's own error string, so the `$e` interpolated
/// below cannot carry the password.
Future<bool> runTransmissionAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(TransmissionClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(transmissionClientProvider);
  try {
    await action(client);
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (successMessage != null && context.mounted) {
      SnackBarHelper.success(context, successMessage);
    }
    return true;
  } catch (e) {
    // Refreshed on failure too: a rejected command usually means the queue
    // moved under us, and re-reading is what shows the user what is there now.
    for (final provider in invalidate) {
      ref.invalidate(provider);
    }
    if (context.mounted) {
      SnackBarHelper.error(context, failureMessage, detail: e);
    }
    return false;
  }
}

/// What an attempt to add a torrent came to.
enum TransmissionAddVerdict {
  /// `torrent-added`.
  added,

  /// `torrent-duplicate`: `result` said `"success"`, and nothing was added.
  duplicate,

  /// The daemon read the request and refused it, in its own words.
  refused,

  /// The request never reached the RPC handler: no route, a TLS failure, the
  /// credentials or a whitelist turned it away, so nothing can have been
  /// added.
  notSent,

  /// The request may have arrived and no answer came back: a timeout, a 5xx,
  /// a reply this app could not read. The torrent may or may not be there.
  unconfirmed,
}

/// The sentence the Add torrent flow shows for a [TransmissionAddVerdict].
@immutable
class TransmissionAddReport {
  const TransmissionAddReport(this.verdict, this.message, {this.detail});

  /// Read from the add's outcome, or from what it threw.
  ///
  /// "Did it work" is not "did it throw" here, which is why this flow does not
  /// go through [runTransmissionAction]: a duplicate is a success on the wire
  /// and a failure to the user, and a timeout is a failure on the wire that may
  /// still have added the torrent. Each gets its own sentence, and none of them
  /// is "Torrent added".
  factory TransmissionAddReport.from({
    ({TransmissionTorrent? torrent, bool isDuplicate})? outcome,
    Object? error,
  }) {
    if (error == null && outcome != null) {
      return outcome.isDuplicate
          ? TransmissionAddReport(
              TransmissionAddVerdict.duplicate,
              'Already in Transmission',
              detail: outcome.torrent?.name,
            )
          : const TransmissionAddReport(
              TransmissionAddVerdict.added,
              'Torrent added',
            );
    }
    if (error is TransmissionException) {
      if (error.rejectedByDaemon) {
        return TransmissionAddReport(
          TransmissionAddVerdict.refused,
          'Transmission refused the torrent',
          detail: error.message,
        );
      }
      return switch (error.reason) {
        ServiceFailureReason.unreachable ||
        ServiceFailureReason.unreachableAtBoth ||
        ServiceFailureReason.tls ||
        ServiceFailureReason.localNetworkBlocked ||
        ServiceFailureReason.unauthorized ||
        // The password never left the device's storage.
        ServiceFailureReason.secretUnread ||
        // Seerr's own two: never Transmission's, refused before anything
        // reached the daemon if they ever were.
        ServiceFailureReason.sessionEnded ||
        ServiceFailureReason.csrfRefused ||
        // Away from the only network that reaches the daemon: never sent.
        ServiceFailureReason.onlyAtHome ||
        ServiceFailureReason.notFound ||
        ServiceFailureReason.redirected ||
        // The gateway answered in the daemon's place: nothing reached it.
        ServiceFailureReason.accessGateway ||
        ServiceFailureReason.insecureTransport => TransmissionAddReport(
          TransmissionAddVerdict.notSent,
          'The torrent was not added',
          detail: error.message,
        ),
        ServiceFailureReason.timeout ||
        ServiceFailureReason.serverError ||
        ServiceFailureReason.invalidResponse ||
        ServiceFailureReason.unknown => TransmissionAddReport(
          TransmissionAddVerdict.unconfirmed,
          _unconfirmed,
          detail: error.message,
        ),
      };
    }
    return TransmissionAddReport(
      TransmissionAddVerdict.unconfirmed,
      _unconfirmed,
      detail: error == null ? null : failureDiagnostic(error),
    );
  }

  static const _unconfirmed =
      'Transmission did not confirm the add. Check the queue before adding it '
      'again.';

  final TransmissionAddVerdict verdict;
  final String message;

  /// The daemon's words, the transport's, or the duplicate's name.
  final String? detail;
}

/// Hands [link] to the daemon and says what came of it; see
/// [TransmissionAddReport.from]. The queue is re-read whatever the outcome.
Future<TransmissionAddVerdict> runTransmissionAdd(
  BuildContext context,
  WidgetRef ref,
  String link, {
  List<ProviderOrFamily> invalidate = const [],
}) async {
  TransmissionAddReport report;
  try {
    final client = ref.read(transmissionClientProvider);
    try {
      report = TransmissionAddReport.from(
        outcome: await client.addTorrent(link),
      );
    } catch (e) {
      report = TransmissionAddReport.from(error: e);
    }
  } catch (e) {
    // No client, so no request left the device.
    report = TransmissionAddReport(
      TransmissionAddVerdict.notSent,
      'The torrent was not added',
      detail: 'Transmission is not set up here, so nothing was sent.',
    );
  }
  for (final provider in invalidate) {
    ref.invalidate(provider);
  }
  if (context.mounted) {
    switch (report.verdict) {
      case TransmissionAddVerdict.added:
        SnackBarHelper.success(context, report.message);
      case TransmissionAddVerdict.duplicate:
        SnackBarHelper.info(context, report.message, detail: report.detail);
      case TransmissionAddVerdict.refused ||
          TransmissionAddVerdict.notSent ||
          TransmissionAddVerdict.unconfirmed:
        SnackBarHelper.error(context, report.message, detail: report.detail);
    }
  }
  return report.verdict;
}
