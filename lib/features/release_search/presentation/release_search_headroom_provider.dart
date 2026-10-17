import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/domain/release_search_headroom.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Everything Cupola has measured about how each instance is reached.
///
/// Persisted in `SharedPreferences` rather than secure storage: these are timings
/// and a server name, not credentials, and the card that shows them says out loud
/// that they never leave the device.
final searchHeadroomProvider =
    NotifierProvider<SearchHeadroomNotifier, Map<ServiceKey, SearchHeadroom>>(
      SearchHeadroomNotifier.new,
    );

/// The headroom for one service, or an empty record.
final serviceHeadroomProvider = Provider.family<SearchHeadroom, ServiceKey>((
  ref,
  service,
) {
  return ref.watch(searchHeadroomProvider)[service] ?? const SearchHeadroom();
});

class SearchHeadroomNotifier extends Notifier<Map<ServiceKey, SearchHeadroom>> {
  static const _key = 'release_search_headroom_v2';

  /// What the first version kept, read once and then removed. Its cut-offs
  /// may be Cupola's own wait running out, which it took for the path's, so
  /// they are dropped; its gateway is classified again from the server's own
  /// name, since it took Kestrel, the arrs' own server, for something in front
  /// of them. Durations that completed stay true and are kept.
  static const _firstKey = 'release_search_headroom';

  @override
  Map<ServiceKey, SearchHeadroom> build() {
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      final raw = prefs.getString(_key);
      if (raw != null) return _decode(raw);
      final first = prefs.getString(_firstKey);
      if (first == null) return const {};
      final migrated = {
        for (final MapEntry(:key, :value) in _decode(first).entries)
          key: SearchHeadroom(
            gateway: value.gateway == SearchGateway.cloudflare
                ? value.gateway
                : value.gatewayName == null
                ? value.gateway
                : classifyGateway(value.gatewayName),
            gatewayName: value.gatewayName,
            longestSuccess: value.longestSuccess,
            recentDurations: value.recentDurations,
          ),
      };
      _persist(migrated);
      unawaited(prefs.remove(_firstKey));
      return migrated;
    } catch (_) {
      return const {};
    }
  }

  static Map<ServiceKey, SearchHeadroom> _decode(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <ServiceKey, SearchHeadroom>{};
    for (final entry in decoded.entries) {
      for (final service in ServiceKey.values) {
        if (service.name != entry.key) continue;
        result[service] = SearchHeadroom.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return result;
  }

  /// Records a search that came back with an answer.
  void recordSuccess(ServiceKey service, Duration elapsed) {
    _update(service, (current) => current.recordSuccess(elapsed));
  }

  /// Records a search that was cut off by something in the middle.
  ///
  /// Only the path's cut-offs belong here. A lost connection, a server error
  /// or Cupola's own wait running out says nothing about how long the path
  /// allows, and folding it in would report a ceiling that does not exist.
  void recordCutoff(ServiceKey service, Duration elapsed) {
    _update(service, (current) => current.recordCutoff(elapsed));
  }

  void recordGateway(ServiceKey service, SearchGateway gateway, String? name) {
    _update(service, (current) => current.withGateway(gateway, name: name));
  }

  void _update(
    ServiceKey service,
    SearchHeadroom Function(SearchHeadroom current) transform,
  ) {
    final next = Map<ServiceKey, SearchHeadroom>.of(state);
    next[service] = transform(next[service] ?? const SearchHeadroom());
    state = next;
    _persist(next);
  }

  void _persist(Map<ServiceKey, SearchHeadroom> value) {
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(
            _key,
            jsonEncode({
              for (final entry in value.entries)
                entry.key.name: entry.value.toJson(),
            }),
          );
    } catch (_) {
      // No prefs in this scope; the in-memory record still serves the session.
    }
  }
}

/// Asks the instance one ordinary question and reads who answered.
///
/// Deliberately **not** a timing probe: nothing here tries to make the server
/// slow, so it cannot be mistaken for load on the user's stack. All it does is
/// look at the response's own headers, which is enough to name the intermediary
/// and therefore enough to name its ceiling.
final headroomProbeProvider =
    Provider<Future<SearchGateway> Function(ServiceKey)>((ref) {
      return (service) async {
        Response<dynamic> response;
        switch (service) {
          case ServiceKey.sonarr:
            response = await ref.read(sonarrServiceProvider).probeHeaders();
          case ServiceKey.radarr:
            response = await ref.read(radarrServiceProvider).probeHeaders();
          case ServiceKey.lidarr:
            response = await ref.read(lidarrServiceProvider).probeHeaders();
          default:
            throw UnsupportedError(
              '${service.name} has no release search to measure',
            );
        }

        final headers = response.headers;
        final gateway = classifyGateway(
          headers.value('server'),
          hasCfRay: headers.value('cf-ray') != null,
        );
        ref
            .read(searchHeadroomProvider.notifier)
            .recordGateway(service, gateway, headers.value('server'));
        return gateway;
      };
    });
