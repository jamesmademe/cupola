import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';

/// True when NZBGet answered the call but refused to do the work.
///
/// NZBGet does not signal a rejected command with a JSON-RPC `error` object:
/// it answers HTTP 200 with `{"result": false}` (`editqueue`) or `{"result":
/// 0}` (`append`). Pausing a group whose NZBID has just left the queue,
/// deleting an already-removed id, or appending a URL the server declines all
/// take that path, so the client's own return value is the only evidence a
/// mutation did not happen.
///
/// Anything else (including the `null` a `Future<void>` method resolves to)
/// counts as success, because a method that reports nothing has no failure to
/// report.
bool _isRejection(Object? result) {
  if (result is bool) return !result;
  // `append` documents 0 as its failure value; a real NZBID is always > 0.
  if (result is num) return result <= 0;
  return false;
}

/// NZBGet answered and refused: a failure with words and no transport fault
/// behind it, so the toast says what NZBGet did and not that it did not answer.
class _Rejected implements Exception {
  const _Rejected();

  @override
  String toString() => 'NZBGet rejected the request.';
}

/// Runs a [NzbgetClient] mutation with the shared plumbing: resolve the client,
/// await [action], invalidate [invalidate] providers and report the outcome via
/// [SnackBarHelper]. Returns whether the mutation actually took effect.
///
/// [action] returns `Future<Object?>` rather than `Future<void>` on purpose.
/// `void` is a top type in Dart, so the old signature silently accepted
/// `Future<bool>` and `Future<int>` and then discarded their results: this
/// wrapper returned `true` unconditionally and the UI reported "Job paused"
/// for calls NZBGet had refused. Widening the return type is what lets
/// [_isRejection] see the answer at all; a genuinely `void` client method still
/// satisfies it and resolves to `null`.
///
/// NZBGet keeps its Basic-auth credentials in the `Authorization` header, never
/// in the URL, so the [NzbgetException] surfaced below carries no secret.
Future<bool> runNzbgetAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<Object?> Function(NzbgetClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) {
  final client = ref.read(nzbgetClientProvider);
  return runServiceAction(
    context,
    ref,
    action: () async {
      // A refused command is a failure like any other: the same words, a
      // re-read of what the queue now holds, and a Retry.
      if (_isRejection(await action(client))) {
        throw const _Rejected();
      }
    },
    successMessage: successMessage,
    failureMessage: failureMessage,
    invalidate: invalidate,
    refreshOnFailure: true,
  );
}
