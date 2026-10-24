@Tags(['e2e'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

import 'seed_writer.dart';

/// A profile is a replacement, not a merge, and the app itself has to prove
/// it on the stores it will use: SharedPreferences, the Keychain and the App
/// Group. One process applies P1, then P2, then P1 again. A key, a session,
/// a pin or a persisted choice that survived a replacement fails the readback
/// inside [replaceAppConfiguration] before this test can pass.
///
/// Run it with the same testlab build settings as `seed_app.dart`:
///
/// ```bash
/// flutter test integration_test/testlab/seed_replacement.dart -d macos \
///   --tags e2e --run-skipped --no-uninstall \
///   --dart-define=CUPOLA_TESTLAB=1 ...
/// ```
const _controlUrl = String.fromEnvironment('CUPOLA_TESTLAB_CONTROL_URL');
const _controlToken = String.fromEnvironment('CUPOLA_TESTLAB_CONTROL_TOKEN');
const _bundleId = testlabBundleId;
const _keychainService = String.fromEnvironment(
  'CUPOLA_TESTLAB_KEYCHAIN_SERVICE',
);
const _appGroup = String.fromEnvironment(
  'CUPOLA_TESTLAB_APP_GROUP',
  defaultValue: 'group.com.matthwlabs.cupola.testlab',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P1 to P2 to P1 replaces every store', (tester) async {
    if (_controlUrl.isEmpty || _controlToken.isEmpty) {
      fail('The lab did not compile its control API into this build.');
    }
    await requireTestlabIdentity(
      bundleId: _bundleId,
      keychainService: _keychainService,
      appGroup: _appGroup,
    );

    final prefs = await SharedPreferences.getInstance();
    final secure = createSecureSettingsStore();
    for (final profile in const ['P1', 'P2', 'P1']) {
      final document = await fetchProfile(
        controlUrl: _controlUrl,
        controlToken: _controlToken,
        profile: profile,
      );
      final settings = await replaceAppConfiguration(
        document: document,
        prefs: prefs,
        secure: secure,
        expectedProfile: profile,
        expectedBundleId: _bundleId,
      );
      expect(settings.instances, isNotEmpty);
      debugPrint(
        '[testlab] replaced profile=$profile '
        'connections=${settings.instances.length}: '
        '${settings.instances.map((instance) => instance.id).join(', ')}',
      );
    }
  });
}
