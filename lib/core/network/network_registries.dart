import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/network/route_poster.dart';
import 'package:cupola/core/network/unanswered_addresses.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// Keeps the four static registries the network code reads in step with
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
///  * `RoutePoster`, for the addresses a route's preloaded poster may come
///    from.
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
  RoutePoster.update(_addressesOf(ref.read(currentSettingsProvider).instances));
  ref.listen(
    currentSettingsProvider.select((s) => s.instances),
    (previous, next) => RoutePoster.update(_addressesOf(next)),
  );
  UnansweredAddresses.update(ref.read(unansweredAddressesProvider));
  ref.listen(
    unansweredAddressesProvider,
    (previous, next) => UnansweredAddresses.update(next),
  );
});

/// Every address a connection is reached at, home and away.
Iterable<String> _addressesOf(List<ServiceInstance> instances) => [
  for (final instance in instances)
    for (final address in [instance.home, ?instance.away])
      if (address.url.isNotEmpty) address.url,
];
