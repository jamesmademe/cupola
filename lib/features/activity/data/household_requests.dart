/// The household's requests, every Seerr's, for the operator's Requests view
/// and Everyone's requests on All.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One Seerr's requests as read: the connection, its name once there are
/// two, whether the lens is on it, and the read itself.
typedef SeerrRequestsRead = ({
  String instanceId,
  String? name,
  bool isLens,
  AsyncValue<List<SeerrRequest>> read,
});

/// The requests of every configured Seerr, in the user's order, or of the
/// one [only] names: the lens for `''`, that connection for its id. A link
/// that outlives its connection (`?i=` of a Seerr since deleted) reads every
/// one, as a link naming none does.
///
/// Each connection is read on its own (`requestsForProvider`), so one that
/// does not answer takes nobody else's requests with it, and the poll and a
/// pull that drop that family reach every list drawn from here.
final householdRequestsProvider = Provider.autoDispose
    .family<List<SeerrRequestsRead>, String?>((ref, only) {
      final ids = ref.watch(serviceInstanceIdsProvider(ServiceKey.seerr));
      final lens = ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id;
      final configured = [
        for (final id in ids)
          if (ref.watch(
            currentSettingsProvider.select(
              (settings) => settings.instanceById(id)?.isConfigured ?? false,
            ),
          ))
            id,
      ];
      final wanted = only == null
          ? null
          : only.isEmpty
          ? lens
          : only;
      final chosen = wanted != null && configured.contains(wanted)
          ? [wanted]
          : configured;
      return [
        for (final id in chosen)
          (
            instanceId: id,
            name: ref.watch(connectionNameProvider(id)),
            isLens: id == lens,
            read: ref.watch(requestsForProvider(id == lens ? '' : id)),
          ),
      ];
    });
