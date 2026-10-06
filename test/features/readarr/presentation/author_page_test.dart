/// An author's page on the profiles' Readarr: Jules Verne, seven books, six
/// on disk and one wanted, as the board draws them.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/readarr/presentation/author_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

final _profile = Profiles.p1.withConnection(WorldConnections.readarr);
const _readarr = 'readarr';

Future<ProfileHarness> _open(
  WidgetTester tester, {
  void Function(ProfileHarness harness)? arrange,
  Size size = const Size(800, 3200),
  double textScale = 1,
}) async {
  final harness = await ProfileHarness.start(_profile);
  harness.network.followFakeTime(tester.binding);
  arrange?.call(harness);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const MaterialApp(home: AuthorPage(authorId: 1)),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// The name in the page's identity, not on a cover.
Finder _name(String name) =>
    find.descendant(of: find.byType(ShelfIdentity), matching: find.text(name));

void main() {
  testWidgets('as the board draws it: who, the books by year, the one '
      'wanted, the settings', (tester) async {
    final harness = await _open(tester);

    expect(_name('Jules Verne'), findsOneWidget);
    expect(find.text('JV'), findsOneWidget);
    expect(
      find.text('7\u00A0books · 6\u00A0on disk · 1\u00A0wanted'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Readarr is no longer maintained;'),
      findsOneWidget,
    );
    expect(find.text('by year'), findsOneWidget);

    // By year, the oldest first, three to a row.
    Offset at(String title) => tester.getTopLeft(find.text(title).first);
    expect(
      at('Five Weeks in a Balloon').dx,
      lessThan(
        at(
          'Journey to the '
          'Centre of the Earth',
        ).dx,
      ),
    );
    expect(
      at('Twenty Thousand Leagues Under the Seas').dy,
      greaterThan(at('Five Weeks in a Balloon').dy),
    );
    expect(find.text('1876'), findsOneWidget);

    expect(find.text('Wanted · no file yet'), findsOneWidget);
    expect(find.text('1863 · quality profile eBook'), findsOneWidget);
    expect(find.text('Search for this book'), findsOneWidget);

    expect(
      find.text('Readarr looks for missing books by this author'),
      findsOneWidget,
    );
    expect(find.text('eBook'), findsOneWidget);
    expect(find.text('/mnt/user/media/books/Jules Verne'), findsOneWidget);
    expect(find.text('Open in Readarr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a wanted book is searched for on the page\'s Readarr', (
    tester,
  ) async {
    final harness = await _open(tester);

    await tester.tap(find.text('Search for this book'));
    await harness.settle(tester);

    final command = harness.network
        .requestsTo(_readarr)
        .where((r) => r.method == 'POST' && r.path == '/api/v1/command')
        .single;
    expect(jsonDecode(command.body), {
      'name': 'BookSearch',
      'bookIds': [1],
    });
    expect(
      find.text('Readarr is searching for Five Weeks in a Balloon'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('over a queue that did not answer, a book not on disk is not '
      'Wanted: it may be downloading', (tester) async {
    final harness = await _open(
      tester,
      arrange: (harness) => harness.network.on(
        _readarr,
        'GET',
        '/api/v1/queue',
        (_) => NetworkReply.json({'message': 'boom'}, status: 500),
      ),
    );

    expect(find.text('Wanted · no file yet'), findsNothing);
    expect(find.text('Unknown'), findsNWidgets(2));

    await harness.unmount(tester);
  });

  testWidgets('Monitored off writes the page\'s Readarr', (tester) async {
    Object? written;
    final harness = await _open(
      tester,
      arrange: (harness) => harness.network
        ..on(_readarr, 'PUT', '/api/v1/author/1', (r) {
          written = r.json;
          return NetworkReply.json(written);
        })
        ..on(
          _readarr,
          'GET',
          '/api/v1/author/1',
          (_) => written == null ? null : NetworkReply.json(written),
        ),
    );

    await tester.tap(find.text('Monitored'));
    await harness.settle(tester);

    expect((written! as Map)['monitored'], isFalse);
    expect(
      find.text('Readarr has stopped monitoring this author'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('removing asks what it takes, then removes from the page\'s '
      'Readarr', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _open(
      tester,
      arrange: (harness) => harness.network.on(
        _readarr,
        'DELETE',
        '/api/v1/author/1',
        (_) => NetworkReply.json(const <String, Object?>{}),
      ),
    );

    await tester.tap(find.bySemanticsLabel('More actions for Jules Verne'));
    await harness.settle(tester);
    expect(find.text('Search for every wanted book'), findsOneWidget);
    await tester.tap(find.text('Remove from Readarr'));
    await harness.settle(tester);

    expect(find.text('Remove Jules Verne from Readarr?'), findsOneWidget);
    expect(find.text('Readarr stops looking for their books.'), findsOneWidget);

    await tester.tap(find.text('Remove from Readarr').last);
    await harness.settle(tester);

    expect(
      harness.network.requestsTo(_readarr).where((r) => r.method == 'DELETE'),
      hasLength(1),
    );

    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('an author that could not be read says why, and Retry reads '
      'them again', (tester) async {
    var failing = true;
    final harness = await _open(
      tester,
      arrange: (harness) => harness.network.on(
        _readarr,
        'GET',
        '/api/v1/author/1',
        (_) => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : null,
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);

    failing = false;
    await tester.tap(find.text('Retry'));
    await harness.settle(tester);

    expect(_name('Jules Verne'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('at twice the reading size the books go two to a row, and '
      'nothing overflows', (tester) async {
    final harness = await _open(
      tester,
      size: const Size(390, 4000),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    Offset at(String title) => tester.getTopLeft(find.text(title).first);
    // The third book starts the second row.
    expect(
      at('From the Earth to the Moon').dy,
      greaterThan(at('Five Weeks in a Balloon').dy),
    );

    await harness.unmount(tester);
  });
}
