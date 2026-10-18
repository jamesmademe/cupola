import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Runs a mutating service call with the shared plumbing every write action in
/// the app needs: await [action], invalidate the [invalidate] providers on
/// success, and report the outcome via [SnackBarHelper].
///
/// Shows [successMessage] on success (when non-null) and the error-styled
/// `"$failureMessage: <error>"` on failure. Returns `true` when the action
/// completed without throwing, so callers can chain follow-up work (popping a
/// detail screen after a delete) only on success.
///
/// A failure that the same request can get past carries `Retry`, which runs
/// [action] again with the same follow-up: not a refusal of the request as
/// made (a 4xx other than a timeout or too many requests), which the service
/// would answer the same way. The outcome is said even when the page that
/// asked has gone: the app's own navigator says it instead, and `Retry` runs
/// from there. That is why the follow-up goes through the provider container
/// [context] reads rather than through [ref], which dies with its widget.
///
/// With a [capability], a permission refusal is not reported as a failure: it
/// marks that connection read-only and raises the refusal toast instead; see
/// [reportCapabilityRefusal].
Future<bool> runServiceAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function() action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
  CapabilityTarget? capability,
}) => _run(
  context,
  ProviderScope.containerOf(context, listen: false),
  action: action,
  successMessage: successMessage,
  failureMessage: failureMessage,
  invalidate: invalidate,
  capability: capability,
);

Future<bool> _run(
  BuildContext context,
  ProviderContainer container, {
  required Future<void> Function() action,
  required String? successMessage,
  required String failureMessage,
  required List<ProviderOrFamily> invalidate,
  required CapabilityTarget? capability,
}) async {
  // The app's own navigator outlives every page: where the outcome is said
  // once the page that asked has gone, and where a Retry runs from.
  final host = Navigator.maybeOf(context, rootNavigator: true)?.context;
  void say(void Function(BuildContext at) show) {
    if (context.mounted) {
      show(context);
    } else if (host != null && host.mounted) {
      show(host);
    }
  }

  try {
    await action();
    for (final provider in invalidate) {
      container.invalidate(provider);
    }
    if (successMessage != null) {
      say((at) => SnackBarHelper.success(at, successMessage));
    }
    return true;
  } catch (e) {
    if (capability != null && isPermissionRefusal(e)) {
      container
          .read(capabilityScopeProvider.notifier)
          .markReadOnly(capability.connectionId);
      say((at) => showCapabilityRefusal(at, capability));
      return false;
    }
    say(
      (at) => SnackBarHelper.error(
        at,
        failureMessage,
        detail: e,
        onRetry: host == null || _refusedAsMade(e)
            ? null
            : () => _run(
                host,
                container,
                action: action,
                successMessage: successMessage,
                failureMessage: failureMessage,
                invalidate: invalidate,
                capability: capability,
              ),
      ),
    );
    return false;
  }
}

/// Whether the service turned down this request as it was made: a 4xx other
/// than a timeout (408) or too many requests (429), both of which pass.
/// Sending it again gets the same answer.
bool _refusedAsMade(Object error) => switch (error) {
  DioException(response: Response(:final statusCode?)) =>
    statusCode >= 400 &&
        statusCode < 500 &&
        statusCode != 408 &&
        statusCode != 429,
  _ => false,
};

/// Handles [error] if it is a permission refusal: marks the connection in
/// [capability] read-only and raises the refusal toast, whose one action is
/// that connection's settings form. Returns whether it handled [error], so a
/// hand-written `catch` skips its own generic toast.
///
/// Not a failure toast, and not red: nothing broke. The service answered the
/// question the probe asked: this credential may read and not change this:
/// and from here on every write for the connection draws dimmed and the page
/// banner says why.
///
/// Call it only with a mounted [context]; after an `await`, check
/// `context.mounted` first, or use [markCapabilityRefusal] alone.
bool reportCapabilityRefusal(
  BuildContext context,
  WidgetRef ref,
  CapabilityTarget capability,
  Object error,
) {
  if (!markCapabilityRefusal(ref, capability, error)) return false;
  showCapabilityRefusal(context, capability);
  return true;
}

/// The ledger half of [reportCapabilityRefusal]: records the refusal and says
/// whether [error] was one. Needs no [BuildContext], so it runs even when the
/// page that started the write has gone.
bool markCapabilityRefusal(
  WidgetRef ref,
  CapabilityTarget capability,
  Object error,
) {
  if (!isPermissionRefusal(error)) return false;
  ref
      .read(capabilityScopeProvider.notifier)
      .markReadOnly(capability.connectionId);
  return true;
}

/// The toast half of [reportCapabilityRefusal].
void showCapabilityRefusal(BuildContext context, CapabilityTarget capability) {
  final router = GoRouter.maybeOf(context);
  SnackBarHelper.withAction(
    context,
    capability.copy.refusal,
    actionLabel: capability.service.capabilityFixLabel,
    onAction: () => router?.push(
      ServiceRoutes.settingsForConnection(
        capability.service,
        capability.connectionId,
      ),
    ),
  );
}
