import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';

/// Runs a [SabnzbdClient] mutation with the shared plumbing: resolve the client,
/// await [action], invalidate [invalidate] providers on success and report the
/// outcome via [SnackBarHelper].
///
/// [SabnzbdClient] always throws a [SabnzbdException] whose message has been run
/// through [redactSabnzbdSecrets], so interpolating the error below can never
/// leak the API key that SABnzbd carries in the request URL (security §10.2 #7).
Future<bool> runSabnzbdAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(SabnzbdClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) {
  final client = ref.read(sabnzbdClientProvider);
  return runServiceAction(
    context,
    ref,
    action: () => action(client),
    successMessage: successMessage,
    failureMessage: failureMessage,
    invalidate: invalidate,
    refreshOnFailure: true,
  );
}
