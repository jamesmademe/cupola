import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/unreached_origins.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'http://192.168.1.20:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(url: 'https://radarr.example.com'),
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'http://192.168.1.20:8989',
  credential: 'sonarr-key',
);

class _Settings extends Notifier<SettingsModel> {
  @override
  SettingsModel build() => const SettingsModel(instances: [_radarr, _sonarr]);

  // ignore: use_setters_to_change_properties
  void set(SettingsModel value) => state = value;
}

final _settings = NotifierProvider<_Settings, SettingsModel>(_Settings.new);

/// Which addresses answer, by URL, and every knock asked.
class _Knocks {
  final answering = <String>{};
  final asked = <String>[];

  Future<bool> knock(
    ServiceKey service,
    ConnectionReach reach, {
    required Duration timeout,
  }) async {
    asked.add(reach.url);
    return answering.contains(reach.url);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Knocks knocks;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    knocks = _Knocks();
    now = DateTime(2026, 10, 13, 12);
  });

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureSettingsStoreProvider.overrideWithValue(
          FakeSecureSettingsStore(),
        ),
        currentSettingsProvider.overrideWith((ref) => ref.watch(_settings)),
        initialActiveInstancesProvider.overrideWithValue(const {}),
        routeKnockProvider.overrideWithValue(
          (service, reach, {required timeout}) =>
              knocks.knock(service, reach, timeout: timeout),
        ),
        calendarClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Starts the probe and lets its first round finish.
  Future<RouteProbe> started(ProviderContainer container) async {
    final probe = container.read(routeProbeProvider);
    await pumpEventQueue();
    return probe;
  }

  ConnectionRoute? routeOf(ProviderContainer container, String id) =>
      container.read(connectionRoutesProvider)[id];

  group('decideRoute', () {
    test('home when home answers, whatever away says', () async {
      expect(
        await decideRoute(
          home: Future.value(true),
          away: Completer<bool>().future,
        ),
        ConnectionRoute.home,
      );
    });

    test('away when only away answers', () async {
      expect(
        await decideRoute(home: Future.value(false), away: Future.value(true)),
        ConnectionRoute.away,
      );
    });

    test('nothing when neither answers', () async {
      expect(
        await decideRoute(home: Future.value(false), away: Future.value(false)),
        isNull,
      );
    });
  });

  test('away from home, a start moves the connection away', () async {
    knocks.answering.add('https://radarr.example.com');
    final c = await container();

    final probe = await started(c);

    expect(routeOf(c, 'radarr'), ConnectionRoute.away);
    expect(probe.recheckArmed, isTrue, reason: 'it rechecks for home');
  });

  test('a connection with one address is never knocked on', () async {
    final c = await container();

    await started(c);

    expect(knocks.asked, isNot(contains('http://192.168.1.20:8989')));
  });

  test('back home, a return to the foreground moves it home', () async {
    knocks.answering.add('https://radarr.example.com');
    final c = await container();
    final probe = await started(c);

    knocks.answering.add('http://192.168.1.20:7878');
    probe.onResume();
    await pumpEventQueue();

    expect(routeOf(c, 'radarr'), isNull, reason: 'home is the default');
    expect(probe.recheckArmed, isFalse);
  });

  test('neither answering leaves the route as it was', () async {
    SharedPreferences.setMockInitialValues({'connection_routes': '["radarr"]'});
    final c = await container();

    await started(c);

    expect(routeOf(c, 'radarr'), ConnectionRoute.away);
  });

  group('an address that stops answering', () {
    test('is probed again at once, then not before 30 seconds', () async {
      final c = await container();
      await started(c);
      knocks.asked.clear();

      UnreachedOrigins.report(Uri.parse('http://192.168.1.20:7878/api/v3/x'));
      await pumpEventQueue();
      expect(knocks.asked, hasLength(2), reason: 'both addresses');

      knocks.asked.clear();
      now = now.add(const Duration(seconds: 10));
      UnreachedOrigins.report(Uri.parse('http://192.168.1.20:7878/api/v3/x'));
      await pumpEventQueue();
      expect(knocks.asked, isEmpty);

      now = now.add(unreachedProbeInterval);
      UnreachedOrigins.report(Uri.parse('http://192.168.1.20:7878/api/v3/x'));
      await pumpEventQueue();
      expect(knocks.asked, hasLength(2));
    });

    test('on another origin knocks on nothing', () async {
      final c = await container();
      await started(c);
      knocks.asked.clear();

      UnreachedOrigins.report(Uri.parse('http://192.168.1.20:8989/api'));
      await pumpEventQueue();

      expect(knocks.asked, isEmpty);
    });
  });

  test('a connection given an address away is probed at once', () async {
    final c = await container();
    await started(c);
    knocks.asked.clear();

    c
        .read(_settings.notifier)
        .set(
          SettingsModel(
            instances: [
              _radarr,
              _sonarr.copyWith(
                away: const ConnectionAddress(
                  url: 'https://sonarr.example.com',
                ),
              ),
            ],
          ),
        );
    c.read(currentSettingsProvider);
    await pumpEventQueue();

    expect(knocks.asked, contains('https://sonarr.example.com'));
  });
}
