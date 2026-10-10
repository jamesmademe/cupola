import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// Seerr's Requests tab, which hosts the household's list and pulls it.
///
/// One Seerr, which is the common case and the one the defect lived in. With
/// a single connection the list is read for the lens — an empty
/// `instanceId` — and `requestsForProvider('')` is then a passthrough of
/// `requestsProvider`. Dropping only the family entry rebuilds it against a
/// value the plain provider is still holding, so the gesture re-renders the
/// identical rows and never reaches the server. A fixture with two Seerr would
/// have hidden that: the named path fetches on its own.
Future<Widget> _app(_CountingSeerrService seerr) async {
  return ProviderScope(
    overrides: [
      ...await settingsScopeOverrides(configured: const [ServiceKey.seerr]),
      seerrServiceProvider.overrideWith((ref) => seerr),
    ],
    child: const MaterialApp(home: ServiceAllRequestsScreen()),
  );
}

void main() {
  testWidgets('pull-to-refresh fetches the list again', (tester) async {
    final seerr = _CountingSeerrService();
    await tester.pumpWidget(await _app(seerr));
    await tester.pumpAndSettle();

    expect(seerr.calls, 1);
    expect(find.text('Fetch 1'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    // The point of the gesture. One call means the pull spun an indicator over
    // a cached list.
    expect(seerr.calls, 2);
    expect(find.text('Fetch 2'), findsOneWidget);
    expect(find.text('Fetch 1'), findsNothing);
  });

  testWidgets('and so does Retry after a failure', (tester) async {
    final seerr = _CountingSeerrService(failFirst: true);
    await tester.pumpWidget(await _app(seerr));
    await tester.pumpAndSettle();

    expect(seerr.calls, 1);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // An errored provider caches its error exactly as a loaded one caches its
    // value, so a Retry that drops the entry alone offers the user a button
    // that re-renders the same failure.
    expect(seerr.calls, 2);
    expect(find.text('Fetch 2'), findsOneWidget);
  });
}

/// Counts the fetches and hands back a list that names the fetch it came from,
/// so a stale render is visible rather than merely equal.
class _CountingSeerrService extends FakeSeerrService {
  _CountingSeerrService({this.failFirst = false});

  final bool failFirst;
  int calls = 0;

  @override
  Future<List<SeerrRequest>> getRequests() async {
    calls++;
    if (failFirst && calls == 1) throw Exception('connection refused');
    return [
      SeerrRequest(
        id: calls,
        status: RequestStatus.pendingApproval,
        type: 'movie',
        createdAt: '2026-08-01T10:00:00.000Z',
        media: RequestMedia(
          id: calls,
          tmdbId: calls,
          mediaType: 'movie',
          title: 'Fetch $calls',
        ),
      ),
    ];
  }
}
