import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

const _second = ServiceInstance(
  id: 'sonarr-2222222',
  service: ServiceKey.sonarr,
  label: '2',
  url: 'https://second.lan:8989',
  credential: 'key-2',
);

/// A queue row that belongs to [instanceId].
///
/// Both rows carry queue id **7** on purpose: \*arr queue ids are per server and
/// every server numbers from one, so an id alone cannot say which download this
/// is. That is the whole reason a write has to be routed by the row's
/// connection — sending id 7 to the wrong Sonarr removes somebody else's
/// download and reports success.
GlobalActivityItem _row(String instanceId, String title) => GlobalActivityItem(
  kind: GlobalActivityKind.queue,
  service: ServiceKey.sonarr,
  serviceType: ServiceType.series,
  instanceId: instanceId,
  instanceLabel: instanceId,
  title: title,
  subtitle: 'Release.Name',
  status: const MediaStatusInfo(
    availability: MediaAvailability.unknown,
    labelOverride: 'Downloading',
  ),
  raw: const {
    'id': 7,
    'title': 'Release.Name',
    'series': {'title': 'A Series'},
  },
);

Future<List<Override>> _settings() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_second),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required ProviderContainer container,
  required GlobalActivityItem item,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: GlobalActivityItemTile(item: item)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the row's detail sheet and takes it through Remove from queue.
Future<void> _removeFromQueue(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove from queue'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a write on a row the lens is NOT on reaches that row\'s server',
    (tester) async {
      final lens = _RecordingSonarrService();
      final other = _RecordingSonarrService();

      final container = ProviderContainer(
        overrides: [
          ...await _settings(),
          // The lens stays on the FIRST connection deliberately: if the action
          // still resolves through the lens this test passes nothing, it fails.
          sonarrServiceProvider.overrideWith((ref) => lens),
          sonarrServiceForProvider(_second.id).overrideWithValue(other),
        ],
      );
      addTearDown(container.dispose);

      await _pumpRow(
        tester,
        container: container,
        item: _row(_second.id, 'On the second server'),
      );
      await _removeFromQueue(tester, 'On the second server');

      expect(
        other.removed,
        [7],
        reason: 'the row belongs to the second Sonarr, so the write goes there',
      );
      expect(
        lens.removed,
        isEmpty,
        reason: 'the lens is a viewing choice, not the address of a write',
      );
    },
  );

  testWidgets('and a row on the lens still reaches the lens', (tester) async {
    final lens = _RecordingSonarrService();
    final other = _RecordingSonarrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => lens),
        sonarrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row('sonarr', 'On the first server'),
    );
    await _removeFromQueue(tester, 'On the first server');

    expect(lens.removed, [7]);
    expect(other.removed, isEmpty);
  });

  testWidgets('the routing follows the row after the lens moves', (
    tester,
  ) async {
    // The mirror image, so a "always send it to the non-lens one" implementation
    // cannot pass: here the lens sits on the SECOND connection and the row
    // belongs to the first.
    final first = _RecordingSonarrService();
    final second = _RecordingSonarrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => second),
        sonarrServiceForProvider('sonarr').overrideWithValue(first),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(activeInstancesProvider.notifier)
        .select(ServiceKey.sonarr, _second.id);

    await _pumpRow(
      tester,
      container: container,
      item: _row('sonarr', 'On the first server'),
    );
    await _removeFromQueue(tester, 'On the first server');

    expect(first.removed, [7]);
    expect(second.removed, isEmpty);
  });

  // Three separate call sites pass the row's connection, so three separate
  // chances to forget one. The resolution is shared; the argument is not.
  testWidgets('blocklist-and-retry goes to the row\'s server too', (
    tester,
  ) async {
    final lens = _RecordingSonarrService();
    final other = _RecordingSonarrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => lens),
        sonarrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row(_second.id, 'On the second server'),
    );

    await tester.tap(find.text('On the second server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocklist and search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Blocklist and search'));
    await tester.pumpAndSettle();

    expect(other.removed, [7]);
    expect(lens.removed, isEmpty);
  });

  testWidgets('and so does un-blocklisting', (tester) async {
    final lens = _RecordingSonarrService();
    final other = _RecordingSonarrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => lens),
        sonarrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: GlobalActivityItem(
        kind: GlobalActivityKind.blocklist,
        service: ServiceKey.sonarr,
        serviceType: ServiceType.series,
        instanceId: _second.id,
        instanceLabel: _second.label,
        title: 'A blocked release',
        subtitle: 'Release.Name',
        status: const MediaStatusInfo(
          availability: MediaAvailability.unknown,
          labelOverride: 'Blocked',
        ),
        raw: const {'id': 7, 'sourceTitle': 'Release.Name'},
      ),
    );

    // Through the row's overflow menu: the blocklist detail sheet carries no
    // action buttons, so the menu is the only way in.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from blocklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(other.unblocked, [7]);
    expect(lens.unblocked, isEmpty);
  });

  testWidgets('a row names the connection it came from', (tester) async {
    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        sonarrServiceProvider.overrideWith((ref) => _RecordingSonarrService()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row(_second.id, 'On the second server'),
    );

    expect(find.text(_second.id.toUpperCase()), findsOneWidget);
  });

  testWidgets('and grows no badge when the row carries no label', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: activityServiceKeys),
        sonarrServiceProvider.overrideWith((ref) => _RecordingSonarrService()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: GlobalActivityItem(
        kind: GlobalActivityKind.queue,
        service: ServiceKey.sonarr,
        serviceType: ServiceType.series,
        instanceId: 'sonarr',
        title: 'The only Sonarr',
        subtitle: 'Release.Name',
        status: const MediaStatusInfo(
          availability: MediaAvailability.unknown,
          labelOverride: 'Downloading',
        ),
        raw: const {'id': 7, 'title': 'Release.Name'},
      ),
    );

    expect(find.text('SONARR'), findsNothing);
  });
}

class _RecordingSonarrService extends FakeSonarrService {
  final List<int> removed = [];
  final List<int> unblocked = [];

  @override
  Future<void> deleteBlocklistItem(int id) async {
    unblocked.add(id);
  }

  @override
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) async {
    removed.add(id);
  }
}
