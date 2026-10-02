import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Who the app is for on this device, from every saved connection
/// ([audienceOf]).
///
/// Read from the saved permissions, so it is right on the first frame and
/// asks nothing of any server. A connection counts once it is set up, or
/// signed out: a form left half filled is no connection yet, and signing out
/// does not make anyone the operator.
///
/// The gate follows it at once, like it follows a grant: a control the
/// account may no longer use dims or goes the moment the answer arrives. The
/// app's shell, which follows the audience too, changes only on the next
/// return to the foreground, never under the person's finger; that hold
/// belongs to the shell, not to this value.
final audienceProvider = Provider<Audience>(
  (ref) => ref.watch(currentSettingsProvider.select(audienceOfSettings)),
);

/// [audienceOf] over the connections in [settings].
Audience audienceOfSettings(SettingsModel settings) => audienceOf([
  for (final instance in settings.instances)
    if (instance.isConfigured || instance.isSignedOut)
      (
        service: instance.service,
        seerr: switch ((instance.service, instance.account)) {
          (ServiceKey.seerr, final account?) => SeerrGrant.account(
            permissions: account.permissions,
          ),
          (ServiceKey.seerr, null) => const SeerrGrant.apiKey(),
          _ => null,
        },
      ),
]);

/// The gate a surface showing Seerr connection [connectionId] reads, empty
/// meaning the connection the lens is on.
///
/// The audience, what that connection may do ([seerrGrantProvider]), and for
/// an account the server it is on ([seerrServerFactsProvider]): its name, for
/// the operator's reasons, and its 4K servers, for the request's 4K option.
/// The server is asked only for an account that is signed in. The key may do
/// everything and dims nothing, so it never needs the server's facts, and a
/// surface the operator has always had asks nothing new.
///
/// A surface that reads no Seerr at all is answered with no grant, which the
/// gate reads by the audience alone.
final roleGateProvider = Provider.autoDispose.family<RoleGate, String>((
  ref,
  connectionId,
) {
  final audience = ref.watch(audienceProvider);
  final grant = ref.watch(seerrGrantProvider(connectionId));
  return RoleGate(
    audience: audience,
    grant: grant,
    server: grant == null || grant.isApiKey
        ? null
        : _serverOf(ref, connectionId),
  );
});

/// What the account connection [connectionId] (empty: the lens) says about
/// its server, once it has said; null while it is out, when it failed, and for
/// a connection that is not signed in, which is asked nothing.
SeerrServerFacts? _serverOf(Ref ref, String connectionId) {
  final id = connectionId.isEmpty
      ? ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id
      : connectionId;
  if (id == null) return null;
  final signedIn = ref.watch(
    currentSettingsProvider.select(
      (settings) => settings.instanceById(id)?.isConfigured ?? false,
    ),
  );
  if (!signedIn) return null;
  return ref.watch(seerrServerFactsProvider(id)).value;
}
