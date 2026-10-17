import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/release_search/domain/release_search_headroom.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_headroom_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('classifyGateway', () {
    test('a cf-ray header wins over whatever server claims', () {
      // Cloudflare fronting nginx is the common case, and the cap that matters
      // is the outer one.
      expect(
        classifyGateway('nginx', hasCfRay: true),
        SearchGateway.cloudflare,
      );
    });

    test('no server header means nothing is in the middle', () {
      expect(classifyGateway(null), SearchGateway.direct);
      expect(classifyGateway(''), SearchGateway.direct);
    });

    test('nginx is recognised whatever version it advertises', () {
      expect(classifyGateway('nginx/1.24.0'), SearchGateway.nginx);
      expect(classifyGateway('NGINX'), SearchGateway.nginx);
    });

    test(
      'the arrs\' own web server is the service, not something in front',
      () {
        // Radarr, Sonarr and Lidarr are .NET apps and name their own server.
        expect(classifyGateway('Kestrel'), SearchGateway.direct);
        expect(classifyGateway('Mono-HTTPAPI/1.0'), SearchGateway.direct);
      },
    );

    test('an unknown intermediary is named but not advised about', () {
      expect(classifyGateway('Caddy'), SearchGateway.other);
      const headroom = SearchHeadroom(gateway: SearchGateway.other);
      expect(headroom.knownCap, isNull);
    });
  });

  group('known caps', () {
    test('Cloudflare caps at 100s and cannot be raised', () {
      const h = SearchHeadroom(gateway: SearchGateway.cloudflare);
      expect(h.knownCap, const Duration(seconds: 100));
      expect(h.capIsRaisable, isFalse);
    });

    test('nginx caps at 60s and can be raised', () {
      const h = SearchHeadroom(gateway: SearchGateway.nginx);
      expect(h.knownCap, const Duration(seconds: 60));
      expect(h.capIsRaisable, isTrue);
    });

    test('a direct path has no ceiling to report', () {
      const h = SearchHeadroom(gateway: SearchGateway.direct);
      expect(h.knownCap, isNull);
    });
  });

  group('measurements', () {
    test('keeps the longest success and the earliest cut-off', () {
      // Earliest, not latest: the ceiling is where the path first refuses.
      final h = const SearchHeadroom()
          .recordSuccess(const Duration(seconds: 20))
          .recordSuccess(const Duration(seconds: 47))
          .recordSuccess(const Duration(seconds: 31))
          .recordCutoff(const Duration(seconds: 90))
          .recordCutoff(const Duration(seconds: 62));

      expect(h.longestSuccess, const Duration(seconds: 47));
      expect(h.earliestCutoff, const Duration(seconds: 62));
    });

    test('reports a ceiling only when the evidence brackets one', () {
      final bracketed = const SearchHeadroom()
          .recordSuccess(const Duration(seconds: 47))
          .recordCutoff(const Duration(seconds: 62));
      expect(bracketed.likelyCeiling, const Duration(seconds: 62));

      // A success longer than the earliest cut-off means the path is
      // inconsistent; naming a number from that is worse than naming none.
      final contradictory = const SearchHeadroom()
          .recordSuccess(const Duration(seconds: 90))
          .recordCutoff(const Duration(seconds: 62));
      expect(contradictory.likelyCeiling, isNull);

      expect(const SearchHeadroom().likelyCeiling, isNull);
    });

    test('keeps only the last five durations, newest first', () {
      var h = const SearchHeadroom();
      for (var i = 1; i <= 7; i++) {
        h = h.recordSuccess(Duration(seconds: i));
      }
      expect(h.recentDurations, hasLength(SearchHeadroom.maxRecent));
      expect(h.recentDurations.first, const Duration(seconds: 7));
    });

    test('needs three samples before calling an instance slow', () {
      var h = const SearchHeadroom()
          .recordSuccess(const Duration(seconds: 30))
          .recordSuccess(const Duration(seconds: 30));
      expect(
        h.isHabituallySlow,
        isFalse,
        reason: 'two slow searches could be a bad afternoon',
      );

      h = h.recordSuccess(const Duration(seconds: 30));
      expect(h.isHabituallySlow, isTrue);
    });

    test('a fast instance is never called slow', () {
      var h = const SearchHeadroom();
      for (var i = 0; i < 5; i++) {
        h = h.recordSuccess(const Duration(seconds: 2));
      }
      expect(h.isHabituallySlow, isFalse);
    });
  });

  group('persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a measured path survives a restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final notifier = first.read(searchHeadroomProvider.notifier);
      notifier.recordGateway(
        ServiceKey.sonarr,
        SearchGateway.nginx,
        'nginx/1.24.0',
      );
      notifier.recordSuccess(ServiceKey.sonarr, const Duration(seconds: 47));
      notifier.recordCutoff(ServiceKey.sonarr, const Duration(seconds: 62));
      first.dispose();

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);

      final restored = second.read(serviceHeadroomProvider(ServiceKey.sonarr));
      expect(restored.gateway, SearchGateway.nginx);
      expect(restored.gatewayName, 'nginx/1.24.0');
      expect(restored.longestSuccess, const Duration(seconds: 47));
      expect(restored.earliestCutoff, const Duration(seconds: 62));
    });

    test('services are measured independently', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);

      c
          .read(searchHeadroomProvider.notifier)
          .recordGateway(ServiceKey.sonarr, SearchGateway.cloudflare, null);

      // The whole point of the card: one stack, two different paths.
      expect(
        c.read(serviceHeadroomProvider(ServiceKey.sonarr)).gateway,
        SearchGateway.cloudflare,
      );
      expect(
        c.read(serviceHeadroomProvider(ServiceKey.radarr)).gateway,
        isNull,
      );
    });

    test('it resolves where SharedPreferences was never provided', () {
      final bare = ProviderContainer();
      addTearDown(bare.dispose);
      expect(bare.read(searchHeadroomProvider), isEmpty);
    });
  });

  test('only the path cutting a search off says how long the path allows', () {
    expect(isPathCutoff(ReleaseSearchFailureKind.gatewayTimeout), isTrue);
    expect(isPathCutoff(ReleaseSearchFailureKind.cloudflareCap), isTrue);
    // Cupola's own wait running out is the setting, not the path.
    expect(isPathCutoff(ReleaseSearchFailureKind.clientTimeout), isFalse);
    expect(isPathCutoff(ReleaseSearchFailureKind.connectionLost), isFalse);
    expect(isPathCutoff(null), isFalse);
  });

  group('what the first version kept', () {
    test(
      'is read once: its cut-offs dropped, its gateway classified again',
      () async {
        SharedPreferences.setMockInitialValues({
          'release_search_headroom':
              '{"sonarr":{"gateway":"other","gatewayName":"Kestrel",'
              '"longestMs":197000,"cutoffMs":300000,"recentMs":[197000]}}',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final sonarr = container.read(
          serviceHeadroomProvider(ServiceKey.sonarr),
        );

        // Cupola's own wait running out was kept as the path's ceiling.
        expect(sonarr.earliestCutoff, isNull);
        expect(sonarr.likelyCeiling, isNull);
        expect(sonarr.gateway, SearchGateway.direct);
        expect(sonarr.longestSuccess, const Duration(seconds: 197));
        await Future<void>.delayed(Duration.zero);
        expect(prefs.getString('release_search_headroom'), isNull);
        expect(prefs.getString('release_search_headroom_v2'), isNotNull);
      },
    );
  });
}
