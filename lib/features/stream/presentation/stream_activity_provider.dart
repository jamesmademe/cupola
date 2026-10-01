import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// One playback plus which server is serving it.
///
/// The pairing is the point: `/activity` merges sources, so a row has to be able
/// to say where it came from — the same problem the Recently Added rail solves
/// with an accent dot and a spoken `accentLabel`. [instanceId] is the connection
/// serving it, which is where its Stop goes, and [connectionName] is how the
/// row names it once its service has two (`SettingsModel.connectionName`).
typedef StreamActivityRow = ({
  ServiceKey service,
  String instanceId,
  String? connectionName,
  StreamSession session,
});

/// A media server connection that did not answer, as the note names it.
typedef StreamOfflineSource = ({
  ServiceKey service,
  String instanceId,
  String title,
});

/// One connection of a media server.
typedef StreamConnection = ({ServiceKey service, String instanceId});

/// What is playing on one named connection of a media server.
///
/// The lens's own connection collapses onto [jellyfinSessionsProvider] or
/// [plexSessionsProvider], so the service's own Now playing page and Activity
/// read one cache and an override of either still reaches both. Every other
/// connection asks its own client. Read by both [streamActivityProvider] and
/// [streamActivityOfflineProvider], so a second Jellyfin is asked once.
final streamSessionsForProvider =
    FutureProvider.family<List<StreamSession>, StreamConnection>((
      ref,
      key,
    ) async {
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      final isJellyfin = key.service == ServiceKey.jellyfin;
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return isJellyfin
            ? ref.watch(jellyfinSessionsProvider.future)
            : ref.watch(plexSessionsProvider.future);
      }
      final StreamServerClient client = isJellyfin
          ? ref.watch(jellyfinClientForProvider(key.instanceId))
          : ref.watch(plexClientForProvider(key.instanceId));
      return client.getSessions();
    }, retry: noProviderRetry);

/// Whether one Plex connection may stop a playback, for the stop control.
///
/// The lens's is [plexCapabilitiesProvider]; another connection is asked on
/// its own, because Plex Pass and the owner's scope are per server.
final streamPlexCapabilitiesForProvider =
    FutureProvider.family<PlexServerCapabilities?, String>((
      ref,
      instanceId,
    ) async {
      final lens = ref.watch(activeInstanceProvider(ServiceKey.plex))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(plexCapabilitiesProvider.future);
      }
      return ref.watch(plexClientForProvider(instanceId)).getCapabilities();
    }, retry: noProviderRetry);

/// Every configured connection of the media servers, in registry and then
/// the user's order, with what a row calls it.
List<({StreamConnection key, String? name})> _streamConnections(Ref ref) {
  final settings = ref.watch(currentSettingsProvider);
  return [
    for (final service in ServiceDomain.stream.services)
      for (final instance in settings.configuredInstancesOf(service))
        (
          key: (service: service, instanceId: instance.id),
          name: settings.connectionName(instance.id),
        ),
  ];
}

