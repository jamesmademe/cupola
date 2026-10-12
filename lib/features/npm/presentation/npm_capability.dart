/// What an Nginx Proxy Manager account may change, and the sentences that say
/// so (decision 34).
///
/// NPM scopes an account per resource: a non-admin carries one of `hidden` /
/// `view` / `manage` for each of proxy hosts, redirections, 404 hosts,
/// streams, certificates and access lists, and `visibility` scopes which rows
/// it sees, never what it may write. An admin manages everything. A write the
/// account may not make is refused with 403 (`PermissionError`), which the
/// client reports as `NpmException.forbidden`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Asks NPM what the account saved for [connectionId] may manage.
///
/// `GET /api/users/me?expand=permissions`. For the connection the app is
/// looking through it reads [npmAccountProvider]: the same answer the audit
/// log's admin-only note reads, asked once, and for any other connection it
/// asks that connection's own client.
///
/// Admin → read-write; nothing managed → read-only; otherwise the resources
/// the account manages. No answer → `unanswered`.
Future<CapabilityGrant> probeNpmCapability(Ref ref, String connectionId) async {
  try {
    final lens =
        ref.read(activeInstanceProvider(ServiceKey.nginxProxyManager))?.id ??
        '';
    final NpmAccount? account = connectionId == lens
        ? await ref.watch(npmAccountProvider.future)
        : await ref.watch(npmClientForProvider(connectionId)).currentUser();
    return npmGrantFor(account);
  } catch (_) {
    return const CapabilityGrant.unanswered();
  }
}

/// The grant an [account] carries. Null (the probe could not answer) is
/// `unanswered`.
CapabilityGrant npmGrantFor(NpmAccount? account) {
  if (account == null) return const CapabilityGrant.unanswered();
  if (account.isAdmin) return const CapabilityGrant.readWrite();
  if (account.isViewOnly) return const CapabilityGrant.readOnly();
  return CapabilityGrant.partial({
    for (final resource in NpmResource.values)
      if (account.canManage(resource)) resource.key,
  });
}

/// How the copy names a resource: `proxy hosts`, `certificates`.
String npmResourceLabel(NpmResource resource) => switch (resource) {
  NpmResource.proxyHosts => 'proxy hosts',
  NpmResource.redirectionHosts => 'redirections',
  NpmResource.deadHosts => '404 hosts',
  NpmResource.streams => 'streams',
  NpmResource.certificates => 'certificates',
  NpmResource.accessLists => 'access lists',
};

String _labelForKey(String key) {
  for (final resource in NpmResource.values) {
    if (resource.key == key) return npmResourceLabel(resource);
  }
  return key.replaceAll('_', ' ');
}

String _joined(Iterable<String> labels) {
  final list = labels.toList();
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

/// The banner for an account that may manage some of this page and not the
/// rest: it names what it cannot change **here**.
String _npmPartialBanner(Set<String> restricted) {
  final names = _joined(restricted.map(_labelForKey));
  return 'This Nginx Proxy Manager account can read $names but not change '
      'them. Changing them needs an account that can manage $names.';
}

const _viewOnlyBanner =
    'This Nginx Proxy Manager account is view-only. Every host, certificate '
    'and access list reads; nothing here can be changed.';

/// The hint every dimmed NPM write carries.
const npmCapabilityHint = 'requires an admin account';

/// The copy of an NPM page, or of one resource's writes.
///
/// [resource] names the refusal toast's object; null is the whole-connection
/// copy the Overview and the write-free tabs use.
CapabilityCopy npmCapabilityCopy([NpmResource? resource]) => CapabilityCopy(
  service: ServiceKey.nginxProxyManager,
  answered: _viewOnlyBanner,
  scope: 'an admin account',
  hint: npmCapabilityHint,
  refusal: resource == null
      ? 'Nginx Proxy Manager refused this change. This account can read but '
            'not change it.'
      : 'Nginx Proxy Manager refused this change. This account can read but '
            'not change ${npmResourceLabel(resource)}.',
  partial: _npmPartialBanner,
);

/// The toast a dimmed NPM write raises.
String npmBlockedMessage(NpmResource resource) =>
    'This Nginx Proxy Manager account can\'t change '
    '${npmResourceLabel(resource)}. Sign in as an admin to change this.';

/// The NPM page banner, on the connection the page reads through.
///
/// [resources] are what the page writes. Null (the Overview, and the tabs
/// with no writes) shows it only when the account can change nothing at all;
/// a tab with writes shows it whenever the account may not change that tab's
/// resources, naming them.
class NpmCapabilityBannerSlot extends ConsumerWidget {
  const NpmCapabilityBannerSlot({super.key, this.resources});

  final Set<NpmResource>? resources;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CapabilityBannerSlot(
    connectionId: capabilityConnectionId(ref, ServiceKey.nginxProxyManager),
    copy: npmCapabilityCopy(),
    resources: resources?.map((resource) => resource.key).toSet(),
  );
}
