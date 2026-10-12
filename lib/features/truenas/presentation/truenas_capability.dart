/// What a TrueNAS API key may change, and the sentences that say so.
///
/// The roles table lives in `domain/truenas_capability.dart`; this file asks
/// the server and turns the answer into a grant the pages gate on.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/auth_api.dart';
import 'package:cupola/features/truenas/data/system_api.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// Asks TrueNAS what the key saved for [connectionId] may change.
///
/// Three reads over the connection's own socket: `auth.me` for the expanded
/// roles, `system.version` because two areas and every `service.*` rule
/// changed in 25.10, and `service.query` so each listed service gets its own
/// `service:<name>` key. A key without `FULL_ADMIN` that cannot read the
/// version is judged by the 25.04 rules, the stricter ones; one that cannot
/// list services simply gets no service keys.
Future<CapabilityGrant> probeTrueNasCapability(
  Ref ref,
  String connectionId,
) async {
  try {
    final client = ref.watch(truenasClientForProvider(connectionId));
    final roles = await TrueNasAuthApi(client).myRoles();
    if (roles == null) return const CapabilityGrant.unanswered();
    if (roles.contains(trueNasFullAdmin)) {
      return const CapabilityGrant.readWrite();
    }
    final system = TrueNasSystemApi(client);
    TrueNasVersion? version;
    try {
      version = TrueNasVersion.parse(await system.getVersion());
    } catch (_) {
      version = null;
    }
    var services = const <String>[];
    try {
      services = [for (final s in await system.getServices()) s.name];
    } catch (_) {
      services = const [];
    }
    return trueNasGrantFor(roles, version: version, services: services);
  } catch (_) {
    return const CapabilityGrant.unanswered();
  }
}

/// The grant [roles] carry on [version], over [services].
CapabilityGrant trueNasGrantFor(
  Set<String> roles, {
  TrueNasVersion? version,
  Iterable<String> services = const [],
}) {
  if (roles.contains(trueNasFullAdmin)) {
    return const CapabilityGrant.readWrite();
  }
  final writable = <String>{
    for (final area in TrueNasCapabilityArea.values)
      if (area.grantedBy(version).any(roles.contains)) area.key,
    for (final service in services)
      if (trueNasMayWriteService(service, roles, version))
        trueNasServiceArea(service),
  };
  if (writable.isEmpty) return const CapabilityGrant.readOnly();
  return CapabilityGrant.partial(writable);
}

/// The hint every dimmed TrueNAS write carries.
const trueNasCapabilityHint = 'requires a TrueNAS key with write access';

String _trueNasPartialBanner(Set<String> restricted) =>
    'This TrueNAS key can change some of this page but not all of it. The '
    'dimmed controls need a key whose user holds the matching write role, '
    'such as Full Admin.';

/// The sentences every TrueNAS page speaks.
const trueNasCapabilityCopy = CapabilityCopy(
  service: ServiceKey.truenas,
  answered:
      'This TrueNAS key can read. Changing anything here needs a key whose '
      'user holds a write role, such as Full Admin.',
  scope: 'a key with write access',
  hint: trueNasCapabilityHint,
  partial: _trueNasPartialBanner,
);

/// The toast a dimmed TrueNAS write raises: *This TrueNAS key can't delete
/// snapshots.*
String trueNasBlockedMessage(String verbPhrase) =>
    'This TrueNAS key can\'t $verbPhrase.';

/// The connection the TrueNAS pages read through, read once: for action code.
String readTrueNasConnectionId(WidgetRef ref) =>
    ref.read(activeInstanceProvider(ServiceKey.truenas))?.id ?? '';

/// Whether a TrueNAS write on [area] may go ahead: the menu-item and in-flow
/// counterpart of the gated widgets. Raises the toast and returns false when
/// it may not.
bool trueNasWriteAllowed(
  BuildContext context,
  WidgetRef ref, {
  required String area,
  required String verbPhrase,
}) => capabilityWriteAllowed(
  context,
  ref,
  service: ServiceKey.truenas,
  connectionId: readTrueNasConnectionId(ref),
  resource: area,
  blockedMessage: trueNasBlockedMessage(verbPhrase),
);

/// An `IconButton` TrueNAS write gated on [area].
Widget trueNasGatedIcon({
  required WidgetRef ref,
  required String area,
  required String verbPhrase,
  required String tooltip,
  required Widget icon,
  required VoidCallback onTap,
  Color? color,
  Key? key,
}) => CapabilityGatedAction.icon(
  key: key,
  service: ServiceKey.truenas,
  connectionId: capabilityConnectionId(ref, ServiceKey.truenas),
  resource: area,
  hint: trueNasCapabilityHint,
  blockedMessage: trueNasBlockedMessage(verbPhrase),
  tooltip: tooltip,
  icon: icon,
  color: color,
  onTap: onTap,
);

/// A button TrueNAS write gated on [area]; see
/// [CapabilityGatedAction.builder].
Widget trueNasGatedButton({
  required WidgetRef ref,
  required String area,
  required String verbPhrase,
  required VoidCallback onTap,
  required GatedAffordanceBuilder builder,
}) => CapabilityGatedAction.builder(
  service: ServiceKey.truenas,
  connectionId: capabilityConnectionId(ref, ServiceKey.truenas),
  resource: area,
  hint: trueNasCapabilityHint,
  blockedMessage: trueNasBlockedMessage(verbPhrase),
  onTap: onTap,
  builder: builder,
);

/// A `Switch` TrueNAS write gated on [area].
Widget trueNasGatedToggle({
  required WidgetRef ref,
  required String area,
  required String verbPhrase,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => CapabilityGatedAction.toggle(
  service: ServiceKey.truenas,
  connectionId: capabilityConnectionId(ref, ServiceKey.truenas),
  resource: area,
  hint: trueNasCapabilityHint,
  blockedMessage: trueNasBlockedMessage(verbPhrase),
  value: value,
  onChanged: onChanged,
);

/// The label of a `PopupMenuItem` TrueNAS write on [area].
Widget trueNasGatedMenuLabel({
  required WidgetRef ref,
  required String area,
  required String text,
  TextStyle? style,
}) => CapabilityGatedMenuLabel(
  service: ServiceKey.truenas,
  // Read, not watched: a menu's items are built in the menu's own route, not
  // in the page whose `ref` this is. The label watches the grant itself.
  connectionId: readTrueNasConnectionId(ref),
  resource: area,
  text: text,
  hint: trueNasCapabilityHint,
  style: style,
);
