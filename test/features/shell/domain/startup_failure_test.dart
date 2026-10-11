/// A start that stops is a failure for the step it reached, in words that name
/// the platform's store, and never a window left black.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_service.dart'
    show SecureStorageUnavailable;
import 'package:cupola/features/shell/domain/startup_failure.dart';

StartupFailure _keychain(TargetPlatform platform, {Object? error}) =>
    StartupFailure(
      step: StartupStep.connections,
      error:
          error ??
          PlatformException(
            code: '-25308',
            message: 'User interaction is not allowed.',
          ),
      platform: platform,
    );

void main() {
  group('attemptStartup', () {
    test('a boot that finishes is ready with its value', () async {
      final outcome = await attemptStartup((reach) async {
        reach(StartupStep.connections);
        return 42;
      });
      expect(outcome, isA<StartupReady<int>>());
      expect((outcome as StartupReady<int>).value, 42);
    });

    test('a throw is a failure of the step it was in', () async {
      final outcome = await attemptStartup<int>((reach) async {
        reach(StartupStep.preferences);
        await Future<void>.value();
        reach(StartupStep.connections);
        throw PlatformException(code: '-34018');
      });
      final failure = (outcome as StartupFailed<int>).failure;
      expect(failure.step, StartupStep.connections);
      expect(failure.error, isA<PlatformException>());
    });

    test(
      'a boot that never answers is a failure once the limit passes',
      () async {
        final outcome = await attemptStartup<int>(
          (reach) => Completer<int>().future,
          limit: const Duration(milliseconds: 20),
        );
        final failure = (outcome as StartupFailed<int>).failure;
        expect(failure.timedOut, isTrue);
        expect(failure.step, StartupStep.preferences);
      },
    );

    test('the limit leaves room for a cold Keychain', () {
      expect(startupLimit, const Duration(seconds: 20));
    });
  });

  group('the words', () {
    test('a refused read names the store of each platform', () {
      expect(
        _keychain(TargetPlatform.macOS).headline,
        "Cupola could not read your saved connections",
      );
      expect(
        _keychain(TargetPlatform.macOS).sentence,
        "The Keychain didn't hand them over.",
      );
      expect(
        _keychain(TargetPlatform.iOS).sentence,
        "The Keychain didn't hand them over.",
      );
      expect(
        _keychain(TargetPlatform.android).sentence,
        "Android's secure storage didn't hand them over.",
      );
      expect(
        _keychain(TargetPlatform.windows).sentence,
        "Windows Credential Manager didn't hand them over.",
      );
      expect(
        _keychain(TargetPlatform.linux).sentence,
        "The system keyring didn't hand them over. It may still be locked.",
      );
    });

    test('a read that never answered says so', () {
      expect(
        _keychain(TargetPlatform.macOS, error: TimeoutException(null)).sentence,
        "The Keychain hasn't answered.",
      );
      expect(
        _keychain(TargetPlatform.macOS, error: TimeoutException(null)).why,
        isNull,
      );
    });

    test(
      'Why? carries the platform\'s message and code, never its details',
      () {
        final failure = _keychain(
          TargetPlatform.macOS,
          error: PlatformException(
            code: '-25308',
            message: 'User interaction is not allowed.',
            details: 'secure_radarr_apiKey',
          ),
        );
        expect(failure.why, 'User interaction is not allowed. (-25308)');
        expect(failure.why, isNot(contains('secure_')));
      },
    );

    test('an error the step does not explain is said behind Why? alone', () {
      final failure = StartupFailure(
        step: StartupStep.connections,
        error: StateError('bad state'),
      );
      expect(failure.sentence, isNull);
      expect(failure.why, contains('bad state'));
    });

    test('the settings file has its own headline', () {
      const failure = StartupFailure(
        step: StartupStep.preferences,
        error: 'boom',
      );
      expect(failure.headline, "Cupola could not open its settings");
    });
  });

  test('a store that will not even be emptied says what to start on Linux', () {
    expect(
      StartupFailure(
        step: StartupStep.forgettingKeys,
        error: PlatformException(code: 'x'),
        platform: TargetPlatform.linux,
      ).sentence,
      "The system keyring isn't answering. Start GNOME Keyring or KWallet, "
      'then retry.',
    );
    expect(
      StartupFailure(
        step: StartupStep.forgettingKeys,
        error: PlatformException(code: 'x'),
        platform: TargetPlatform.android,
      ).sentence,
      "Android's secure storage refused that too.",
    );
  });

  test(
    'every read refused is the store\'s failure, its first words behind Why?',
    () {
      final failure = StartupFailure(
        step: StartupStep.connections,
        error: SecureStorageUnavailable(
          PlatformException(code: '-34018', message: 'Missing entitlement.'),
        ),
        platform: TargetPlatform.macOS,
      );
      expect(failure.sentence, "The Keychain didn't hand them over.");
      expect(failure.why, 'Missing entitlement. (-34018)');
      expect(failure.canForget, isTrue);
    },
  );
}
