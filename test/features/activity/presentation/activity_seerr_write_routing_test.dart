import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

const _second = ServiceInstance(
  id: 'seerr-2222222',
  service: ServiceKey.seerr,
  label: 'Anime',
  url: 'https://second.lan:5055',
  credential: 'key-2',
);

/// A pending request that belongs to [instanceId].
///
/// **Both connections carry request id 42.** Seerr numbers its requests per
/// instance, so the id alone cannot say which request this is: approve 42 on
/// the wrong server and somebody else's request goes to their \*arr, with a
/// success toast. That is the whole reason a write is routed by the row's
/// connection rather than by the lens.
GlobalActivityItem _row(String instanceId, String title) => GlobalActivityItem(
  kind: GlobalActivityKind.request,
  service: ServiceKey.seerr,
  serviceType: ServiceType.discover,
  instanceId: instanceId,
  instanceLabel: instanceId,
  title: title,
  subtitle: 'Matt · Movie',
  status: const MediaStatusInfo(
    availability: MediaAvailability.unknown,
    labelOverride: 'Pending',
  ),
  request: SeerrRequest(
    id: 42,
    status: RequestStatus.pendingApproval,
    type: 'movie',
    createdAt: '2026-08-01T10:00:00.000Z',
    media: RequestMedia(id: 1, tmdbId: 1, mediaType: 'movie', title: title),
  ),
);

Future<List<Override>> _settings() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_second),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required ProviderContainer container,
  required GlobalActivityItem item,
  List<String>? pushed,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: GlobalActivityItemTile(item: item)),
      ),
      GoRoute(
        path: '/activity/:type',
        builder: (context, state) {
          pushed?.add(state.uri.toString());
          return const Scaffold(body: Text('destination'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Takes the row's overflow menu through Approve.
Future<void> _approve(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Approve request'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
  await tester.pumpAndSettle();
}

Future<void> _decline(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Decline request'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an approval on a row the lens is NOT on reaches that row\'s Seerr',
    (tester) async {
      final lens = _RecordingSeerrService();
      final other = _RecordingSeerrService();

      final container = ProviderContainer(
        overrides: [
          ...await _settings(),
          // The lens stays on the FIRST connection deliberately: if approve still
          // resolves through the lens this test fails rather than passing blind.
          seerrServiceProvider.overrideWith((ref) => lens),
          seerrServiceForProvider(_second.id).overrideWithValue(other),
        ],
      );
      addTearDown(container.dispose);

      await _pumpRow(
        tester,
        container: container,
        item: _row(_second.id, 'On the second Seerr'),
      );
      await _approve(tester);

      expect(
        other.approved,
        [42],
        reason: 'the row belongs to the second Seerr, so the write goes there',
      );
      expect(
        lens.approved,
        isEmpty,
        reason: 'the lens is a viewing choice, not the address of a write',
      );
    },
  );

  testWidgets('and a row on the lens still reaches the lens', (tester) async {
    final lens = _RecordingSeerrService();
    final other = _RecordingSeerrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row('seerr', 'On the first Seerr'),
    );
    await _approve(tester);

    expect(lens.approved, [42]);
    expect(other.approved, isEmpty);
  });

  // The mirror image, so an "always send it to the other one" implementation
  // cannot pass either: the lens sits on the SECOND connection and the row
  // belongs to the first.
  testWidgets('the routing follows the row after the lens moves', (
    tester,
  ) async {
    final first = _RecordingSeerrService();
    final second = _RecordingSeerrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => second),
        seerrServiceForProvider('seerr').overrideWithValue(first),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(activeInstancesProvider.notifier)
        .select(ServiceKey.seerr, _second.id);

    await _pumpRow(
      tester,
      container: container,
      item: _row('seerr', 'On the first Seerr'),
    );
    await _approve(tester);

    expect(first.approved, [42]);
    expect(second.approved, isEmpty);
  });

  testWidgets('a decline goes to the row\'s Seerr too', (tester) async {
    final lens = _RecordingSeerrService();
    final other = _RecordingSeerrService();

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row(_second.id, 'On the second Seerr'),
    );
    await _decline(tester);

    expect(other.declined, [42]);
    expect(lens.declined, isEmpty);
  });

  // The navigation half of the same problem: a request row opens the requests
  // list, and a list resolved through the lens would show the FIRST Seerr's
  // requests under a row that came off the second.
  testWidgets('the row opens the requests list of its own connection', (
    tester,
  ) async {
    final pushed = <String>[];
    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => _RecordingSeerrService()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row(_second.id, 'On the second Seerr'),
      pushed: pushed,
    );

    await tester.tap(find.text('On the second Seerr'));
    await tester.pumpAndSettle();

    expect(pushed, ['/activity/discover?i=${_second.id}']);
  });

  testWidgets('and carries no connection when the row has none', (
    tester,
  ) async {
    final pushed = <String>[];
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: activityServiceKeys),
        seerrServiceProvider.overrideWith((ref) => _RecordingSeerrService()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpRow(
      tester,
      container: container,
      item: _row('', 'The only Seerr'),
      pushed: pushed,
    );

    await tester.tap(find.text('The only Seerr'));
    await tester.pumpAndSettle();

    expect(pushed, ['/activity/discover']);
  });
}

class _RecordingSeerrService extends FakeSeerrService {
  final List<int> approved = [];
  final List<int> declined = [];
  final List<int> deleted = [];

  @override
  Future<List<SeerrRequest>> getRequests() async => const [];

  @override
  Future<void> approveRequest(int requestId) async {
    approved.add(requestId);
  }

  @override
  Future<void> declineRequest(int requestId) async {
    declined.add(requestId);
  }

  @override
  Future<void> deleteRequest(int requestId) async {
    deleted.add(requestId);
  }
}
