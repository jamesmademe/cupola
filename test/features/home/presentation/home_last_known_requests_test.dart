import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/data/home_requests.dart';
import 'package:cupola/features/home/data/last_known/dashboard_decision_codec.dart';
import 'package:cupola/features/home/data/last_known/requests_last_known.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 12, 20, 53);

DashboardDecision _request(
  String title,
  int id, {
  int hoursAgo = 2,
  String detail = 'Anna',
  String instanceId = '',
  String posterUrl = '',
}) => DashboardDecision(
  kind: DecisionKind.pendingRequest,
  id: 'seerr-$instanceId-$id',
  service: ServiceKey.seerr,
  title: title,
  detail: detail,
  occurredAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
  actionId: id,
  instanceId: instanceId,
  route: '/dashboard/seerr/requests',
  posterUrl: posterUrl,
);

DashboardDecisions _decisions(
  List<DashboardDecision> decisions, {
  SourceCoverage? coverage,
}) => (
  decisions: decisions,
  coverage: coverage ?? SourceCoverage.answeredBy(ServiceKey.seerr),
);

typedef _Count = ({int count, bool floor});

class _Answered extends AnsweredRequests {
  _Answered(this.initial);

  final Map<String, AnsweredRequest> initial;

  @override
  Map<String, AnsweredRequest> build() => initial;
}

/// A Seerr account of the operator's own: an administrator, signed in.
SettingsModel _account(int userId) => SettingsModel(
  instances: [
    ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'https://seerr.test',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.local,
        login: 'anna@home.arpa',
        userId: userId,
        displayName: 'Anna',
        session: 'session',
        permissions: 2,
      ),
    ),
  ],
);

