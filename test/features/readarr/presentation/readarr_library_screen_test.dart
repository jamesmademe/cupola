import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

/// Four authors, one of them with no `statistics` at all (a Readarr that has
/// not scanned them yet), written so that every order answers differently:
///
/// * by name: McCaffrey, Sanderson, Tolkien, Le Guin;
/// * by date added, newest first: Tolkien, Sanderson, Le Guin, then
///   McCaffrey, whom Readarr never dated;
/// * by size, largest first: Tolkien, Sanderson, Le Guin, McCaffrey.
List<Map<String, dynamic>> _library() => [
  {
    'id': 1,
    'authorName': 'Brandon Sanderson',
    'monitored': true,
    'added': '2026-03-01T09:30:00Z',
    'statistics': {
      'bookCount': 20,
      'bookFileCount': 15,
      'sizeOnDisk': 5000000000,
    },
  },
  {
    'id': 2,
    'authorName': 'J.R.R. Tolkien',
    'monitored': false,
    'added': '2026-05-10T09:30:00Z',
    'statistics': {
      'bookCount': 10,
      'bookFileCount': 10,
      'sizeOnDisk': 9000000000,
    },
  },
  {
    'id': 3,
    'authorName': 'Ursula K. Le Guin',
    'monitored': true,
    'added': '2025-12-01T09:30:00Z',
    'statistics': {
      'bookCount': 12,
      'bookFileCount': 3,
      'sizeOnDisk': 1000000000,
    },
  },
  {'id': 4, 'authorName': 'Anne McCaffrey', 'monitored': true},
];

const _mccaffrey = 'Anne McCaffrey';
const _sanderson = 'Brandon Sanderson';
const _tolkien = 'J.R.R. Tolkien';
const _leGuin = 'Ursula K. Le Guin';

