import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';

/// Runs a TrueNAS mutation with the shared plumbing: await [action],
/// invalidate the [invalidate] providers on success, and report the outcome
/// via `SnackBarHelper`.
///
/// A thin alias over [runServiceAction], which the whole app shares; kept as a
/// named entry point because every TrueNAS action flow reads through it.
Future<bool> runTrueNasAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) {
  return runServiceAction(
    context,
    ref,
    action: action,
    successMessage: successMessage,
    failureMessage: failureMessage,
    invalidate: invalidate,
  );
}

/// Fires a TrueNAS call whose reply can never arrive, and reports it in the
/// present tense.
///
/// [runTrueNasAction] awaits the call before it says anything, which is right
/// for every write in the app except two. `system.shutdown` and `system.reboot`
/// are executed by tearing down the middleware that would have answered them:
/// the socket dies mid-call, so the awaited future resolves — if it resolves at
/// all — to a connection error. On that path the *only* reachable outcome is
/// the red "could not shut down" snack, printed while the NAS is shutting down
/// perfectly well.
///
/// So this one does not await. It fires, drops the future (with a catch, or a
/// dead socket would raise an unhandled async error in the zone), and reports
/// immediately — in the present tense, because "shutting down" is the only
/// thing anyone here can honestly claim. Nothing invalidates: every provider
/// behind this screen is about to be unreachable, and re-fetching them would
/// only race the shutdown to an error card.
void runTrueNasDetachedAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String message,
}) {
  unawaited(
    action().catchError((Object _) {
      // Deliberately silent. A failure here is indistinguishable from success:
      // both look like a socket that stopped answering.
    }),
  );
  SnackBarHelper.info(context, message);
}
