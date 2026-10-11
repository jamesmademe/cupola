/// The household's requests, whole: how they are folded from every Seerr,
/// and how many of the rest the list draws at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/data/household_requests.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 10, 20, 30);

/// Seerr's own numbering: 1 waiting, 2 approved, 3 declined.
SeerrRequest _request(int id, {int status = 2, int media = 5}) =>
    SeerrRequest.fromJson({
      'id': id,
      'status': status,
      'type': 'movie',
      'createdAt': _now.subtract(Duration(hours: id)).toUtc().toIso8601String(),
      'media': {
        'id': id,
        'tmdbId': 100 + id,
        'mediaType': 'movie',
        'status': media,
        'title': 'Title $id',
      },
      'requestedBy': {'id': 1, 'displayName': 'Anna'},
    }, numbering: SeerrNumbering.seerr);

SeerrRequestsRead _read(
  String id,
  AsyncValue<List<SeerrRequest>> read, {
  String? name,
}) => (instanceId: id, name: name, isLens: id == 'a', read: read);

/// The key's gate: every request is the operator's to answer.
RoleGate _key(String _) => const RoleGate(audience: Audience.operator);

void main() {
  group('householdRequestsOf', () {
    test('the waiting ones are decisions, the longest waiting first; the '
        'rest in the requester page\'s order; the figure counts what the '
        'section lists, and Seerr\'s count stays whole', () {
      final requests = householdRequestsOf(
        [
          _read(
            'a',
            AsyncData(
              SeerrRequestList([
                _request(1, status: 1, media: 2),
                _request(2, media: 3),
                _request(3, status: 1, media: 2),
              ], total: 3),
            ),
          ),
        ],
        now: _now,
        gateOf: _key,
        named: false,
      );

      expect([for (final d in requests.waiting) d.actionId], [3, 1]);
      expect(
        requests.waitingRequests.keys,
        unorderedEquals(['seerr-a-1', 'seerr-a-3']),
      );
      expect([for (final r in requests.rest) r.mine.request.id], [2]);
      expect(requests.total, 3);
      expect(requests.totalLabel, '1 total');
      expect(requests.whole, isTrue);
      expect(requests.rest.single.connection, isNull);
    });

    test('one request waiting above and one other read as two requests: '
        'the section says 1 total, the one it lists', () {
      final requests = householdRequestsOf(
        [
          _read(
            'a',
            AsyncData(
              SeerrRequestList([
                _request(1, status: 1, media: 2),
                _request(2, media: 3),
              ], total: 2),
            ),
          ),
        ],
        now: _now,
        gateOf: _key,
        named: false,
      );

      expect(requests.waiting, hasLength(1));
      expect(requests.rest, hasLength(1));
      expect(requests.totalLabel, '1 total');
    });

    test('a page that did not arrive leaves Seerr\'s count the total, and '
        'nothing tallied over the rows is the household\'s', () {
      final requests = householdRequestsOf(
        [
          _read(
            'a',
            AsyncData(
              SeerrRequestList([_request(2)], total: 60, isPartial: true),
            ),
          ),
        ],
        now: _now,
        gateOf: _key,
        named: false,
      );

      expect(requests.totalLabel, '60 total');
      expect(requests.whole, isFalse);
    });

    test('a Seerr that did not answer is named, takes nobody else\'s '
        'requests with it, and leaves the total a floor', () {
      final requests = householdRequestsOf(
        [
          _read(
            'a',
            AsyncData(SeerrRequestList([_request(2)], total: 1)),
            name: 'Home',
          ),
          _read(
            'b',
            AsyncError(Exception('refused'), StackTrace.empty),
            name: 'Cabin',
          ),
        ],
        now: _now,
        gateOf: _key,
        named: true,
      );

      expect([for (final s in requests.failed) s.instanceId], ['b']);
      expect(requests.rest, hasLength(1));
      expect(requests.rest.single.connection, 'Seerr Home');
      expect(requests.totalLabel, '1+ total');
      expect(requests.pending, isFalse);
    });

    test('a page that did not arrive from a Seerr with no count makes the '
        'total a floor', () {
      final requests = householdRequestsOf(
        [
          _read(
            'a',
            AsyncData(SeerrRequestList([_request(2)], isPartial: true)),
          ),
        ],
        now: _now,
        gateOf: _key,
        named: false,
      );

      expect(requests.totalLabel, '1+ total');
      expect(requests.whole, isFalse);
    });

    test('nothing answered or failed yet is pending', () {
      final requests = householdRequestsOf(
        [_read('a', const AsyncLoading())],
        now: _now,
        gateOf: _key,
        named: false,
      );

      expect(requests.pending, isTrue);
    });
  });

  group('RequestsBoard', () {
    Future<void> pump(WidgetTester tester, List<SeerrRequest> list) async {
      await tester.binding.setSurfaceSize(const Size(430, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.seerr],
            ),
            requestsProvider.overrideWith(
              (ref) async => SeerrRequestList(list, total: list.length),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: RequestsBoard(only: '')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('thirty of the rest at a time, then the ones left', (
      tester,
    ) async {
      await pump(tester, [for (var id = 1; id <= 35; id++) _request(id)]);

      expect(find.textContaining(RegExp(r'^Title \d+$')), findsNWidgets(30));
      expect(find.text('35 total'), findsOneWidget);
      await tester.tap(find.text('Show 5 more'));
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp(r'^Title \d+$')), findsNWidgets(35));
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('a no reads in the owner\'s words', (tester) async {
      await pump(tester, [_request(1, status: 3, media: 1)]);

      expect(find.textContaining('Declined'), findsOneWidget);
      expect(find.textContaining("server's owner"), findsNothing);
    });
  });
}