/// Requests at a cold start: the requests that waited, as they were last
/// drawn and with the count the line said, until the live answer comes.
void main() {
  group('a cold start', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    /// One run of the app: a fresh scope over the same [store], as a start
    /// over the same file would be.
    Future<void> run(
      WidgetTester tester,
      Future<DashboardDecisions> Function() decisions, {
      Future<_Count?> Function()? count,
      SettingsModel Function(SettingsModel)? customize,
      Map<String, AnsweredRequest> answered = const {},
    }) async {
      tester.view.physicalSize = const Size(1170, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.seerr],
              customize: customize,
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => _now),
            dashboardDecisionSourceProvider.overrideWith(
              (ref, source) => decisions(),
            ),
            pendingRequestCountProvider.overrideWith(
              (ref) => (count ?? () async => (count: 2, floor: false))(),
            ),
            seerrServerFactsProvider.overrideWith(
              (ref, id) => Completer<SeerrServerFacts>().future,
            ),
            answeredRequestsProvider.overrideWith(() => _Answered(answered)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(children: [HomeAsOfLine(), HomeRequestsModule()]),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final charge = _request('Charge', 1);
    Future<void> firstRun(
      WidgetTester tester, {
      int count = 7,
      bool floor = false,
      SettingsModel Function(SettingsModel)? customize,
      String instanceId = '',
      Map<String, AnsweredRequest> answered = const {},
    }) async {
      await run(
        tester,
        () async => _decisions([
          _request('Charge', 1, instanceId: instanceId),
          _request('Metropolis', 2, hoursAgo: 20, instanceId: instanceId),
        ]),
        count: () async => (count: count, floor: floor),
        customize: customize,
        answered: answered,
      );
      await tester.pumpAndSettle();
      expect(find.text('Charge'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('draws the requests as they were at once, with their '
        'buttons and the count they were drawn with, then the live ones', (
      tester,
    ) async {
      await firstRun(tester);
      expect(find.text('7 wait for you'), findsOne);

      final answer = Completer<DashboardDecisions>();
      final count = Completer<_Count?>();
      await run(tester, () => answer.future, count: () => count.future);
      // No skeleton: the rows the person last saw, one line over them.
      expect(find.text('Charge'), findsOne);
      expect(find.text('Metropolis'), findsOne);
      expect(find.text('7 wait for you'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);
      // Their answers stay: the server says for what is no longer valid.
      expect(find.byTooltip('Approve Charge'), findsOne);
      expect(find.byTooltip('Decline Charge'), findsOne);
      expect(find.byTooltip('Approve Metropolis'), findsOne);
      expect(find.text('See all requests'), findsOne);
      // Who asked, and how long ago, made again against now.
      expect(find.textContaining('Anna · 2\u00A0h ago'), findsOne);

      answer.complete(_decisions([_request('Spring', 3)]));
      count.complete((count: 1, floor: false));
      await tester.pumpAndSettle();
      expect(find.text('Charge'), findsNothing);
      expect(find.text('Spring'), findsOne);
      expect(find.text('1 waits for you'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a floor is drawn as a floor, never as a total', (
      tester,
    ) async {
      await firstRun(tester, count: 50, floor: true);
      expect(find.text('50+ wait for you'), findsOne);

      await run(tester, () => Completer<DashboardDecisions>().future);
      expect(find.text('50+ wait for you'), findsOne);
      expect(find.text('50 wait for you'), findsNothing);
    });

    testWidgets('a live read that fails keeps the drawing at full ink, over '
        'the failure, with its buttons, and stops checking', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Charge'), findsOne);
      expect(find.byTooltip('Approve Charge'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);
      // The same server draws it: the drawing is there to be refused.
      await run(tester, () => Completer<DashboardDecisions>().future);
      expect(find.text('Charge'), findsOne);

      await run(
        tester,
        () => Completer<DashboardDecisions>().future,
        customize: (settings) => settings.copyWithService(
          ServiceKey.seerr,
          url: 'https://other.test',
          apiKey: 'seerr-key',
        ),
      );
      expect(find.text('Charge'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('another account draws nothing of it', (tester) async {
      await firstRun(
        tester,
        customize: (_) => _account(1),
        instanceId: 'seerr',
      );
      // The same account draws it: the drawing is there to be refused.
      await run(
        tester,
        () => Completer<DashboardDecisions>().future,
        customize: (_) => _account(1),
      );
      expect(find.text('Charge'), findsOne);
      expect(find.byTooltip('Approve Charge'), findsOne);

      await run(
        tester,
        () => Completer<DashboardDecisions>().future,
        customize: (_) => _account(2),
      );
      expect(find.text('Charge'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a request answered here is not part of the drawing', (
      tester,
    ) async {
      // Seerr's list, as read, still holds Charge: it was answered here.
      await firstRun(
        tester,
        answered: {
          charge.id: (decision: charge, outcome: 'Approved · sent to Radarr'),
        },
      );
      expect(find.text('Approved · sent to Radarr'), findsOne);

      await run(tester, () => Completer<DashboardDecisions>().future);
      expect(find.text('Metropolis'), findsOne);
      expect(find.text('Charge'), findsNothing);
      expect(find.text('Approved · sent to Radarr'), findsNothing);
      expect(find.byTooltip('Approve Charge'), findsNothing);
    });

    testWidgets('a live answer with nothing waiting replaces the drawing: '
        'what was answered since is not drawn again', (tester) async {
      await firstRun(tester);
      await run(
        tester,
        () async => _decisions(const []),
        count: () async => (count: 0, floor: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Requests'), findsNothing);

      await run(tester, () => Completer<DashboardDecisions>().future);
      // The loading frame, never the requests answered since, and nothing
      // dated: there is nothing drawn from the past.
      expect(find.text('Charge'), findsNothing);
      expect(find.text('Metropolis'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a read that is not whole is not kept: the count would read '
        'as a total', (tester) async {
      await firstRun(tester);

      // One Seerr silent: the figure is a part, and says so only live.
      await run(
        tester,
        () async => _decisions(
          [_request('Spring', 3)],
          coverage: SourceCoverage.merge([
            SourceCoverage.answeredBy(ServiceKey.seerr, instanceId: 'a'),
            SourceCoverage.failure(
              ServiceKey.seerr,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
              instanceId: 'b',
            ),
          ]),
        ),
        count: () async => null,
      );
      await tester.pumpAndSettle();
      expect(find.text('Spring'), findsOne);

      // The drawing before it stays.
      await run(tester, () => Completer<DashboardDecisions>().future);
      expect(find.text('Spring'), findsNothing);
      expect(find.text('Charge'), findsOne);
      expect(find.text('7 wait for you'), findsOne);
    });
  });

  group('the read', () {
    ProviderContainer containerOf({
      required Future<DashboardDecisions> Function() decisions,
      required Future<_Count?> Function() count,
      Map<String, AnsweredRequest> answered = const {},
    }) {
      final container = ProviderContainer(
        overrides: [
          dashboardDecisionSourceProvider.overrideWith(
            (ref, source) => decisions(),
          ),
          pendingRequestCountProvider.overrideWith((ref) => count()),
          answeredRequestsProvider.overrideWith(() => _Answered(answered)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the rows come first; the count settles the read', () async {
      final count = Completer<_Count?>();
      final container = containerOf(
        decisions: () async => _decisions([_request('Charge', 1)]),
        count: () => count.future,
      );
      container.listen(homeRequestsProvider, (_, _) {});
      expect(container.read(homeRequestsProvider).isLoading, isTrue);

      await container.read(
        dashboardDecisionSourceProvider(DecisionSource.requests).future,
      );
      final rowsOnly = container.read(homeRequestsProvider).requireValue;
      expect(rowsOnly.decisions, hasLength(1));
      expect(rowsOnly.counted, isNull);
      expect(rowsOnly.settled, isFalse);

      count.complete((count: 9, floor: true));
      await container.read(pendingRequestCountProvider.future);
      final whole = container.read(homeRequestsProvider).requireValue;
      expect(whole.counted, (count: 9, floor: true));
      expect(whole.settled, isTrue);
    });

    test('a request answered here is not among the rows', () async {
      final charge = _request('Charge', 1);
      final container = containerOf(
        decisions: () async =>
            _decisions([charge, _request('Metropolis', 2, hoursAgo: 20)]),
        count: () async => (count: 2, floor: false),
        answered: {charge.id: (decision: charge, outcome: 'Declined')},
      );
      container.listen(homeRequestsProvider, (_, _) {});
      await container.read(
        dashboardDecisionSourceProvider(DecisionSource.requests).future,
      );
      final read = container.read(homeRequestsProvider).requireValue;
      expect(read.decisions.map((each) => each.title), ['Metropolis']);
    });

    test('a read that failed is a failure, as the module reads it', () async {
      final container = containerOf(
        decisions: () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
        count: () async => null,
      );
      container.listen(homeRequestsProvider, (_, _) {});
      await container
          .read(dashboardDecisionSourceProvider(DecisionSource.requests).future)
          .then<void>((_) {}, onError: (Object _) {});
      expect(container.read(homeRequestsProvider).hasError, isTrue);
    });
  });

  group('the codec', () {
    DashboardDecision full() => DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'seerr-4k-17',
      service: ServiceKey.seerr,
      title: 'Charge',
      detail: 'Seerr 4K · Anna',
      occurredAt: DateTime.utc(2026, 10, 12, 18, 30, 15, 250),
      route: '/dashboard/seerr/requests?i=4k',
      posterUrl: 'https://image.tmdb.org/t/p/w154/charge.jpg',
      actionId: 17,
      instanceId: '4k',
      connectionName: '4K',
    );

    Object? onDisk(Object? json) => jsonDecode(jsonEncode(json));

    test('a request survives its codec whole', () {
      final back = dashboardDecisionFromJson(
        onDisk(dashboardDecisionToJson(full())),
      )!;
      final decision = full();
      expect(back.kind, decision.kind);
      expect(back.id, decision.id);
      expect(back.service, decision.service);
      expect(back.title, decision.title);
      expect(back.detail, decision.detail);
      expect(back.occurredAt!.isAtSameMomentAs(decision.occurredAt!), isTrue);
      expect(back.route, decision.route);
      expect(back.posterUrl, decision.posterUrl);
      expect(back.actionId, decision.actionId);
      expect(back.instanceId, decision.instanceId);
      expect(back.connectionName, decision.connectionName);
      expect(back.count, decision.count);
      expect(back.actionInstanceId, decision.actionInstanceId);
    });

    test('the time is an instant and never the words made of it', () {
      final json = jsonEncode(dashboardDecisionToJson(full()));
      expect(json, contains('2026-10-12T18:30:15.250Z'));
      expect(json, isNot(contains('ago')));
      expect(json, isNot(contains('yesterday')));
    });

    test('who asked is kept by name and never by address', () {
      DashboardDecision with_(String detail) => DashboardDecision(
        kind: DecisionKind.pendingRequest,
        id: 'seerr--1',
        service: ServiceKey.seerr,
        title: 'Charge',
        detail: detail,
        occurredAt: null,
        actionId: 1,
      );
      String? detailOf(String detail) =>
          (dashboardDecisionToJson(with_(detail))!)['detail'] as String?;
      expect(detailOf('Anna'), 'Anna');
      expect(detailOf('Seerr 4K · Anna'), 'Seerr 4K · Anna');
      // Seerr's display name falls back to the account's email.
      expect(detailOf('anna@home.arpa'), isNull);
      expect(detailOf('Seerr 4K · anna@home.arpa'), 'Seerr 4K');
      expect(
        jsonEncode(dashboardDecisionToJson(with_('Seerr · anna@home.arpa'))),
        isNot(contains('anna@home.arpa')),
      );
      // A handle is not an address.
      expect(detailOf('@anna'), '@anna');
    });

    test('no credential is kept: an address that carries a key is dropped', () {
      final json = dashboardDecisionToJson(
        DashboardDecision(
          kind: DecisionKind.pendingRequest,
          id: 'seerr--2',
          service: ServiceKey.seerr,
          title: 'Leaky',
          detail: '',
          occurredAt: null,
          actionId: 2,
          route: '/somewhere?apikey=SECRET-ROUTE',
          posterUrl: 'https://example.com/p.jpg?api_key=SECRET-POSTER',
        ),
      )!;
      expect(jsonEncode(json), isNot(contains('SECRET')));
      expect(json.containsKey('route'), isFalse);
      expect(json.containsKey('posterUrl'), isFalse);
    });

    test(
      'only a request that waits is kept, and a broken record is refused',
      () {
        const fault = DashboardDecision(
          kind: DecisionKind.stalledDownload,
          id: 'queue-1',
          service: ServiceKey.radarr,
          title: 'Stuck',
          detail: '',
          occurredAt: null,
        );
        expect(dashboardDecisionToJson(fault), isNull);

        final good = dashboardDecisionToJson(full())!;
        expect(
          dashboardDecisionFromJson({...good, 'kind': 'stalledDownload'}),
          isNull,
        );
        expect(dashboardDecisionFromJson({...good}..remove('id')), isNull);
        expect(dashboardDecisionFromJson({...good}..remove('title')), isNull);
        expect(
          dashboardDecisionFromJson({...good, 'service': 'nowhere'}),
          isNull,
        );
        expect(dashboardDecisionFromJson({...good, 'actionId': '17'}), isNull);
        expect(
          dashboardDecisionFromJson({...good, 'occurredAt': 'soon'}),
          isNull,
        );
        expect(dashboardDecisionFromJson('nope'), isNull);
        expect(dashboardDecisionFromJson(null), isNull);
      },
    );
  });

  group('the drawing', () {
    HomeRequests read({
      List<DashboardDecision>? decisions,
      SourceCoverage? coverage,
      _Count? counted = (count: 7, floor: false),
      bool settled = true,
    }) => (
      decisions: decisions ?? [_request('Charge', 1), _request('Spring', 2)],
      coverage: coverage ?? SourceCoverage.answeredBy(ServiceKey.seerr),
      counted: counted,
      settled: settled,
    );

    Object? decoded(Object? encoded) => requestsLastKnown.decode(
      jsonDecode(jsonEncode(encoded)),
      (_) => throw StateError('no pictures'),
    );

    test('keeps the rows and the count it drew, floor and all', () {
      final back =
          decoded(
                requestsLastKnown.encode(
                  read(counted: (count: 50, floor: true)),
                ),
              )!
              as HomeRequests;
      expect(back.decisions.map((each) => each.title), ['Charge', 'Spring']);
      expect(back.counted, (count: 50, floor: true));
      expect(back.settled, isTrue);
      expect(back.coverage.failed, isEmpty);
    });

    test('is made of a whole read only', () {
      expect(requestsLastKnown.encode(read(counted: null)), isNull);
      expect(requestsLastKnown.encode(read(settled: false)), isNull);
      expect(
        requestsLastKnown.encode(
          read(
            coverage: SourceCoverage.merge([
              SourceCoverage.answeredBy(ServiceKey.seerr, instanceId: 'a'),
              SourceCoverage.failure(
                ServiceKey.seerr,
                const ClassifiedFailure(ServiceFailureReason.unreachable),
                instanceId: 'b',
              ),
            ]),
          ),
        ),
        isNull,
      );
      expect(
        requestsLastKnown.encode(
          read(coverage: SourceCoverage.pendingOf(const [ServiceKey.seerr])),
        ),
        isNull,
      );
      // Nothing waiting, said by every Seerr, is kept: as an empty drawing.
      final empty =
          requestsLastKnown.encode(
                read(decisions: const [], counted: (count: 0, floor: false)),
              )!
              as Map;
      expect(empty['rows'], isEmpty);
    });

    test('is bounded, the oldest first', () {
      final many = [
        for (var i = 0; i < 20; i++) _request('Title $i', i, hoursAgo: i + 1),
      ];
      final kept = requestsLastKnown.encode(read(decisions: many))! as Map;
      final titles = [
        for (final row in kept['rows'] as List) (row as Map)['title'],
      ];
      expect(titles, hasLength(8));
      expect(titles.first, 'Title 19');
    });

    test('a record it cannot read whole is not drawn', () {
      final good =
          jsonDecode(jsonEncode(requestsLastKnown.encode(read())))! as Map;
      Object? decode(Object? data) =>
          requestsLastKnown.decode(data, (_) => throw StateError(''));
      expect(decode(good), isNotNull);
      expect(decode({...good}..remove('count')), isNull);
      expect(decode({...good, 'floor': 'no'}), isNull);
      expect(decode({...good, 'rows': 'nope'}), isNull);
      expect(
        decode({
          ...good,
          'rows': [
            ...good['rows'] as List,
            {'kind': 'stalledDownload'},
          ],
        }),
        isNull,
      );
      expect(decode('nope'), isNull);
    });
  });
}
