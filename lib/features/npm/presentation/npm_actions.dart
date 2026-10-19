import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Runs an [NpmClient] mutation with the shared plumbing.
///
/// [NpmException.message] is always a static sentence or one of NPM's own fixed
/// strings: the client never interpolates a response body, so the `$e` below
/// cannot carry the bearer token or the password. That is the whole reason the
/// client is strict about it: this line is where it would otherwise surface.
///
/// [resource] is what the write changes, so a refusal names it.
Future<bool> runNpmAction(
  BuildContext context,
  WidgetRef ref, {
  required NpmResource resource,
  required Future<void> Function(NpmClient client) action,
  String? successMessage,
  required String failureMessage,
  List<ProviderOrFamily> invalidate = const [],
}) async {
  final client = ref.read(npmClientProvider);
  final capability = CapabilityTarget(
    connectionId:
        ref.read(activeInstanceProvider(ServiceKey.nginxProxyManager))?.id ??
        '',
    copy: npmCapabilityCopy(resource),
  );
  // Taken before the `await`, not read from [ref] after it: a renewal or a slow
  // write outlasts the page that asked.
  final container = ProviderScope.containerOf(context, listen: false);
  final say = outcomeSayer(context);
  try {
    await action(client);
    for (final provider in invalidate) {
      container.invalidate(provider);
    }
    if (successMessage != null) {
      say((at) => SnackBarHelper.success(at, successMessage));
    }
    return true;
  } catch (e) {
    // The second half of decision 34's rule: the role comes back with the
    // probe, and a refusal on any write marks the connection too. It reads
    // `forbidden` rather than the reason because NPM folds a wrong password and
    // an expired token onto the same `unauthorized` verdict, and neither of
    // those says anything about what this account may change: dimming the
    // whole screen over a mistyped password would be a lie with a long tail.
    final refused = markCapabilityRefusal(container, capability, e);
    for (final provider in invalidate) {
      container.invalidate(provider);
    }
    say((at) {
      if (refused) {
        showCapabilityRefusal(at, capability);
      } else {
        SnackBarHelper.error(at, failureMessage, detail: e);
      }
    });
    return false;
  }
}

/// Asks the user to type [phrase] before an outward-facing change goes through.
///
/// A heavier gate than [showAppConfirmDialog], used where the blast radius
/// leaves the device: disabling a proxy host takes a hostname offline for
/// everyone who uses it, not just for the person holding the phone, and it does
/// so instantly and silently. A tap-to-confirm is calibrated for "are you
/// sure"; this is calibrated for "do you know which one you are about to take
/// down", which is a different question and the one that actually goes wrong on
/// a small screen.
///
/// The dialog itself is the shared [showAppTypedConfirmDialog], neutral, with
/// the verb carrying the weight, which the TrueNAS power card reads too.
Future<bool> confirmByTyping(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
}) => showAppTypedConfirmDialog(
  context,
  title: title,
  message: message,
  phrase: phrase,
  confirmLabel: confirmLabel,
);
