/// The Requests view reads, and writes to, the connection its address names:
/// `/activity/requests?i=<connection>`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
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

Future<List<Override>> _settings() async => [
  ...await settingsScopeOverrides(
    configured: const [ServiceKey.seerr],
    customize: (settings) => settings.copyWithInstance(_second),
  ),
  // A page on its own clock would leave timers behind the test.
  activityLivePollProvider.overrideWith((ref, tab) {}),
];

SeerrRequest _request(
  int id,
  String title, {
  RequestStatus status = RequestStatus.pendingApproval,
}) => SeerrRequest(
  id: id,
  status: status,
  type: 'movie',
  createdAt: '2026-08-01T10:00:00.000Z',
  media: RequestMedia(id: id, tmdbId: id, mediaType: 'movie', title: title),
);

Future<void> _pump(
  WidgetTester tester, {
  required ProviderContainer container,
  String? instanceId,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ActivityPage(tab: ActivityTab.requests, requestsOf: instanceId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // A request row in the page opens this list; if the list resolves through
  // the lens, a row that came off the second Seerr opens the first Seerr's
  // requests: the defect moved rather than closed.
  testWidgets('the list shows the connection it was opened for', (
    tester,
  ) async {
    final lens = _RequestsSeerrService([_request(1, 'From the first')]);
    final other = _RequestsSeerrService([_request(1, 'From the second')]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: _second.id);

    expect(find.text('From the second'), findsOneWidget);
    expect(find.text('From the first'), findsNothing);
  });

  testWidgets('a row says the day as the app says dates', (tester) async {
    // 1 August 2026 is a Saturday. The sortable 2026-08-01 is the dense
    // feed's voice, and the year only appears when it is another year.
    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith(
          (ref) => _RequestsSeerrService([_request(1, 'From the first')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container);

    expect(find.textContaining('Sat 1 Aug'), findsOneWidget);
    expect(find.textContaining('2026-08-01'), findsNothing);
  });

  testWidgets('with no connection named it reads every one, each row naming '
      'its own', (tester) async {
    final lens = _RequestsSeerrService([_request(1, 'From the first')]);
    final other = _RequestsSeerrService([_request(1, 'From the second')]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container);

    expect(find.text('From the first'), findsOneWidget);
    expect(find.text('From the second'), findsOneWidget);
    expect(find.textContaining('Seerr Anime'), findsOneWidget);
  });

  // A link outlives the connection it names: the user opens a request row,
  // deletes that Seerr in Settings, then comes back to the page from history
  // or a deep link. The list reads every Seerr, as a link naming none does;
  // handing the dead id to it would print "not configured" for a server that
  // is up.
  testWidgets('a link naming a connection that is gone reads every one', (
    tester,
  ) async {
    final lens = _RequestsSeerrService([_request(1, 'From the first')]);
    final other = _RequestsSeerrService([_request(1, 'From the second')]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: 'seerr-deleted');

    expect(find.text('From the first'), findsOneWidget);
    expect(find.textContaining('not configured'), findsNothing);
  });

  // Every write on this list is keyed by a per-instance request id too.
  testWidgets('a delete on this list goes to the connection it belongs to', (
    tester,
  ) async {
    const approved = RequestStatus.approved;
    final lens = _RequestsSeerrService([
      _request(42, 'From the first', status: approved),
    ]);
    final other = _RequestsSeerrService([
      _request(42, 'From the second', status: approved),
    ]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: _second.id);

    // Delete request is on the row's long press.
    await tester.longPress(find.text('From the second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete request'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
    await tester.pumpAndSettle();

    expect(other.deleted, [42]);
    expect(lens.deleted, isEmpty);
  });

  testWidgets('and so does an approval', (tester) async {
    final lens = _RequestsSeerrService([_request(42, 'From the first')]);
    final other = _RequestsSeerrService([_request(42, 'From the second')]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: _second.id);

    await tester.tap(find.byTooltip('Approve From the second'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
    await tester.pumpAndSettle();

    expect(other.approved, [42]);
    expect(lens.approved, isEmpty);
  });

  testWidgets('and so does a decline', (tester) async {
    final lens = _RequestsSeerrService([_request(42, 'From the first')]);
    final other = _RequestsSeerrService([_request(42, 'From the second')]);

    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith((ref) => lens),
        seerrServiceForProvider(_second.id).overrideWithValue(other),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: _second.id);

    await tester.tap(find.byTooltip('Decline From the second'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
    await tester.pumpAndSettle();

    expect(other.declined, [42]);
    expect(lens.declined, isEmpty);
  });
}

class _RequestsSeerrService extends FakeSeerrService {
  _RequestsSeerrService(this.requests);

  final List<SeerrRequest> requests;
  final List<int> approved = [];
  final List<int> declined = [];
  final List<int> deleted = [];

  @override
  Future<List<SeerrRequest>> getRequestRows() async => requests;

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
