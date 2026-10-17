/// An Arrived card says which connection imported it, while the service has
/// more than one.
///
/// One title is one card, so the HD and the 4K copy of one movie are not two
/// identical cards side by side: the card is the newer import's, and its line
/// names the connection that import came to. A service with a single
/// connection names none.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/fakes/arr_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/profiles/service_fakes.dart';

const _phone = Size(375, 1200);

/// Local noon, so a day-old import is "Yesterday" whatever hour the suite runs.
final _now = DateTime(2026, 10, 7, 12);

/// The module alone, as the phone's Home lays it out: the rail is what is
/// under test, and the rest of Home is measured elsewhere.
const _region = Scaffold(
  body: SingleChildScrollView(child: HomeArrivedModule()),
);

Finder _inRail(Finder matching) =>
    find.descendant(of: find.byType(HomeArrivedModule), matching: matching);

/// The card of [title], built even where the rail has not scrolled to it.
Finder _cardOf(String title) => find.byWidgetPredicate(
  (widget) => widget is ArrivedCard && widget.entry.title == title,
  skipOffstage: false,
);

/// The two lines a card draws: its title, then when and where it came.
List<Text> _textsOf(String title) => [
  for (final element
      in find
          .descendant(
            of: _cardOf(title),
            matching: find.byType(Text),
            skipOffstage: false,
          )
          .evaluate())
    element.widget as Text,
];

/// What the card under [title] says under it.
String? _lineOf(String title) => _textsOf(title).last.data;

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileHarness harness)? before,
}) async {
  final harness = await ProfileHarness.start(
    profile,
    now: _now,
    overrides: [
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
    ],
  );
  before?.call(harness);
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: _region),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// A new series on the one Sonarr, imported three hours ago: the world's own
/// Sonarr has none in the week.
void _scriptNewSeries(ProfileHarness harness) {
  final network = harness.network;
  network.on(
    WorldIds.sonarr,
    'GET',
    '/api/v3/history/since',
    (r) => NetworkReply.json([
      ...const SonarrFake().history(
        ServerContext(
          network: network,
          server: network.server(WorldIds.sonarr),
        ),
      ),
      {
        'id': 90,
        'seriesId': 2,
        'episodeId': 2101,
        'eventType': 'downloadFolderImported',
        'sourceTitle': 'Night.Shift.S01E01.1080p.WEB',
        'date': network.now
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'series': {
          'id': 2,
          'title': 'Night Shift',
          'tmdbId': WorldTitles.nightShift.tmdbId,
          'added': network.now
              .subtract(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
          'images': <Object?>[],
        },
        'episode': {'seasonNumber': 1, 'episodeNumber': 1},
      },
    ]),
  );
}

/// Tears of Steel again on the HD Radarr, three days ago: the 4K imported it
/// more recently, a day and two hours ago.
void _scriptOlderCopyOnHd(ProfileHarness harness) {
  final network = harness.network;
  network.on(
    WorldIds.radarr,
    'GET',
    '/api/v3/history/since',
    (r) => NetworkReply.json([
      ...const RadarrFake().history(
        ServerContext(
          network: network,
          server: network.server(WorldIds.radarr),
        ),
      ),
      {
        'id': 77,
        'movieId': 5,
        'eventType': 'downloadFolderImported',
        'date': network.now
            .subtract(const Duration(days: 3))
            .toUtc()
            .toIso8601String(),
        'movie': {
          'id': 5,
          'title': 'Tears of Steel',
          'tmdbId': WorldTitles.tearsOfSteel.tmdbId,
          'added': network.now
              .subtract(const Duration(days: 17))
              .toUtc()
              .toIso8601String(),
        },
      },
    ]),
  );
}

void main() {
  testWidgets('P1 at 375 pt: each Radarr\'s cards name their Radarr, and a '
      'movie on both is the 4K\'s one card', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await _pump(
      tester,
      Profiles.p1,
      before: (harness) {
        _scriptOlderCopyOnHd(harness);
        _scriptNewSeries(harness);
      },
    );

    // Each Radarr card says which Radarr: the 4K's, and the HD's, which
    // nobody named before there were two.
    expect(_lineOf('Spring'), '2\u00A0h ago\u00A0· Radarr 4K');
    expect(_lineOf('Coffee Run'), '2\u00A0h ago\u00A0· Radarr 1');
    // The card is one button, and speaks its title and its line.
    expect(find.bySemanticsLabel('Spring, 2\u00A0h ago, Radarr 4K'), findsOne);
    // The name is one line, and the card keeps its width and its 16:9 art.
    final line = _textsOf('Spring').last;
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(_cardOf('Spring')).width, ArrivedCard.width);
    expect(
      tester.getSize(
        find.descendant(
          of: _cardOf('Spring'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox && widget.height == ArrivedCard.artHeight,
          ),
        ),
      ),
      const Size(ArrivedCard.width, ArrivedCard.artHeight),
    );

    // Further along the rail: Sonarr has one connection, so its card names
    // none, and Tears of Steel, which both Radarr imported, is the 4K's card
    // once, the newer import.
    await tester.drag(_inRail(find.byType(ListView)), const Offset(-400, 0));
    await tester.pump();
    expect(_lineOf('Night Shift'), '3\u00A0h ago');
    expect(_inRail(find.text('Sonarr')), findsNothing);
    expect(_inRail(find.text('Tears of Steel')), findsOne);
    expect(_lineOf('Tears of Steel'), 'Yesterday\u00A0· Radarr 4K');
    expect(tester.takeException(), isNull);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P4 at 375 pt: one Radarr, no name, and the title keeps its '
      'one line', (tester) async {
    final harness = await _pump(tester, Profiles.p4);

    final title = _textsOf('Coffee Run').first;
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    // Only when it arrived: with one connection there is none to tell apart.
    expect(_lineOf('Coffee Run'), '2\u00A0h ago');
    expect(_inRail(find.textContaining('Radarr')), findsNothing);
    expect(tester.getSize(_cardOf('Coffee Run')).width, ArrivedCard.width);

    await harness.unmount(tester);
  });
}
