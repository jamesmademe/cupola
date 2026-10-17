import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/fakes/media_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

const _personId = 9;

Future<void> _pump(
  WidgetTester tester,
  FutureOr<PersonDetail> Function(Ref ref, int id) builder,
) async {
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3's own backoff retry would make the load count
      // non-deterministic.
      retry: (retryCount, error) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.seerr]),
        ),
        personDetailProvider.overrideWith(builder),
        personCreditsProvider.overrideWith(
          (ref, id) async => PersonCombinedCredits.empty,
        ),
        seerrNumberingProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: PersonPage(personId: _personId)),
    ),
  );
}

/// Ian Hubert's directing, as the board draws it: one title on the server,
/// a movie and a series Seerr has no record of.
PersonCombinedCredits _directing() => PersonCombinedCredits.fromJson({
  'crew': [
    {
      'id': 777001,
      'mediaType': 'tv',
      'name': 'Dynamo Dream',
      'firstAirDate': '2019-02-01',
      'job': 'Director',
      'department': 'Directing',
    },
    {
      'id': 133701,
      'mediaType': 'movie',
      'title': 'Tears of Steel',
      'releaseDate': '2012-09-26',
      'voteAverage': 6.6,
      'job': 'Director',
      'department': 'Directing',
      'mediaInfo': {'status': 5},
    },
    {
      'id': 777002,
      'mediaType': 'movie',
      'title': 'Project London',
      'releaseDate': '2011-06-01',
      'job': 'Director',
      'department': 'Directing',
    },
  ],
});

Future<ProfileHarness> _person(
  WidgetTester tester,
  ConfigProfile profile, {
  List<Override> overrides = const [],
}) => pumpWithProfile(
  tester,
  profile,
  child: const PersonPage(personId: SeerrFake.personId),
  overrides: [
    personCreditsProvider.overrideWith((ref, id) async => _directing()),
    ...overrides,
  ],
  surfaceSize: const Size(430, 1600),
);

/// The operator's choice of how a title nobody holds is added, fixed for a
/// test: the plus on a row is the same choice the media page's lead reads.
class _AddsVia extends OperatorAddsViaNotifier {
  _AddsVia(this.via);

  final OperatorAddsVia via;

  @override
  OperatorAddsVia build() => via;
}

void main() {
  group('PersonPage', () {
    testWidgets('a failed lookup names Seerr and can be retried in place', (
      tester,
    ) async {
      var loads = 0;
      await _pump(tester, (ref, id) {
        loads++;
        return Future<PersonDetail>.error(Exception('Connection refused'));
      });
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(
        find.text('The request to Seerr did not complete'),
        findsOneWidget,
      );
      expect(loads, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(loads, 2);
    });

    testWidgets('a person Seerr has no record of gets the empty-state voice', (
      tester,
    ) async {
      await _pump(
        tester,
        (ref, id) async => const PersonDetail(id: 0, name: ''),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('No details for this person'), findsOneWidget);
      expect(find.text('The request to Seerr did not complete'), findsNothing);
    });

    testWidgets('dates speak the detail pages one date voice', (tester) async {
      await _pump(
        tester,
        (ref, id) async => const PersonDetail(
          id: _personId,
          name: 'Robert Downey Jr.',
          knownForDepartment: 'Acting',
          birthday: '1965-04-04',
          deathday: '2099-01-09',
          placeOfBirth: 'Manhattan, New York, USA',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('About'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // TMDB answers with `1965-04-04`; the page used to print it raw, on a
      // surface where the Seerr title one tap away said `Apr 4, 1965`.
      expect(
        find.text('Born Apr 4, 1965\u00A0· Manhattan, New York, USA'),
        findsOneWidget,
      );
      expect(find.text('Died Jan 9, 2099'), findsOneWidget);
      expect(find.textContaining('1965-04-04'), findsNothing);
      // Under the name, what they do.
      expect(find.text('Actor'), findsOneWidget);
    });
  });

  group('on the profiles', () {
    testWidgets('P1: Seerr\'s own credits, by trade, the count exact', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: const PersonPage(personId: SeerrFake.personId),
        surfaceSize: const Size(430, 1600),
      );

      expect(find.text(SeerrFake.personName), findsOneWidget);
      expect(find.text('Director'), findsOneWidget);
      expect(find.text('Directed'), findsOneWidget);
      // Three of the four on the server; Charge waits for approval.
      expect(find.text('3 of 4 on your server'), findsOneWidget);
      expect(find.text('Credits from TMDB.'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1, straight to the arr: the plus adds to each arr, never on '
        'a title the server has', (tester) async {
      final harness = await _person(
        tester,
        Profiles.p1,
        overrides: [
          operatorAddsViaProvider.overrideWith(
            () => _AddsVia(OperatorAddsVia.arr),
          ),
        ],
      );

      expect(find.text('1 of 3 on your server'), findsOneWidget);
      // Newest first.
      expect(
        tester.getTopLeft(find.text('Dynamo Dream')).dy,
        lessThan(tester.getTopLeft(find.text('Project London')).dy),
      );
      expect(find.text('2019\u00A0· Series'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Add Dynamo Dream to Sonarr')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Add Project London to Radarr')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Add Tears of Steel')),
        findsNothing,
      );
      expect(find.text('Request'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1, through Seerr by default: the plus asks Seerr for each '
        'title, and never adds to the arr', (tester) async {
      final harness = await _person(tester, Profiles.p1);

      expect(
        find.bySemanticsLabel(RegExp(r'^Request Dynamo Dream')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Request Project London')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Add ')), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1, through Seerr, but Seerr has no Radarr to send a movie '
        'to: the plus adds it to Radarr', (tester) async {
      final harness = await _person(
        tester,
        Profiles.p1,
        overrides: [
          seerrSendsToProvider.overrideWith((ref, arr) async => false),
        ],
      );

      expect(
        find.bySemanticsLabel(RegExp(r'^Add Project London to Radarr')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Request Project London')),
        findsNothing,
      );

      await harness.unmount(tester);
    });

    testWidgets('P5, no Radarr in Cupola: a movie is asked of the Radarr '
        'Seerr knows', (tester) async {
      final harness = await _person(tester, Profiles.p5);

      expect(find.bySemanticsLabel('Request Project London'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Add ')), findsNothing);

      await tester.tap(find.bySemanticsLabel('Request Project London'));
      await tester.pumpAndSettle();
      // The request sheet a title's page opens.
      expect(find.text('Request Project London'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P5 where Seerr knows no Radarr either: the plus stays, '
        'dimmed, and a tap answers with the fix', (tester) async {
      final harness = await _person(
        tester,
        Profiles.p5,
        overrides: [
          seerrSendsToProvider.overrideWith((ref, arr) async => false),
        ],
      );

      final plus = find.bySemanticsLabel('Add Project London');
      expect(plus, findsOneWidget);
      expect(find.text('Request'), findsNothing);
      expect(
        tester.getSemantics(plus),
        // Never `enabled: false`: a screen reader stops on it and hears why.
        containsSemantics(
          label: 'Add Project London',
          hint: 'requires Radarr',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(plus);
      await tester.pump();
      expect(find.text('Radarr is not set up.'), findsOneWidget);
      expect(find.text('Set up Radarr'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P2: she asks, and reads no service but her player', (
      tester,
    ) async {
      final harness = await _person(tester, Profiles.p2);

      expect(find.text('Directed'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Add ')), findsNothing);
      expect(find.textContaining('Seerr'), findsNothing);
      expect(find.textContaining('Radarr'), findsNothing);
      expect(find.textContaining('Sonarr'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