Future<void> _pump(
  WidgetTester tester,
  FakeApiClient api, {
  bool configured = true,
}) async {
  // Tall enough for the four letter sections: the wall builds its rows as
  // they scroll in.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(
            configured ? const [ServiceKey.readarr] : const [],
          ),
        ),
        readarrServiceProvider.overrideWith((ref) => ReadarrService(api)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const ReadarrLibraryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// [names] in the order the wall reads them: top to bottom, then left to
/// right.
List<String> _reading(WidgetTester tester, List<String> names) {
  final at = {
    for (final name in names) name: tester.getTopLeft(find.text(name)),
  };
  return names.toList()..sort((a, b) {
    final byRow = at[a]!.dy.compareTo(at[b]!.dy);
    return byRow != 0 ? byRow : at[a]!.dx.compareTo(at[b]!.dx);
  });
}

Future<void> _sortBy(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Change sort order'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('readarrAuthorCaption', () {
    ReadarrAuthor author(int books, int files) => ReadarrAuthor(
      id: 1,
      authorName: 'A',
      monitored: true,
      bookCount: books,
      bookFileCount: files,
    );

    test('says how many books are on disk, and how many are missing', () {
      expect(
        readarrAuthorCaption(author(12, 3)),
        '3/12 books${dotSeparator}9 missing',
      );
    });

    test('leaves the missing part out when nothing is', () {
      expect(readarrAuthorCaption(author(10, 10)), '10/10 books');
    });

    test('an author with no book counted is an em dash, not 0/0', () {
      // Readarr omits `statistics` on an author it has not scanned, and the
      // model reads an absent count as zero: `0/0 books` would assert a
      // fact nobody reported.
      expect(readarrAuthorCaption(author(0, 0)), '—');
    });
  });

  group('the Library tab', () {
    testWidgets('draws every author on the shared wall, in a circle, with '
        'the counts the row always had', (tester) async {
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      expect(find.byType(MediaBrowseScaffold<ReadarrAuthor>), findsOneWidget);
      for (final name in [_mccaffrey, _sanderson, _tolkien, _leGuin]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('15/20 books${dotSeparator}5 missing'), findsOneWidget);
      expect(find.text('10/10 books'), findsOneWidget);
      expect(find.text('3/12 books${dotSeparator}9 missing'), findsOneWidget);
      // The unscanned author's caption is the figure that did not answer.
      expect(find.text('—'), findsOneWidget);
      // Four portraits: a person is not a poster.
      expect(find.byType(ClipOval), findsNWidgets(4));
      // The title stays Authors, and the rail is above the wall.
      expect(
        find.descendant(
          of: find.byType(GlassAppBar),
          matching: find.text('Authors'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ServiceKpiPeek), findsOneWidget);
    });

    testWidgets('is lettered by name, A to Z, by default', (tester) async {
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      expect(_reading(tester, [_sanderson, _leGuin, _mccaffrey, _tolkien]), [
        _mccaffrey,
        _sanderson,
        _tolkien,
        _leGuin,
      ]);
      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsOneWidget,
      );
    });

    testWidgets('sorts by the date Readarr added them, newest first, the '
        'undated last', (tester) async {
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      await _sortBy(tester, 'Date added');

      expect(_reading(tester, [_sanderson, _leGuin, _mccaffrey, _tolkien]), [
        _tolkien,
        _sanderson,
        _leGuin,
        _mccaffrey,
      ]);
      // A date order is one unheaded run.
      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsNothing,
      );
    });

    testWidgets('sorts by size on disk, largest first', (tester) async {
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      await _sortBy(tester, 'Size');

      expect(_reading(tester, [_sanderson, _leGuin, _mccaffrey, _tolkien]), [
        _tolkien,
        _sanderson,
        _leGuin,
        _mccaffrey,
      ]);
    });

    testWidgets('offers no chip that asks a status, since it resolves none', (
      tester,
    ) async {
      // Readarr's queue is indexed by book, not by author, so an author's
      // status would ignore it. With no status, Missing would list every
      // author and Available and In queue none.
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      // Not by label: the rail above the wall has a Missing figure of its
      // own. The chips are the scaffold's own widget.
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_MediaBrowseFilterChip',
        ),
        findsNothing,
      );
      // The sort control is still the strip's.
      expect(find.byTooltip('Change sort order'), findsOneWidget);
    });

    testWidgets('each author speaks one sentence: the name, then the counts', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      final tile = find.bySemanticsLabel(_sanderson);
      expect(tile, findsOneWidget);
      final node = tester.getSemantics(tile);
      expect(node.value, '15/20 books${dotSeparator}5 missing');
      // The caption beneath is not read a second time.
      expect(find.bySemanticsLabel(RegExp('15/20 books')), findsNothing);
      semantics.dispose();
    });

    testWidgets('searches the library it holds, whatever the case and the '
        'order of the words', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, FakeApiClient()..getResponseData = _library());

      await tester.enterText(find.byType(TextField), 'tolkien j.r.r.');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(MediaGrid<ReadarrAuthor>), findsOneWidget);
      expect(find.bySemanticsLabel(_tolkien), findsOneWidget);
      expect(find.bySemanticsLabel(_sanderson), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Readarr found nothing for “zzz”'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a Readarr that does not answer says so instead of claiming '
        'an empty library', (tester) async {
      final api = FakeApiClient()
        ..getException = DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/author'),
          reason: 'Connection refused',
        );

      await _pump(tester, api);

      // The error branch was written and never reachable: `getAuthors`
      // answered a dead server with `[]`, which this screen drew as an empty
      // library.
      expect(find.text('Your Readarr library is empty'), findsNothing);
      expect(find.byType(ServiceOfflineState), findsOneWidget);
      expect(find.text('Readarr did not answer'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('an empty library says where authors come from', (
      tester,
    ) async {
      await _pump(tester, FakeApiClient()..getResponseData = const []);

      expect(find.text('Your Readarr library is empty'), findsOneWidget);
      expect(find.text('Authors are added in Readarr itself.'), findsOneWidget);
      // A book, not the film strip the other libraries draw.
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    });

    testWidgets('a Readarr that was never set up says so, at its own form, '
        'and asks nothing of it', (tester) async {
      final api = FakeApiClient()..getResponseData = _library();

      await _pump(tester, api, configured: false);

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(MediaBrowseScaffold<ReadarrAuthor>), findsNothing);
      expect(api.getCallCount, 0);
    });
  });

  group('a tap', () {
    testWidgets('opens the author on the connection the wall shows, with the '
        'author and the photo\'s hero tag', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.readarr),
      );
      harness.network.followFakeTime(tester.binding);
      Uri? opened;
      Object? extra;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const ReadarrLibraryScreen(),
          ),
          GoRoute(
            path: '${ServiceRoutes.readarrAuthorBase}/:id',
            builder: (context, state) {
              opened = state.uri;
              extra = state.extra;
              return const Scaffold(body: Text('the author'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp.router(
            theme: AppTheme.darkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await harness.settle(tester);

      // What the profile's own client read: six of seven on disk.
      expect(find.text('6/7 books${dotSeparator}1 missing'), findsOneWidget);

      await tester.tap(find.text('Jules Verne'));
      await tester.pumpAndSettle();

      expect(find.text('the author'), findsOneWidget);
      expect(opened?.path, '${ServiceRoutes.readarrAuthorBase}/1');
      // The connection's id rides in the query, as every link to a page
      // under a lens does: the page reads this Readarr's copy.
      expect(opened?.queryParameters['i'], 'readarr');
      expect(opened?.queryParameters['heroTag'], startsWith('author_1_'));
      expect(extra, isA<ReadarrAuthor>());
      expect((extra! as ReadarrAuthor).authorName, 'Jules Verne');

      await harness.unmount(tester);
    });
  });
}
