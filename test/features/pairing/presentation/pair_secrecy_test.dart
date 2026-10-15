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
    'seerr-fixture-key',
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
      // An invite shown in person, which carries what a gateway asks for.
      const PairReceiveFetching(invite: true),
      for (final f in PairReceiveFailure.values)
        PairReceiveFailed(f, invite: true),
      const PairReceiveInvited(),
      PairReceiveInvited(
        here: pairFixtureInvitePackage().connections.single,
        updated: true,
      ),
      pairFixtureInvitePackage(),
      pairFixtureInvitePackage().asInvite()!,
      pairFixtureInvitePackage().connections.single,
      pairFixtureLink(invite: true),
      PairOfferOpen(
        link: pairFixtureLink(invite: true),
        package: pairFixtureInvitePackage(),
      ),
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
      for (final f in PairReceiveFailure.values)
        '${f.inviteNotice.headline} ${f.inviteNotice.sentence}',
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
    // The places a pairing link is written out: the sending screen's QR and
    // its Copy link, and the QR of the invite shown in person (which has no
    // Copy link). `link.toLink()` is read there and nowhere else in the
    // pages; the invite sheet's other `toLink()` is the link of an invite,
    // which holds no secret.
    final reads = <String>[];
    final pages = [
      ...Directory(
        'lib/features/pairing/presentation',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      File('lib/features/settings/presentation/widgets/invite_sheet.dart'),
    ];
    for (final file in pages) {
      final source = file.readAsStringSync();
      final count = RegExp(r'\blink\.toLink\(\)').allMatches(source).length;
      if (count > 0) reads.add('${file.path}: $count');
    }
    expect(reads..sort(), [
      'lib/features/pairing/presentation/pair_offer_screen.dart: 2',
      'lib/features/settings/presentation/widgets/invite_sheet.dart: 1',
    ]);
  });
}
