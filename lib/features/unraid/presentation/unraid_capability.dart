/// What an Unraid API key may change, and the sentences that say so.
///
/// Cupola writes two Unraid resources: VMs (start, stop, resume) and
/// notifications (archive). An `ADMIN` key writes both. Any other key writes a
/// resource only if its **explicit** permissions grant an `_ANY` write action
/// on it — the roles `VIEWER`, `CONNECT` and `GUEST` imply none. A write the
/// key may not make is refused as a GraphQL `FORBIDDEN` error on HTTP 200.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// The resources Cupola writes, by their capability key.
const unraidGatedResources = {UnraidResource.vms, UnraidResource.notifications};

/// Asks Unraid what the key saved for [connectionId] may change:
/// `query { me { roles permissions { resource actions } } }`.
///
/// Watches the connection's client, so a new key re-asks.
Future<CapabilityGrant> probeUnraidCapability(
  Ref ref,
  String connectionId,
) async {
  try {
    final capabilities = await ref
        .watch(unraidClientForProvider(connectionId))
        .getCapabilities();
    return unraidGrantFor(capabilities);
  } catch (_) {
    // A transport error, a bad key (`UNAUTHENTICATED`, which the connection's
    // own health path reports) or a server too old to carry `me`.
    return const CapabilityGrant.unanswered();
  }
}

/// The grant [capabilities] carry, over the resources Cupola writes.
CapabilityGrant unraidGrantFor(UnraidCapabilities capabilities) {
  if (!capabilities.answered) return const CapabilityGrant.unanswered();
  if (capabilities.isAdmin) return const CapabilityGrant.readWrite();
  final writable = {
    for (final resource in unraidGatedResources)
      if (capabilities.writable.contains(resource)) resource.name,
  };
  if (writable.isEmpty) return const CapabilityGrant.readOnly();
  return CapabilityGrant.partial(writable);
}

/// The VMs page's sentences.
const unraidVmsCopy = CapabilityCopy(
  service: ServiceKey.unraid,
  answered:
      'This Unraid key can read. Starting and stopping VMs needs a key with '
      'write access to VMs.',
  scope: 'write access to VMs',
  hint: 'requires a key that can write VMs',
);

/// The Notifications page's sentences.
const unraidNotificationsCopy = CapabilityCopy(
  service: ServiceKey.unraid,
  answered:
      'This Unraid key can read. Archiving notifications needs a key with '
      'write access to notifications.',
  scope: 'write access to notifications',
  hint: 'requires a key that can write notifications',
);
