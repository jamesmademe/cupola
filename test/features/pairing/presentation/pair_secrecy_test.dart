/// What the two pairing screens hold and say never includes the key or a
/// secret of a connection: not in a state's text, not in a notice, not in the
/// source of the screens themselves.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';

import '../../../test_helpers/pair_fixtures.dart';

void main() {
  final secrets = [
    pairFixtureKey,
    'radarr-fixture-key',
    'sonarr-fixture-key',
    'seerr-fixture-session',
    'fixture-secret',
  ];

  test('no state of either screen prints the link, a key or a secret', () {
    final plan = pairFixturePlan();
    final package = pairFixturePackage();
    final link = pairFixtureLink();
    final said = [
      PairOfferOpen(link: link, package: package),
      PairOfferSent(package),
      const PairOfferClosed(PairServerEnd.expired),
      const PairOfferPreparing(),
      const PairOfferNoNetwork(),
      const PairOfferFailed(),
      const PairReceiveWaiting(),
      const PairReceiveFetching(),
      PairReceivePreview(plan),
      PairReceiveAdding(plan),
      PairReceiveAdded(plan),
      for (final f in PairReceiveFailure.values) PairReceiveFailed(f),
      PairArrival(link),
      const PairArrival(null),
      link,
      package,
      for (final c in plan.toAdd) c,
    ].map((state) => state.toString()).join('\n');

    for (final secret in secrets) {
      expect(said, isNot(contains(secret)));
    }
    expect(said, isNot(contains('k=')));
  });

  test('every word the screens say is free of them', () {
    final plan = pairFixturePlan();
    final said = [
      for (final m in pairMovesOf(pairFixturePackage()))
        '${m.title} ${m.detail}',
      for (final f in PairReceiveFailure.values)
        '${f.notice.headline} ${f.notice.sentence}',
      pairPlanCounts(plan),
      pairAddLabel(plan),
      ...pairPlanNotes(plan),
    ].join('\n');

    for (final secret in secrets) {
      expect(said, isNot(contains(secret)));
    }
  });

  test('the screens write the key nowhere but into the code and the '
      'clipboard', () {
    // The one place the link is written out is the sending screen's QR and
    // its Copy link: `toLink()` is read there and nowhere else in the pages.
    final reads = <String>[];
    for (final file in Directory(
      'lib/features/pairing/presentation',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final count = RegExp(r'\.toLink\(\)').allMatches(source).length;
      if (count > 0) reads.add('${file.path}: $count');
    }
    expect(reads, [
      'lib/features/pairing/presentation/pair_offer_screen.dart: 2',
    ]);
  });
}
