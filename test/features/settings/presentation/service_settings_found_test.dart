import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// A server another connection knows opens its form filled in: the address
/// proposed for this device, the key when the source gave one, the name it
/// goes by beside its service, and a line saying where it all came from.
void main() {
  const seerr = ServiceInstance(
    id: 'seerr',
    service: ServiceKey.seerr,
    url: 'http://seerr.lan:5055',
    credential: 'seerr-key',
  );
  const radarr = ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'http://nas.lan:7878',
    credential: 'radarr-key',
  );
  const fromSeerr = CandidateSource(
    service: ServiceKey.seerr,
    connectionId: 'seerr',
    url: 'http://seerr.lan:5055',
  );
  const fromProwlarr = CandidateSource(
    service: ServiceKey.prowlarr,
    connectionId: 'prowlarr',
    url: 'http://nas.lan:9696',
  );
  const fourK = ConnectionCandidate(
    service: ServiceKey.radarr,
    name: 'Radarr 4K',
    reportedUrl: 'http://nas.lan:7879',
    source: fromSeerr,
    apiKey: 'found-4k-key',
  );
  const sonarr = ConnectionCandidate(
    service: ServiceKey.sonarr,
    name: 'Sonarr',
    reportedUrl: 'http://nas.lan:8989',
    source: fromProwlarr,
  );

  Future<void> pump(
    WidgetTester tester, {
    required ServiceKey service,
    required String from,
    required String name,
    bool isNew = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureSettingsStoreProvider.overrideWithValue(
          FakeSecureSettingsStore(),
        ),
        initialSettingsProvider.overrideWithValue(
          const SettingsModel(instances: [seerr, radarr]),
        ),
        initialActiveInstancesProvider.overrideWithValue(const {}),
        knownCandidatesProvider.overrideWith(
          (ref, id) async => [
            if (id == 'seerr') fourK,
            if (id == 'prowlarr') sonarr,
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    // Tall enough that every field is built: the list builds lazily.
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ServiceSettingsScreen(
            service: service,
            isNew: isNew,
            foundFrom: from,
            foundName: name,
            certificateProber: (url, {pinnedFingerprint = ''}) async => null,
            localNetworkProbe: (raw, {timeout = Duration.zero}) async =>
                LocalNetworkAccess.unrestricted,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool holds(WidgetTester tester, String text) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .any((field) => field.controller.text == text);

  testWidgets('a server Seerr knows fills in its address, key and name', (
    tester,
  ) async {
    await pump(
      tester,
      service: ServiceKey.radarr,
      from: 'seerr',
      name: 'Radarr 4K',
      isNew: true,
    );

    expect(holds(tester, fourK.proposal!.url), isTrue);
    expect(holds(tester, fourK.apiKey!), isTrue);
    expect(holds(tester, '4K'), isTrue);
    expect(
      find.text(
        'Seerr knows this Radarr: its address and key are filled in. Test '
        'it, then save.',
      ),
      findsOneWidget,
    );
    // Filled in is not saved: leaving asks first.
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('Prowlarr gives no key: the address is filled in, the key is '
      'asked for', (tester) async {
    await pump(
      tester,
      service: ServiceKey.sonarr,
      from: 'prowlarr',
      name: 'Sonarr',
    );

    expect(holds(tester, sonarr.proposal!.url), isTrue);
    expect(
      find.text(
        'Prowlarr knows this Sonarr: its address is filled in. Paste its '
        'key, test it, then save.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a name the source no longer knows fills in nothing', (
    tester,
  ) async {
    await pump(
      tester,
      service: ServiceKey.radarr,
      from: 'seerr',
      name: 'Radarr UHD',
      isNew: true,
    );

    expect(holds(tester, fourK.proposal!.url), isFalse);
    expect(find.textContaining('knows this Radarr'), findsNothing);
  });
}
