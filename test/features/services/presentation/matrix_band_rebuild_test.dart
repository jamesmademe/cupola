import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'https://radarr.lan:7878',
  credential: 'k',
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'k',
);

/// Sonarr's version: a summary that moves without moving the band's line.
final _sonarrVersion = StateProvider<String>((ref) => '4.0');

ServiceSummary _up(ServiceKey service, String version) => ServiceSummary(
  service: service,
  status: ServiceSummaryStatus.online,
  host: 'somewhere',
  version: version,
);

void main() {
  testWidgets('a summary that moves without changing the band line rebuilds '
      'only its own cell', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureSettingsStoreProvider.overrideWithValue(
          FakeSecureSettingsStore(),
        ),
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_radarr, _sonarr]),
        ),
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: _radarr.id,
        )).overrideWith((ref) async => _up(ServiceKey.radarr, '5.0')),
        instanceSummaryProvider((
          service: ServiceKey.sonarr,
          instanceId: _sonarr.id,
        )).overrideWith(
          (ref) async => _up(ServiceKey.sonarr, ref.watch(_sonarrVersion)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: ServiceMatrix()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = container.read(domainHealthLineProvider(ServiceDomain.media));
    expect(line, isNotNull, reason: 'the band says how its services are');

    final lines = <String?>[];
    container.listen(
      domainHealthLineProvider(ServiceDomain.media),
      (_, next) => lines.add(next),
    );
    final rebuilt = <ServiceKey>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final widget = element.widget;
      if (widget is ServiceMatrixCell) rebuilt.add(widget.service);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    container.read(_sonarrVersion.notifier).state = '4.1';
    await tester.pumpAndSettle();

    expect(
      container.read(domainHealthLineProvider(ServiceDomain.media)),
      line,
      reason: 'a new version is not news to the band',
    );
    expect(
      lines,
      isEmpty,
      reason: 'a probe read again keeps its verdict: no flash of checking',
    );
    expect(
      rebuilt,
      isNot(contains(ServiceKey.radarr)),
      reason: "Radarr's cell has nothing new to draw",
    );
  });
}
