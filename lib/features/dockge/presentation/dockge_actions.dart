import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';

/// Runs a [DockgeClient] mutation with the shared plumbing every action button
/// uses: resolve the client, await [action], invalidate [invalidate] providers
/// on success and report the outcome via [SnackBarHelper].
///
/// Returns `true` when the action completed without throwing so callers can
/// chain follow-up work (popping a screen, clearing state) only on success.
///
/// [client] is the connection the action belongs to, when it is not the one
/// the lens is on: Home's Start on a stack that exited on the second Dockge
/// has to reach that Dockge.
Future<bool> runDockgeAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(DockgeClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
  DockgeClient? client,
}) {
  // The *lensed* client by default: an action fired while the lens is on an
  // agent has to reach that agent, and `dockgeClientProvider` is always the
  // hub.
  final DockgeClient target = client ?? ref.read(dockgeLensedClientProvider);
  return runServiceAction(
    context,
    ref,
    action: () => action(target),
    successMessage: successMessage,
    failureMessage: failureMessage,
    invalidate: invalidate,
    refreshOnFailure: true,
  );
}

/// Convenience wrapper around [runDockgeAction] for the action buttons/chips
/// that fire a stack mutation with the positional
/// `(action, success, failure)` shape. Invalidates [invalidate] when the action
/// succeeds. Returns the same `bool`.
Future<bool> runDockgeStackAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(DockgeClient client) action,
  String success,
  String failure, {
  List<ProviderOrFamily> invalidate = const [],
  DockgeClient? client,
}) => runDockgeAction(
  context,
  ref,
  action: action,
  successMessage: success,
  failureMessage: failure,
  invalidate: invalidate,
  client: client,
);

/// The stack commands that interrupt something that is running, and so ask
/// first. Start is additive and stays a single tap; Delete has its own dialog.
enum DockgeStackLifecycle { stop, restart, update, down }

/// What a lifecycle confirmation says: one copy for the Stacks list row and
/// the stack page, so the same command cannot be described two ways.
///
/// Stop and Restart are the list row's words, which came first. Update and
/// Down say what Dockge actually runs (`backend/stack.ts`): Update is
/// `docker compose pull`, then `up -d --remove-orphans` only if the stack is
/// running; Down is `docker compose down`, which removes the containers and
/// their network but not named volumes or the compose file.
({String title, String message, String confirmLabel}) dockgeLifecycleCopy(
  DockgeStackLifecycle verb,
  String stack,
) => switch (verb) {
  DockgeStackLifecycle.stop => (
    title: 'Stop $stack?',
    message:
        'The stack and its containers will be stopped until you start them '
        'again.',
    confirmLabel: 'Stop stack',
  ),
  DockgeStackLifecycle.restart => (
    title: 'Restart $stack?',
    message: 'The stack will be briefly unavailable while it restarts.',
    confirmLabel: 'Restart stack',
  ),
  DockgeStackLifecycle.update => (
    title: 'Update $stack?',
    message:
        'Dockge pulls the newest images. If the stack is running, containers '
        'whose image changed are recreated, so it is briefly unavailable.',
    confirmLabel: 'Update stack',
  ),
  DockgeStackLifecycle.down => (
    title: 'Take $stack down?',
    message:
        'Its containers are removed, not just stopped. Named volumes and the '
        'compose file stay, so Start creates them again.',
    confirmLabel: 'Take down',
  ),
};

/// Asks before [verb] runs on [stack]; true when the user confirmed.
///
/// Neutral, like every confirmation: red means unreachable and nothing else.
/// The Stacks list row's Stop used to confirm in red and the stack page's in
/// the theme's fill, the same command drawn two ways, until both came here.
Future<bool> confirmDockgeLifecycle(
  BuildContext context,
  DockgeStackLifecycle verb,
  String stack,
) async {
  final copy = dockgeLifecycleCopy(verb, stack);
  final result = await showAppConfirmDialog(
    context: context,
    title: copy.title,
    message: copy.message,
    confirmLabel: copy.confirmLabel,
  );
  return result.confirmed;
}