/// Every live playback across every connection of both media servers, most
/// expensive first.
///
/// **Deliberately not a `GlobalActivityItem`, and this is the load-bearing
/// decision on this surface.** Forcing a session into that model needs a
/// `ServiceType`, which is a closed `{movies, series, music, discover}` with no
/// legal value for a media server — and adding one breaks **21 exhaustive
/// switches** across the activity feature, plus 6 more on `GlobalActivityKind`,
/// two of which have `_ =>` fallbacks that would silently mis-route a session row
/// instead of failing to compile. A playing session is also genuinely a different
/// record: it has a person, a device and a delivery method, and none of the queue
/// affordances (retry, blocklist, change category) mean anything for it.
///
/// So the Streaming sub-segment carries its own type end to end. That is why
/// `_ActivitySub.custom` exists.
///
/// Sources degrade independently **while one of them still answers**: an
/// unreachable Jellyfin yields no rows rather than emptying the section, and
/// [streamActivityOfflineProvider] names it beside the sessions Plex did send.
/// That partial answer is honest — every row on screen is a fact, and the
/// silence is named.
///
/// When **no** configured server answered there is no partial answer to show,
/// and this throws the last failure. It used to return `[]`, which the section
/// drew as "Nobody is watching right now" about servers nobody could ask — the
/// offline note never fired either, because the sessions reads swallowed their
/// own failures until they stopped.
///
/// `retry: noProviderRetry` because both sessions providers carry it: a
/// derivation that dropped it would hold the failure through ten backing-off
/// re-runs its sources had already declined.
final streamActivityProvider = FutureProvider<List<StreamActivityRow>>((
  ref,
) async {
  final rows = <StreamActivityRow>[];
  var answered = 0;
  Object? failure;
  StackTrace? failureStack;

  // Every connection, not the lens: a second Jellyfin's viewers are as much
  // the household's as the first one's, and Activity is where they are all
  // counted.
  for (final connection in _streamConnections(ref)) {
    try {
      final sessions = await ref.watch(
        streamSessionsForProvider(connection.key).future,
      );
      answered++;
      rows.addAll(
        sessions.map(
          (session) => (
            service: connection.key.service,
            instanceId: connection.key.instanceId,
            connectionName: connection.name,
            session: session,
          ),
        ),
      );
    } catch (error, stack) {
      // Reported through streamActivityOfflineProvider rather than thrown: one
      // dark server must not hide the other's sessions.
      failure = error;
      failureStack = stack;
    }
  }

  if (answered == 0 && failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }

  // Transcodes first — the rows that are costing the box something are the rows
  // worth reading first, and the per-service order underneath has to stay stable
  // so a bitrate updating in place does not reshuffle the list.
  //
  // Decorated with the source index because `List.sort` is *not* guaranteed
  // stable: Dart insertion-sorts 32 elements or fewer and dual-pivot quicksorts
  // above that, so a cost-only comparator can hand back two direct plays in a
  // different order on each poll. Same pattern, and the same reason, as
  // `servicesQueueProvider`.
  final ordered =
      List.generate(
        rows.length,
        (index) => (index: index, row: rows[index]),
        growable: false,
      )..sort((a, b) {
        final aCost = a.row.session.playMethod.isTranscode ? 0 : 1;
        final bCost = b.row.session.playMethod.isTranscode ? 0 : 1;
        final byCost = aCost.compareTo(bCost);
        if (byCost != 0) return byCost;
        return a.index.compareTo(b.index);
      });

  return ordered.map((entry) => entry.row).toList(growable: false);
}, retry: noProviderRetry);

/// Configured media server connections that did not answer, each named the
/// way the rows name it.
///
/// Separate from [streamActivityProvider] for the reason
/// `servicesSectionOfflineMessage` documents: sources that degrade to `[]` make
/// "nobody is watching" and "the server is down" arrive identically, which sends
/// the user looking for the wrong thing. Naming which source is dark is what makes
/// a merged section safe.
///
/// Never throws, so its retry policy never engages; `noProviderRetry` anyway,
/// because its sources carry it.
final streamActivityOfflineProvider = FutureProvider<List<StreamOfflineSource>>(
  (ref) async {
    final offline = <StreamOfflineSource>[];

    for (final connection in _streamConnections(ref)) {
      try {
        await ref.watch(streamSessionsForProvider(connection.key).future);
      } catch (_) {
        offline.add((
          service: connection.key.service,
          instanceId: connection.key.instanceId,
          title: serviceWithConnection(
            connection.key.service,
            connection.name,
            joiner: ' ',
          ),
        ));
      }
    }

    return offline;
  },
  retry: noProviderRetry,
);

/// Whether any media server is configured at all.
///
/// The Streaming sub-segment is offered unconditionally — hiding a whole record
/// type because nothing is set up yet would make the feature undiscoverable — so
/// the body needs this to tell "not set up" from "nobody watching".
final hasStreamServiceProvider = Provider<bool>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  return ServiceDomain.stream.services.any(settings.isServiceConfigured);
});
