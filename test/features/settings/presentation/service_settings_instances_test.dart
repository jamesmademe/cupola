import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://nas.lan:7878',
  credential: 'key-4k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://nas.lan:7879',
  credential: 'key-hd',
);
const _lonely = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://nas.lan:8989',
  credential: 'key-sonarr',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required SettingsModel settings,
  ServiceKey service = ServiceKey.radarr,
  String? instanceId,
  bool isNew = false,
  Map<ServiceKey, String> lenses = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(settings),
      initialActiveInstancesProvider.overrideWithValue(lenses),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ServiceSettingsScreen(
          service: service,
          instanceId: instanceId,
          isNew: isNew,
          // Never reaches a socket in a widget test.
          certificateProber: (url, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: _nothingIsBlockingUs,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls to the destructive action, taps it and confirms.
Future<void> _removeThisConnection(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Remove Radarr'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Remove Radarr'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
  await tester.pumpAndSettle();
}

Future<LocalNetworkAccess> _nothingIsBlockingUs(
  String rawUrl, {
  Duration timeout = Duration.zero,
}) async => LocalNetworkAccess.unrestricted;

void main() {
  testWidgets('a lone connection is never asked for a name', (tester) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_lonely]),
      service: ServiceKey.sonarr,
    );

    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
  });

  testWidgets('the name field appears once there is something to tell apart', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
    );

    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
  });

  testWidgets('opens the connection it was asked for, not the first', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      instanceId: 'radarr-hd11111',
    );

    expect(find.text('HD'), findsOneWidget);
    expect(find.text('https://nas.lan:7879'), findsOneWidget);
  });

  testWidgets('an id belonging to another service is ignored', (tester) async {
    // Writing this form's fields onto a Sonarr would be silent corruption, so
    // the id is not trusted just because it resolves.
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd, _lonely]),
      instanceId: 'sonarr',
    );

    expect(find.text('4K'), findsOneWidget);
    expect(find.text('https://nas.lan:7878'), findsOneWidget);
  });

  testWidgets('adding another starts empty rather than editing the first', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK]),
      isNew: true,
    );

    expect(find.text('https://nas.lan:7878'), findsNothing);
    // One exists already, so this one has to be named.
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
  });

  testWidgets('lists the other connections and a way to add one', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
    );

    await tester.scrollUntilVisible(
      find.text('Add another Radarr'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Add another Radarr'), findsOneWidget);
    // The sibling is reachable from here; the one on screen is not repeated.
    expect(find.text('HD'), findsOneWidget);
  });

  testWidgets('refuses a name another connection already uses', (tester) async {
    await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      instanceId: 'radarr-hd11111',
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), '4K');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Another Radarr already uses that name'), findsOneWidget);
  });

  testWidgets('naming the second one names the first, from what differs', (
    tester,
  ) async {
    // The first connection has no label: it never needed one. Saving a second
    // makes it need one, and "Default" would name a role that moves rather
    // than a thing that does not.
    const nameless = ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://nas.lan:7878',
      credential: 'k',
    );
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [nameless]),
      isNew: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server URL'),
      'https://nas.lan:7879',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'API Key'), 'k2');
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'HD');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = container.read(currentSettingsProvider);
    expect(saved.instancesOf(ServiceKey.radarr), hasLength(2));
    // Same host, different port — so the port is what tells them apart.
    expect(saved.primaryOf(ServiceKey.radarr)?.label, '7878');
    expect(saved.instancesOf(ServiceKey.radarr).last.label, 'HD');
  });

  testWidgets('behind one reverse proxy the path is what differs', (
    tester,
  ) async {
    // Same host, same port, two paths — one proxy fronting both. Naming them by
    // hostname gave both "nas", which is what they have in COMMON, and it is
    // the deployment ADR-6 exists to serve: those two necessarily share a
    // single certificate pin, so the label is the only thing left to tell them
    // apart.
    const proxied = ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://nas.lan/radarr',
      credential: 'k',
    );
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [proxied]),
      isNew: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server URL'),
      'https://nas.lan/radarr4k',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'API Key'), 'k2');
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), '4K');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = container.read(currentSettingsProvider);
    expect(saved.primaryOf(ServiceKey.radarr)?.label, 'radarr');
    expect(saved.instancesOf(ServiceKey.radarr).last.label, '4K');
  });

  testWidgets('a derived name never collides with the typed one', (
    tester,
  ) async {
    // The field validator compares against siblings as they stand in the model,
    // where the one being derived still has an empty label — so a collision
    // introduced BY the derivation slipped through it entirely, and two
    // connections shared a name in the badge, the sheet and every chip.
    const nameless = ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://nas.lan:7878',
      credential: 'k',
    );
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [nameless]),
      isNew: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server URL'),
      'https://nas.lan:7879',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'API Key'), 'k2');
    // The exact string the derivation is about to produce for the sibling.
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), '7878');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = container.read(currentSettingsProvider);
    final labels = saved
        .instancesOf(ServiceKey.radarr)
        .map((i) => i.label)
        .toList();
    expect(labels, hasLength(2));
    expect(labels.toSet(), hasLength(2), reason: 'two names, not one twice');
    expect(labels, contains('7878'));
  });

  testWidgets('removing one connection leaves the other alone', (tester) async {
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      instanceId: 'radarr-hd11111',
    );

    await tester.scrollUntilVisible(
      find.text('Remove Radarr'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Remove Radarr'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    final saved = container.read(currentSettingsProvider);
    expect(saved.instancesOf(ServiceKey.radarr), hasLength(1));
    expect(saved.primaryOf(ServiceKey.radarr)?.id, 'radarr');
  });

  testWidgets('removing the connection being read forgets the lens', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd]),
      instanceId: 'radarr-hd11111',
      lenses: const {ServiceKey.radarr: 'radarr-hd11111'},
    );

    await _removeThisConnection(tester);

    // Resolution alone would have hidden this: `activeInstanceProvider` falls
    // back to the first instance when the id matches nothing, so the app looks
    // right. But the dead id stays on disk for good, and the day a badge or a
    // `?i=` NAMES it instead of resolving it, the app is carrying a pointer to
    // a server that was deleted.
    expect(
      container.read(activeInstancesProvider),
      isNot(contains(ServiceKey.radarr)),
    );
  });

  testWidgets('removing a different connection leaves the lens where it was', (
    tester,
  ) async {
    const third = ServiceInstance(
      id: 'radarr-third11',
      service: ServiceKey.radarr,
      label: 'Seedbox',
      url: 'https://box.lan:7880',
      credential: 'key-third',
    );
    final container = await _pump(
      tester,
      settings: const SettingsModel(instances: [_fourK, _hd, third]),
      instanceId: 'radarr-third11',
      lenses: const {ServiceKey.radarr: 'radarr-hd11111'},
    );

    await _removeThisConnection(tester);

    // The counterweight. Clearing unconditionally would send a lens
    // deliberately parked on HD back to 4K because the user tidied up a third
    // connection neither of them was reading.
    expect(
      container.read(activeInstancesProvider)[ServiceKey.radarr],
      'radarr-hd11111',
    );
  });

  test('a removed connection takes its own viewer, not the survivor\'s', () {
    // copyWithoutServiceExtras clears the viewer on *every* instance of the
    // service, so the removal path must not use it any more: dropping one
    // Jellyfin would have reset which person the other one reads through.
    const first = ServiceInstance(
      id: 'jellyfin',
      service: ServiceKey.jellyfin,
      url: 'https://a.lan',
      credential: 'k',
      viewerId: 'viewer-a',
    );
    const second = ServiceInstance(
      id: 'jellyfin-two1111',
      service: ServiceKey.jellyfin,
      url: 'https://b.lan',
      credential: 'k',
      viewerId: 'viewer-b',
    );
    const settings = SettingsModel(instances: [first, second]);

    final after = settings.copyWithoutInstance('jellyfin-two1111');

    expect(after.instancesOf(ServiceKey.jellyfin), hasLength(1));
    expect(after.jellyfinUserId, 'viewer-a');
  });

  test('SettingsService still round-trips what the form writes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FakeSecureSettingsStore();
    final service = SettingsService(prefs, store);

    await service.saveSettings(const SettingsModel(instances: [_fourK, _hd]));
    final reloaded = await service.loadSettings();

    expect(reloaded.instancesOf(ServiceKey.radarr).map((i) => i.label), [
      '4K',
      'HD',
    ]);
  });
}
