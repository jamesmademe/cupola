import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('the tab draws the household\'s list: the one that waits for '
      'you first, answered there, then everyone\'s', (tester) async {
    await _pumpAllRequests(tester);
    await _pumpAsyncContent(tester);

    expect(find.text('All requests'), findsOneWidget);
    expect(find.text('1 request waits for your approval'), findsOneWidget);
    expect(find.byTooltip('Approve A Quiet Place'), findsOneWidget);
    expect(find.text("Everyone's requests"), findsOneWidget);
    expect(find.text('Shogun'), findsOneWidget);
    expect(find.text('james'), findsOneWidget);
    // No filters over the list: it is one list.
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('a waiting request waits, though the film is on disk', (
    tester,
  ) async {
    await _pumpAllRequests(tester);
    await _pumpAsyncContent(tester);

    // The trap: it read "Available" beside its own Approve.
    expect(find.byTooltip('Approve A Quiet Place'), findsOneWidget);
    expect(find.textContaining('Available'), findsNothing);
    expect(find.textContaining('Ready to watch'), findsNothing);
  });

  group('delete request, on the row\'s long press', () {
    Future<void> open(WidgetTester tester) async {
      await tester.longPress(find.text('Shogun'));
      await _settle(tester);
      await tester.tap(find.text('Delete request'));
      await _settle(tester);
    }

    testWidgets('confirming deletes it and reports the outcome', (
      tester,
    ) async {
      final seerr = _RecordingSeerrService();
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      await open(tester);
      expect(
        find.text('This removes the request for Shogun from Seerr.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
      await _settle(tester);

      expect(seerr.deletedIds, [2]);
      // Without feedback the row just vanishes, which reads as a glitch. The
      // SnackBar is also what announces the result, via its liveRegion.
      expect(find.text('Deleted the request for Shogun'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final seerr = _RecordingSeerrService();
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);

      expect(seerr.deletedIds, isEmpty);
    });

    testWidgets('a failure surfaces instead of failing silently', (
      tester,
    ) async {
      final seerr = _RecordingSeerrService(failure: 'HTTP 403');
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      await open(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
      await _settle(tester);

      expect(find.textContaining('Could not delete the request.'), findsOne);
      expect(seerr.deletedIds, isEmpty);
    });
  });

  group('semantics', () {
    testWidgets('a request row is one button, said without its middle dots', (
      tester,
    ) async {
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      expect(
        find.semantics.byLabel('Shogun'),
        isSemantics(
          value: 'On its way, being fetched, james',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(find.semantics.byLabel('·'), findsNothing);
    });

    testWidgets('Delete request is among the row\'s actions', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      final data = tester
          .getSemantics(find.bySemanticsLabel('Shogun'))
          .getSemanticsData();
      expect(
        [
          for (final id in data.customSemanticsActionIds ?? const <int>[])
            CustomSemanticsAction.getAction(id)!.label,
        ],
        ['Delete request'],
      );
      semantics.dispose();
    });
  });
}

class _RecordingSeerrService extends FakeSeerrService {
  _RecordingSeerrService({this.failure});

  final String? failure;
  final List<int> deletedIds = <int>[];

  @override
  Future<void> deleteRequest(int requestId) async {
    if (failure != null) throw Exception(failure);
    deletedIds.add(requestId);
  }
}

Future<void> _pumpAllRequests(
  WidgetTester tester, {
  SeerrService? seerr,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(seerr: seerr),
      child: MaterialApp(theme: theme, home: const ServiceAllRequestsScreen()),
    ),
  );
}

List<Override> _providerOverrides({SeerrService? seerr}) {
  return [
    currentSettingsProvider.overrideWith(
      (ref) => settingsWith(
        seerrUrl: 'http://seerr.local:5055',
        seerrApiKey: 'key',
        radarrUrl: 'http://radarr.local:7878',
        radarrApiKey: 'key',
        sonarrUrl: 'http://sonarr.local:8989',
        sonarrApiKey: 'key',
        lidarrUrl: 'http://lidarr.local:8686',
        lidarrApiKey: 'key',
      ),
    ),
    if (seerr != null) seerrServiceProvider.overrideWithValue(seerr),
    servicesRequestsProvider.overrideWith(
      (ref) async => const [
        SeerrRequest(
          id: 1,
          status: RequestStatus.pendingApproval,
          media: RequestMedia(
            title: 'A Quiet Place',
            tmdbId: 123,
            posterPath: '/quiet-place.jpg',
            status: SeerrMediaAvailability.available,
          ),
          createdAt: '2026-05-02T10:00:00Z',
          type: 'movie',
          requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
        ),
        SeerrRequest(
          id: 2,
          status: RequestStatus.approved,
          media: RequestMedia(
            title: 'Shogun',
            status: SeerrMediaAvailability.partiallyAvailable,
          ),
          createdAt: '2026-05-01T10:00:00Z',
          type: 'tv',
          requestedBy: RequestedBy(id: 2, displayName: 'james'),
        ),
      ],
    ),
  ];
}

Future<void> _pumpAsyncContent(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Bounded pumping instead of `pumpAndSettle`.
///
/// The rows hold a `CachedNetworkImage`, which never resolves under the test
/// binding, so `pumpAndSettle` times out. 350ms is enough to run a dialog's
/// route transition to completion.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}
