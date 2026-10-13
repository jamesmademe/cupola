import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // Decisions first: Seerr is the exception, and the rails move down.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs a decision', 'Processing', 'Trending'],
    );
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester, service: _scripted());

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        'opens the Seerr Requests tab',
        'opens the Seerr Requests tab',
        // Trending opens no tab of Seerr's: Discover is a tab of the app now,
        // and each of its titles opens on its own.
        null,
      ],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), version: '2.2.0');

    expect(
      find.semantics.byLabel('Seerr, seerr.local:5055, v2.2.0, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Seerr reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, service: _scripted(), version: null);

      expect(
        find.semantics.byLabel('Seerr, seerr.local:5055, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a decision row is spoken as one sentence', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      service: _scripted(
        requests: [
          _request(
            id: 1,
            title: 'Severance',
            type: 'tv',
            seasons: [2],
            requester: 'nadia',
            createdAt: now.subtract(const Duration(hours: 4)).toIso8601String(),
          ),
        ],
      ),
    );

    expect(
      find.semantics.byLabel('Severance, Season 2, nadia, 4\u00A0h ago, TV'),
      findsOneWidget,
    );
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, service: _FailingTrendingSeerr());

    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so what is trending is not shown."),
      findsOneWidget,
    );
    // …and the other two still drew their headings.
    expect(find.byType(SectionHeader), findsNWidgets(3));
  });

  testWidgets('a poster on the trending rail has an accessible name', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _scripted(
        trending: const [
          MediaPreview(id: 9, title: 'Dune: Part Two', mediaType: 'movie'),
        ],
      ),
    );

    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Dune: Part Two'),
          matching: find.byType(PressableScale),
        ),
      ),
      containsSemantics(label: 'Dune: Part Two', isButton: true),
    );
  });

  testWidgets('what waits is counted', (tester) async {
    await _pump(
      tester,
      service: _scripted(requests: [_request(id: 1), _request(id: 2)]),
    );

    expect(find.text('2 requests waiting'), findsOneWidget);
    expect(find.textContaining('+ requests'), findsNothing);
  });

  testWidgets('a lost page of requests makes the count a floor', (
    tester,
  ) async {
    // Seerr holds ten; a page of them did not arrive, so the two waiting
    // ones counted here are the least there are.
    await _pump(
      tester,
      service: _scripted(
        requests: SeerrRequestList(
          [_request(id: 1), _request(id: 2)],
          total: 10,
          isPartial: true,
        ),
      ),
    );
    expect(find.text('2+ requests waiting'), findsOneWidget);
    expect(find.text('2 requests waiting'), findsNothing);
  });

  testWidgets('with nothing waiting the region stays, and says so', (
    tester,
  ) async {
    // A stack with auto-approvals sits here permanently: the region is a
    // tab's, so it does not vanish into a page that looks failed.
    await _pump(
      tester,
      service: _scripted(
        requests: [
          SeerrRequest(
            id: 1,
            status: RequestStatus.approved,
            media: const RequestMedia(title: 'Dune', tmdbId: 1),
            createdAt: '2026-09-01T00:00:00Z',
            type: 'movie',
          ),
        ],
      ),
    );

    expect(find.text('Needs a decision'), findsOneWidget);
    expect(find.text('Nothing waiting on you'), findsOneWidget);
    expect(find.byTooltip('Approve Dune'), findsNothing);
  });

  testWidgets('a Seerr that did not answer says so, never that nothing '
      'waits', (tester) async {
    await _pump(tester, service: _FailingRequestsSeerr());

    expect(find.byType(InlineErrorRetry), findsWidgets);
    expect(find.text('Nothing waiting on you'), findsNothing);
  });

  testWidgets('each waiting request carries its two answers, named by its '
      'title, whole at a phone width and twice the reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(360, 3200),
      textScaleFactor: 2.0,
      service: _scripted(
        requests: [
          _request(id: 1, title: 'Dune', requester: 'Ada'),
          _request(
            id: 2,
            title: 'The Lord of the Rings: The Fellowship of the Ring',
            requester: 'Konstantinos Papadopoulos',
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    for (final verb in ['Approve', 'Decline']) {
      final button = find.byTooltip('$verb Dune');
      expect(button, findsOneWidget);
      // Reachable at 2x: a control that overflows out of the row is a
      // control nobody can press.
      expect(tester.getRect(button).right, lessThanOrEqualTo(360));
    }
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      service: _scripted(
        requests: [
          _request(
            id: 1,
            title: 'A Request Whose Title Will Not Fit On One Line At All',
            requester: 'somebody-with-a-long-name',
          ),
        ],
        trending: const [
          MediaPreview(
            id: 9,
            title: 'A Trending Title That Will Not Fit Either',
            mediaType: 'tv',
          ),
        ],
      ),
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Seerr that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: _scripted(), configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.seerr);
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required SeerrService service,
  String? version = '2.2.0',
  bool configured = true,
  double textScaleFactor = 1.0,
  Size size = const Size(420, 2600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  seerrUrl: 'http://seerr.local:5055',
                  seerrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        seerrServiceProvider.overrideWith((ref) => service),
        seerrClientFactoryProvider.overrideWith(
          (ref) =>
              (
                instance, {
                ConnectionReach? reach,
                SeerrSessionEvents events = const SeerrSessionEvents(),
              }) => _StatusClient(version),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const SeerrOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SeerrService _scripted({
  List<SeerrRequest> requests = const [],
  List<MediaPreview> trending = const [],
}) => _ScriptedSeerr(requests: requests, trending: trending);

class _ScriptedSeerr extends FakeSeerrService {
  _ScriptedSeerr({this.requests = const [], this.trending = const []});

  final List<SeerrRequest> requests;
  final List<MediaPreview> trending;

  @override
  Future<List<SeerrRequest>> getRequests() async => requests;

  @override
  Future<List<MediaPreview>> getDiscoverTrending({int page = 1}) async =>
      trending;
}

class _FailingRequestsSeerr extends _ScriptedSeerr {
  @override
  Future<List<SeerrRequest>> getRequests() async =>
      throw Exception('requests failed');
}

class _FailingTrendingSeerr extends _ScriptedSeerr {
  @override
  Future<List<MediaPreview>> getDiscoverTrending({int page = 1}) async =>
      throw Exception('trending failed');
}

/// The reachability probe, answered offline.
///
/// A null [version] is the wire shape of a service that did not answer: the
/// probe throws, which is what `_loadServiceSummary` reads as offline.
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'http://seerr.local:5055', apiKey: 'key');

  final String? version;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (version == null) throw const SocketException('Connection refused');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'version': version},
    );
  }

  @override
  void close({bool force = false}) {}
}

SeerrRequest _request({
  required int id,
  String title = 'Title',
  String type = 'movie',
  String? requester,
  String createdAt = '2026-09-01T00:00:00Z',
  List<int>? seasons,
}) => SeerrRequest(
  id: id,
  status: RequestStatus.pendingApproval,
  media: RequestMedia(title: title, tmdbId: id),
  createdAt: createdAt,
  type: type,
  requestedBy: requester == null
      ? null
      : RequestedBy(id: id, displayName: requester),
  seasons: seasons
      ?.map((n) => RequestSeason(seasonNumber: n, status: 'pending'))
      .toList(),
);
