@Tags(['e2e'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

import 'seed_writer.dart';

/// The app's configuration for a profile, saved with the app's own code.
///
/// The lab writes the configuration of a profile into its state directory,
/// in the app's own storage: the addresses, the names and the roster in
/// `SharedPreferences`, the keys, the passwords, the tokens and the sessions
/// in the secure storage, with the keys `SettingsService` derives from the id
/// of every connection. This entry point replaces that state, using the app's
/// own cleanup and reader, so the app on the device or in the simulator reads
/// the lab's real connections and proves the readback.
///
/// Nothing is presumed about the host's environment: the profile and the
/// control API arrive as `--dart-define`, which the build compiles into the
/// app process. The bundle is a literal ([testlabBundleId]), so no define can
/// point the seed at the house's app. Before the first write the running
/// container must prove it is the testlab bundle; the plain app refuses.
///
/// Run it with the lab's profile:
///
/// ```bash
/// flutter test integration_test/testlab/seed_app.dart -d <device> \
///   --tags e2e --run-skipped \
///   --dart-define=CUPOLA_TESTLAB=1 \
///   --dart-define=CUPOLA_TESTLAB_PROFILE=P1 \
///   --dart-define=CUPOLA_TESTLAB_CONTROL_URL=http://127.0.0.1:8799 \
///   --dart-define=CUPOLA_TESTLAB_CONTROL_TOKEN=...
/// ```
const _profile = String.fromEnvironment('CUPOLA_TESTLAB_PROFILE');
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

  testWidgets('the configuration of a profile reaches the app', (tester) async {
    if (_profile.isEmpty || _controlUrl.isEmpty || _controlToken.isEmpty) {
      fail(
        'The lab did not compile the profile into this build. Pass '
        'CUPOLA_TESTLAB_PROFILE, CUPOLA_TESTLAB_CONTROL_URL and '
        'CUPOLA_TESTLAB_CONTROL_TOKEN as --dart-define.',
      );
    }

    // The first gate: the app must be the testlab build, in its own container,
    // with the testlab keychain and App Group, before anything is read into
    // the stores or wiped.
    await requireTestlabIdentity(
      bundleId: _bundleId,
      keychainService: _keychainService,
      appGroup: _appGroup,
    );

    final document = await fetchProfile(
      controlUrl: _controlUrl,
      controlToken: _controlToken,
      profile: _profile,
    );
    final prefs = await SharedPreferences.getInstance();
    final secure = createSecureSettingsStore();
    final settings = await replaceAppConfiguration(
      document: document,
      prefs: prefs,
      secure: secure,
      expectedProfile: _profile,
      expectedBundleId: _bundleId,
    );

    // The names, never the secrets.
    debugPrint(
      '[testlab] applied profile=$_profile bundle=$_bundleId '
      'connections=${settings.instances.length}: '
      '${settings.instances.map((instance) => instance.id).join(', ')}',
    );
    expect(settings.instances, isNotEmpty);
    expect(document['profile'], _profile);
    expect(document['bundleId'], _bundleId);
  });
}
