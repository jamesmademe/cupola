import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('SilenceClock', () {
    test('knows no silence for a connection nothing has probed', () {
      expect(SilenceClock().since('sabnzbd:home'), isNull);
    });

    test('keeps the first time a connection did not answer', () {
      var now = DateTime(2026, 10, 12, 20, 41);
      final clock = SilenceClock(now: () => now);

      clock.noteSilent('sabnzbd:home');
      now = DateTime(2026, 10, 12, 20, 47);
      clock.noteSilent('sabnzbd:home');
      now = DateTime(2026, 10, 12, 20, 55);
      clock.noteSilent('sabnzbd:home');

      expect(
        clock.since('sabnzbd:home'),
        DateTime(2026, 10, 12, 20, 41),
        reason: 'a Retry that fails again is the same silence',
      );
      expect(clock.now(), DateTime(2026, 10, 12, 20, 55));
    });

    test('keeps a time it was given', () {
      final clock = SilenceClock();
      final at = DateTime(2026, 10, 12, 20, 41);

      clock.noteSilent('sabnzbd:home', at);

      expect(clock.since('sabnzbd:home'), at);
    });

    test('ends the silence when the connection answers', () {
      final clock = SilenceClock()..noteSilent('sabnzbd:home');

      clock.noteAnswered('sabnzbd:home');

      expect(clock.since('sabnzbd:home'), isNull);
    });

    test('starts a new silence, from its own first time, after an answer', () {
      var now = DateTime(2026, 10, 12, 20, 41);
      final clock = SilenceClock(now: () => now)..noteSilent('sabnzbd:home');
      clock.noteAnswered('sabnzbd:home');

      now = DateTime(2026, 10, 12, 21, 30);
      clock.noteSilent('sabnzbd:home');

      expect(clock.since('sabnzbd:home'), DateTime(2026, 10, 12, 21, 30));
    });

    test('keeps each connection apart', () {
      final clock = SilenceClock();
      final home = DateTime(2026, 10, 12, 20, 41);

      clock.noteSilent('sabnzbd:home', home);
      clock.noteSilent('sabnzbd:seedbox', DateTime(2026, 10, 12, 21));
      clock.noteAnswered('sabnzbd:seedbox');

      expect(clock.since('sabnzbd:home'), home);
      expect(clock.since('sabnzbd:seedbox'), isNull);
      expect(clock.since('nzbget:home'), isNull);
    });

    group('a probe', () {
      test('that did not answer starts a silence', () {
        final clock = SilenceClock();

        clock.noteProbe('radarr:a', ServiceFailureReason.unreachable);

        expect(clock.since('radarr:a'), isNotNull);
      });

      test('that did not answer again keeps the first', () {
        var now = DateTime(2026, 10, 12, 20, 41);
        final clock = SilenceClock(now: () => now);
        clock.noteProbe('radarr:a', ServiceFailureReason.unreachable);

        now = DateTime(2026, 10, 12, 20, 50);
        clock.noteProbe('radarr:a', ServiceFailureReason.unreachable);

        expect(clock.since('radarr:a'), DateTime(2026, 10, 12, 20, 41));
      });

      test('that succeeded ends it', () {
        final clock = SilenceClock()
          ..noteProbe('radarr:a', ServiceFailureReason.unreachable);

        clock.noteProbe('radarr:a', null);

        expect(clock.since('radarr:a'), isNull);
      });

      // A server reached that never replied said nothing either: its
      // silence runs as a dark one's does.
      test('that was reached and never replied keeps it running', () {
        final clock = SilenceClock(now: () => DateTime(2026, 10, 13, 9, 53))
          ..noteProbe('radarr:a', ServiceFailureReason.timeout);

        expect(clock.since('radarr:a'), DateTime(2026, 10, 13, 9, 53));
      });

      // An answer that says something is wrong is still an answer: the box is
      // up, and a clock that says it has been dark would send the person to
      // check a cable.
      for (final reason in ServiceFailureReason.values.where(
        (reason) =>
            !failureDidNotAnswer(reason) &&
            reason != ServiceFailureReason.timeout,
      )) {
        test('that failed as ${reason.name} ends it', () {
          final clock = SilenceClock()
            ..noteProbe('radarr:a', ServiceFailureReason.unreachable);

          clock.noteProbe('radarr:a', reason);

          expect(clock.since('radarr:a'), isNull);
        });

        test('that failed as ${reason.name} starts none', () {
          final clock = SilenceClock();

          clock.noteProbe('radarr:a', reason);

          expect(clock.since('radarr:a'), isNull);
        });
      }
    });
  });

  group('silenceKey', () {
    test('names the service and the connection', () {
      expect(silenceKey(ServiceKey.sabnzbd, 'home'), 'sabnzbd:home');
      expect(
        silenceKey(ServiceKey.sabnzbd, 'home'),
        isNot(silenceKey(ServiceKey.sabnzbd, 'seedbox')),
      );
      expect(
        silenceKey(ServiceKey.sabnzbd, 'home'),
        isNot(silenceKey(ServiceKey.nzbget, 'home')),
      );
    });
  });

  group('silenceClockProvider', () {
    test('reads the time the read clock reads', () {
      var now = DateTime(2026, 10, 12, 9);
      final container = ProviderContainer(
        overrides: [
          readClockProvider.overrideWithValue(ReadClock(now: () => now)),
        ],
      );
      addTearDown(container.dispose);

      final clock = container.read(silenceClockProvider);
      clock.noteSilent('sabnzbd:home');
      now = DateTime(2026, 10, 12, 9, 6);

      expect(clock.since('sabnzbd:home'), DateTime(2026, 10, 12, 9));
      expect(clock.now(), DateTime(2026, 10, 12, 9, 6));
    });

    test(
      'is not the read clock: a silence is no read, and a read no answer',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(silenceClockProvider).noteSilent('sabnzbd:home');
        container.read(readClockProvider).note('sabnzbd:home');

        expect(
          container.read(silenceClockProvider).since('sabnzbd:home'),
          isNotNull,
        );
        container.read(silenceClockProvider).noteAnswered('sabnzbd:home');
        expect(
          container.read(readClockProvider).at('sabnzbd:home'),
          isNotNull,
          reason: 'a probe that answers does not touch when a queue was read',
        );
      },
    );

    test('is one clock for the life of the app', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(silenceClockProvider),
        same(container.read(silenceClockProvider)),
      );
    });
  });
}
