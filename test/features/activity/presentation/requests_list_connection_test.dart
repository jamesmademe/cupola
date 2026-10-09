import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
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

Future<List<Override>> _settings() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_second),
);

SeerrRequest _request(int id, String title) => SeerrRequest(
  id: id,
  status: RequestStatus.pendingApproval,
  type: 'movie',
  createdAt: '2026-08-01T10:00:00.000Z',
  media: RequestMedia(id: id, tmdbId: id, mediaType: 'movie', title: title),
);

Future<void> _pump(
  WidgetTester tester, {
  required ProviderContainer container,
  String? instanceId,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ActivityScreen(
          serviceType: ServiceType.discover,
          instanceId: instanceId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The other half of the routing problem. A request row in the aggregated feed
  // opens this list; if the list resolves through the lens, a row that came off
  // the second Seerr opens the first Seerr's requests — the defect moved rather
  // than closed.
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

  testWidgets('a card says the day as the app says dates', (tester) async {
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

  testWidgets('and says whose requests these are', (tester) async {
    final container = ProviderContainer(
      overrides: [
        ...await _settings(),
        seerrServiceProvider.overrideWith(
          (ref) => _RequestsSeerrService(const []),
        ),
        seerrServiceForProvider(
          _second.id,
        ).overrideWithValue(_RequestsSeerrService(const [])),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container: container, instanceId: _second.id);

    // Named after the connection the link carried, not after the lens — which
    // is still sitting on the first Seerr.
    expect(find.text('Requests · Anime'), findsOneWidget);
  });

  testWidgets('with no connection named it stays on the lens', (tester) async {
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
    expect(find.text('From the second'), findsNothing);
  });

  // A link outlives the connection it names: the user opens a request row,
  // deletes that Seerr in Settings, then comes back to the screen from history
  // or a deep link. The title resolves `named` to null and falls back to the
  // lens; handing the dead id to the list as well would print "not configured"
  // under a header naming a server that is up.
  testWidgets('a link naming a connection that is gone falls back to the lens', (
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

    // The header names the lens — the first Seerr, which carries no label, so
    // it is called by its place, never by its id.
    expect(find.text('Requests · Seerr 1'), findsOneWidget);
    // …and the list under it is that same server's, rather than an error state
    // about a connection nothing on this screen mentions.
    expect(find.text('From the first'), findsOneWidget);
    expect(find.textContaining('not configured'), findsNothing);
  });

  // Every write on this screen is keyed by a per-instance request id too.
  testWidgets('a delete on this list goes to the connection it belongs to', (
    tester,
  ) async {
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

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
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

    // The card's own button is a `FilledButton.icon`, whose runtime type is a
    // private subclass — `find.byType` matches exactly, so it is found by text.
    // The dialog's confirm is a plain `FilledButton`, which is what tells the
    // two apart once both are on screen.
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
    await tester.pumpAndSettle();

    expect(other.approved, [42]);
    expect(lens.approved, isEmpty);
  });
}

class _RequestsSeerrService extends FakeSeerrService {
  _RequestsSeerrService(this.requests);

  final List<SeerrRequest> requests;
  final List<int> approved = [];
  final List<int> declined = [];
  final List<int> deleted = [];

  @override
  Future<List<SeerrRequest>> getRequests() async => requests;

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
