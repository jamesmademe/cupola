import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/network/unanswered_addresses.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Keeps the three static registries the network code reads in step with
/// the settings and the route, for as long as something watches it: the app's
/// root, and the run that reads the servers with the app off the screen
/// (`OutsideRun`). Without it a run in the background would reach a pinned
/// server without its pin and a gated one without its headers.
///
///  * `CertTrustRegistry`, for the leaf image widgets that cannot watch a
///    provider themselves; see its doc for why.
///  * `ConnectionAccessRegistry`, for each connection's access, which an
///    arr's artwork needs as much as its API calls.
///  * `UnansweredAddresses`, for the connections neither of whose addresses
///    answered the route probe, so a client's next request names both.
///
/// Each is set from the current value first, since `listen` alone only fires
/// on a change, and then kept by the listener.
final networkRegistriesProvider = Provider<void>((ref) {
  CertTrustRegistry.update(
    ref.read(currentSettingsProvider).trustedCertificates,
  );
  ref.listen(
    currentSettingsProvider.select((s) => s.trustedCertificates),
    (previous, next) => CertTrustRegistry.update(next),
  );
  ConnectionAccessRegistry.update(
    ref.read(currentSettingsProvider).accessHeadersByAddress,
  );
  ref.listen(
    currentSettingsProvider.select((s) => s.accessHeadersByAddress),
    (previous, next) => ConnectionAccessRegistry.update(next),
  );
  UnansweredAddresses.update(ref.read(unansweredAddressesProvider));
  ref.listen(
    unansweredAddressesProvider,
    (previous, next) => UnansweredAddresses.update(next),
  );
});
