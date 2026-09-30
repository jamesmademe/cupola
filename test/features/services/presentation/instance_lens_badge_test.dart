import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'k',
);
const _onlyOne = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'k',
);

Future<void> _pump(
  WidgetTester tester, {
  required SettingsModel settings,
  ServiceKey service = ServiceKey.radarr,
  Map<ServiceKey, String> lenses = const {},
  SharedPreferences? prefs,
  double barWidth = 390,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        initialActiveInstancesProvider.overrideWithValue(lenses),
        if (prefs != null) ...[
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureSettingsStoreProvider.overrideWithValue(
            FakeSecureSettingsStore(),
          ),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        // Mirrors how `_ServiceDashboardAppBar` composes it: a bare Row inside
        // a glass band. Deliberately *not* a Material `AppBar` — that merges
        // its title's semantics into one node, which would hide the badge's own
        // label behind the service name and make this harness disagree with the
        // screen it is standing in for.
        home: Scaffold(
          body: SizedBox(
            width: barWidth,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    service.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
                InstanceLensBadge(service: service),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders nothing while the service has one connection', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_onlyOne]),
      service: ServiceKey.sonarr,
    );

    expect(find.byType(InstanceLensBadge), findsOneWidget);
    // Present in the tree, but it draws nothing: the common install must not
    // pay a pixel for a distinction it does not have.
    expect(tester.getSize(find.byType(InstanceLensBadge)), const Size(0, 0));
  });

  testWidgets('shows the active label once there are two', (tester) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
    );

    expect(find.text('4K'), findsOneWidget);
  });

  testWidgets('shows the lens, not the first, when one is set', (tester) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      lenses: {ServiceKey.radarr: 'radarr-hd11111'},
    );

    expect(find.text('HD'), findsOneWidget);
    expect(find.text('4K'), findsNothing);
  });

  testWidgets('opens a sheet listing only this service, and switches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd, _onlyOne]),
      prefs: prefs,
    );

    await tester.tap(find.byType(InstanceLensBadge));
    await tester.pumpAndSettle();

    // The boundary that keeps this from becoming the picker the Portal
    // replaced: a lens sheet never offers another service.
    expect(find.text('Sonarr'), findsNothing);
    expect(find.text('HD'), findsOneWidget);

    await tester.tap(find.text('HD'));
    await tester.pumpAndSettle();

    expect(find.text('HD'), findsOneWidget, reason: 'the badge now reads HD');
    expect(find.text('4K'), findsNothing);
  });

  testWidgets('a media server gets a badge like everyone else', (tester) async {
    // Jellyfin, Plex and TrueNAS used to be exempt: their clients were built
    // from the flat first-instance projections, so a badge there would have
    // changed its own label and nothing else. All three go through
    // `watchTransport` now — including Jellyfin's chosen viewer, which is read
    // off the resolved instance rather than off `settings.jellyfinUserId` —
    // so the badge is honest and the exemption is gone.
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      settings: const SettingsModel(
        instances: [
          ServiceInstance(
            id: 'jellyfin',
            service: ServiceKey.jellyfin,
            label: 'Home',
            url: 'https://home.lan:8096',
            credential: 'k',
          ),
          ServiceInstance(
            id: 'jellyfin-away11',
            service: ServiceKey.jellyfin,
            label: 'Away',
            url: 'https://away.lan:8096',
            credential: 'k',
          ),
        ],
      ),
    );

    expect(
      find.text('Home'),
      findsOneWidget,
      reason: 'two Jellyfin, so the badge names the one being read',
    );
  });

  testWidgets('a connection with no address is not offered as a lens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await _pump(
      tester,
      settings: const SettingsModel(
        instances: [
          _fourK,
          _hd,
          // Named but never finished: the state a form is in between "Add
          // another Radarr" and typing the address.
          ServiceInstance(
            id: 'radarr-blank11',
            service: ServiceKey.radarr,
            label: 'Half done',
          ),
        ],
      ),
      prefs: prefs,
    );

    await tester.tap(find.byType(InstanceLensBadge));
    await tester.pumpAndSettle();

    expect(find.text('HD'), findsOneWidget);
    // `select` persists, so offering this row is offering to point the whole
    // app at nothing — and to have it come back up that way tomorrow.
    expect(find.text('Half done'), findsNothing);
    expect(find.text('2 connections. Pick the one to read.'), findsNothing);
    expect(find.text('Two connections. Pick the one to read.'), findsOneWidget);
  });

  testWidgets('the choice is remembered for the next launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      prefs: prefs,
    );
    await tester.tap(find.byType(InstanceLensBadge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HD'));
    await tester.pumpAndSettle();

    expect(prefs.getString('active_instances'), contains('radarr-hd11111'));
  });

  testWidgets('the service name yields before the badge does', (tester) async {
    // "Nginx Proxy Manager" is the longest title in the registry, and this is
    // the case that used to overflow the Row outright — the title had no
    // Flexible, no maxLines and no overflow, and the text scaler is opt-in per
    // call site rather than global.
    const npm = ServiceInstance(
      id: 'npm',
      service: ServiceKey.nginxProxyManager,
      label: 'Casa',
      url: 'https://nas.lan:81',
      credential: 'k',
    );
    const npmTwo = ServiceInstance(
      id: 'npm-second1',
      service: ServiceKey.nginxProxyManager,
      label: 'Ufficio',
      url: 'https://office.lan:81',
      credential: 'k',
    );

    await _pump(
      tester,
      settings: const SettingsModel(instances: [npm, npmTwo]),
      service: ServiceKey.nginxProxyManager,
      barWidth: 240,
    );

    expect(tester.takeException(), isNull);
    // The badge kept its whole label; the title is the one that gave way.
    expect(find.text('Casa'), findsOneWidget);
  });

  testWidgets('announces itself as the lens, not as a service switcher', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
    );

    expect(
      find.bySemanticsLabel('Lens: 4K'),
      findsOneWidget,
      reason: 'the Portal is what switches services; this switches connections',
    );
    handle.dispose();
  });
}
