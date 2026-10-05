/// The requester's sweep: every surface a household member reaches, under
/// each way she signs in, read for what she must never meet.
///
/// No service is named but the players she watches with, no operator's word
/// (an API key, a queue, an indexer, a quality profile, a root folder, an
/// instance), no operator's control (Manage, Approve, Decline, the request
/// sheet's pickers), and nobody else's name. A Seerr that does not answer is
/// one line with its time, never the classification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/collection_detail_screen.dart';
import 'package:cupola/features/discover/presentation/discover_screen.dart';
import 'package:cupola/features/discover/presentation/discover_see_all_screen.dart';
import 'package:cupola/features/discover/presentation/person_detail_screen.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/fakes/media_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// Words the requester never reads (the brand book's requester section).
/// `release` is left out: the page's TMDB release dates are hers to read, and
/// the word she must not meet, a download's release name, is a service's.
final _never = <RegExp>[
  for (final service in ServiceKey.values)
    if (service != ServiceKey.jellyfin && service != ServiceKey.plex)
      RegExp(RegExp.escape(service.title)),
  RegExp(r'\bAPI key\b', caseSensitive: false),
  RegExp(r'\bqueue\b', caseSensitive: false),
  RegExp(r'\bindexers?\b', caseSensitive: false),
  RegExp(r'\bquality profile\b', caseSensitive: false),
  RegExp(r'\broot folder\b', caseSensitive: false),
  RegExp(r'\binstance\b', caseSensitive: false),
  RegExp(r'^(Manage|Approve|Decline|Server)$'),
  RegExp(r'\b(Approve|Decline) request\b'),
  // The operator's words for a request that cannot be made: the requester's
  // button reads `Didn't go through` and `Can't be requested`.
  RegExp(r'^Request failed$'),
  // Seerr's and the download's state words on a badge: the requester's read
  // `On the server`, `On its way`, `Blocked` and the rest.
  RegExp(
    r'^(4K: )?(Available|Partially available|Processing|Blocklisted|Deleted|'
    r'Unknown|Queued|Stuck|Failed|Import blocked|Client unavailable)$',
  ),
  RegExp(r'\bAll services\b'),
  RegExp(r'\bacross every service\b', caseSensitive: false),
  RegExp(r'\bconnections? asked\b'),
  // Somebody else's name: Luca's request is not hers to see.
  RegExp(WorldPeople.luca),
];

/// Every word on screen, tooltips included.
List<String> _words(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
  for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
    rich.text.toPlainText(),
  for (final tip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
    tip.message ?? '',
];

void _expectNothingOfTheOperators(WidgetTester tester, String where) {
  final met = <String>[
    for (final word in _words(tester))
      for (final pattern in _never)
        if (pattern.hasMatch(word)) '"$word" (${pattern.pattern})',
  ];
  expect(met, isEmpty, reason: where);
}

final _pages = <String, Widget>{
  'the Discover tab': const DiscoverScreen(showAppBar: false),
  // The one page a title has: the requester's reads no service but the
  // players, and no copy's fault, whatever the household holds.
  'the Media page, a movie of hers': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.charge.tmdbId),
  ),
  "the Media page, Luca's movie": MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.metropolis.tmdbId),
  ),
  'the Media page, a stuck download': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId),
  ),
  'the Media page, a movie on the server': MediaPage(
    mediaKey: MediaKey.movie(WorldTitles.tearsOfSteel.tmdbId),
  ),
  'the Media page, a series with a season to ask for': MediaPage(
    mediaKey: MediaKey.tv(WorldTitles.nightShift.tmdbId),
  ),
  'the Media page, a series on the server in part': MediaPage(
    mediaKey: MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
  ),
  'a person': const PersonDetailScreen(personId: SeerrFake.personId),
  'a collection': const CollectionDetailScreen(
    collectionId: SeerrFake.collectionId,
  ),
  'See all': const DiscoverSeeAllScreen(type: 'movies', title: 'Movies'),
  'the request sheet, a movie': Scaffold(
    body: SingleChildScrollView(
      child: RequestBottomSheet(
        mediaId: WorldTitles.bigBuckBunny.tmdbId,
        mediaType: 'movie',
        onRequestComplete: () {},
      ),
    ),
  ),
  'the request sheet, a series': Scaffold(
    body: SingleChildScrollView(
      child: RequestBottomSheet(
        mediaId: WorldTitles.agent327.tmdbId,
        mediaType: 'tv',
        onRequestComplete: () {},
      ),
    ),
  ),
  'the global search': const SearchScreen(),
};

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget page,
) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        globalSearchQueryProvider.overrideWith((ref) => 'sprite'),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  for (final profile in [
    Profiles.p2,
    Profiles.p2ViaJellyfin,
    Profiles.p2ViaPlex,
  ]) {
    for (final MapEntry(key: name, value: page) in _pages.entries) {
      testWidgets('${profile.id}: $name', (tester) async {
        final harness = await _pump(tester, profile, page);

        _expectNothingOfTheOperators(tester, '${profile.id}, $name');

        await harness.unmount(tester);
      });
    }
  }

  testWidgets('the sweep sees the operator\'s words where they are (P3)', (
    tester,
  ) async {
    // A scan that read nothing would pass every sweep above.
    final harness = await _pump(
      tester,
      Profiles.p3,
      _pages['the Media page, a movie of hers']!,
    );

    final met = [
      for (final word in _words(tester))
        for (final pattern in _never)
          if (pattern.hasMatch(word)) word,
    ];
    expect(met, containsAll(['Approve', 'Decline', 'Seerr']));

    await harness.unmount(tester);
  });

  group('a Seerr that does not answer', () {
    final silent = Profiles.p2.withBehaviour(
      WorldIds.seerr,
      ConnectionBehaviour.didNotAnswer,
    );
    final line = RegExp(r"^Can't reach the server since \d\d:\d\d\.?$");

    for (final name in [
      'the Discover tab',
      'the Media page, a movie of hers',
      'the global search',
    ]) {
      testWidgets('P2: $name says one line with its time, and Retry', (
        tester,
      ) async {
        final harness = await _pump(tester, silent, _pages[name]!);

        final lines = [
          for (final word in _words(tester))
            if (line.hasMatch(word)) word,
        ];
        expect(lines, isNotEmpty);
        expect(find.text('Retry'), findsWidgets);
        expect(find.textContaining('did not answer'), findsNothing);
        _expectNothingOfTheOperators(tester, 'P2 silent, $name');

        await harness.unmount(tester);
      });
    }
  });
}
