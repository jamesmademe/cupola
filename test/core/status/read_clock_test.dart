import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  group('ReadClock', () {
    test('has no read for a key nothing has noted', () {
      expect(ReadClock().at('sabnzbd:home'), isNull);
    });

    test('keeps the time a key was noted at', () {
      final clock = ReadClock();
      final at = DateTime(2026, 10, 12, 9, 30);

      clock.note('sabnzbd:home', at);

      expect(clock.at('sabnzbd:home'), at);
    });

    test(
      'notes now, by its own reading of the time, when no time is given',
      () {
        var now = DateTime(2026, 10, 12, 9, 30);
        final clock = ReadClock(now: () => now);

        clock.note('sabnzbd:home');
        expect(clock.at('sabnzbd:home'), DateTime(2026, 10, 12, 9, 30));

        now = DateTime(2026, 10, 12, 9, 45);
        clock.note('sabnzbd:home');
        expect(
          clock.at('sabnzbd:home'),
          DateTime(2026, 10, 12, 9, 45),
          reason: 'a later read replaces the earlier one',
        );
        expect(clock.now(), DateTime(2026, 10, 12, 9, 45));
      },
    );

    test('keeps each key apart', () {
      final clock = ReadClock();
      final home = DateTime(2026, 10, 12, 9);
      final seedbox = DateTime(2026, 10, 12, 10);

      clock.note('sabnzbd:home', home);
      clock.note('sabnzbd:seedbox', seedbox);

      expect(clock.at('sabnzbd:home'), home);
      expect(clock.at('sabnzbd:seedbox'), seedbox);
      expect(clock.at('nzbget:home'), isNull);
    });
  });

  group('queueReadKey', () {
    test('names the service and the connection', () {
      expect(
        queueReadKey(ServiceKey.sabnzbd, 'home'),
        isNot(queueReadKey(ServiceKey.sabnzbd, 'seedbox')),
      );
      expect(
        queueReadKey(ServiceKey.sabnzbd, 'home'),
        isNot(queueReadKey(ServiceKey.nzbget, 'home')),
      );
      expect(
        queueReadKey(ServiceKey.sabnzbd, 'home'),
        queueReadKey(ServiceKey.sabnzbd, 'home'),
      );
    });
  });

  group('Ref.queueReadNoter', () {
    final settings = SettingsModel(
      instances: [
        const ServiceInstance(
          id: 'home',
          service: ServiceKey.sabnzbd,
          url: 'https://home.example.com',
          credential: 'home-key',
        ),
        const ServiceInstance(
          id: 'seedbox',
          service: ServiceKey.sabnzbd,
          url: 'https://seedbox.example.com',
          credential: 'seedbox-key',
        ),
      ],
    );

    ProviderContainer containerOn(String lens, ReadClock clock) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => settings),
          initialActiveInstancesProvider.overrideWithValue({
            ServiceKey.sabnzbd: lens,
          }),
          readClockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('files the read under the connection the lens was on', () {
      final clock = ReadClock(now: () => DateTime(2026, 10, 12, 9));
      final noted = Provider<void Function()>(
        (ref) => ref.queueReadNoter(ServiceKey.sabnzbd),
      );
      final container = containerOn('seedbox', clock);

      container.read(noted)();

      expect(clock.at(queueReadKey(ServiceKey.sabnzbd, 'seedbox')), isNotNull);
      expect(clock.at(queueReadKey(ServiceKey.sabnzbd, 'home')), isNull);
    });

    test('notes nothing until the returned call is made', () {
      final clock = ReadClock();
      final noted = Provider<void Function()>(
        (ref) => ref.queueReadNoter(ServiceKey.sabnzbd),
      );
      final container = containerOn('home', clock);

      container.read(noted);

      expect(clock.at(queueReadKey(ServiceKey.sabnzbd, 'home')), isNull);
    });

    test('still notes after its provider was disposed', () {
      // A request in flight when the provider is invalidated lands on a
      // disposed ref; the read still came back and is still noted.
      final clock = ReadClock();
      final noted = Provider.autoDispose<void Function()>(
        (ref) => ref.queueReadNoter(ServiceKey.sabnzbd),
      );
      final container = containerOn('home', clock);
      final subscription = container.listen(noted, (_, _) {});
      final note = subscription.read();

      subscription.close();
      container.invalidate(noted);
      note();

      expect(clock.at(queueReadKey(ServiceKey.sabnzbd, 'home')), isNotNull);
    });
  });
}
