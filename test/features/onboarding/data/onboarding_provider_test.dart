import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('showsWelcome', () {
    test('a first run with nothing set up', () {
      expect(
        showsWelcome(
          onboardingCompleted: false,
          settings: const SettingsModel(),
        ),
        isTrue,
      );
    });

    test('an instance with no address left is still nothing set up', () {
      // A secret the keychain kept after its address went: nothing anyone
      // could talk to, and the Home would draw itself at zero.
      expect(
        showsWelcome(
          onboardingCompleted: false,
          settings: const SettingsModel(
            instances: [
              ServiceInstance(
                id: 'radarr',
                service: ServiceKey.radarr,
                credential: 'left-behind',
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('not for a run cut short after its first connection', () {
      expect(
        showsWelcome(
          onboardingCompleted: false,
          settings: settingsWithServices([ServiceKey.seerr]),
        ),
        isFalse,
      );
    });

    test('not once the way in was finished, even with nothing left', () {
      // Every connection removed afterwards is the Home at zero, inside the
      // tabs, not a first run.
      expect(
        showsWelcome(
          onboardingCompleted: true,
          settings: const SettingsModel(),
        ),
        isFalse,
      );
    });
  });
}
