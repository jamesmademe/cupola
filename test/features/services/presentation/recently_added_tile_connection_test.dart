/// On the phone, a Recently added tile says which connection imported it.
///
/// The desktop rows already did, in their subtitle. The phone's tiles carry
/// only a poster and a title, so the HD and the 4K copy of one movie were two
/// identical tiles side by side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _phone = Size(375, 1200);

/// The region alone, as the phone's Home lays it out: the rail is what is
/// under test, and the rest of Home is measured elsewhere.
const _region = Scaffold(
  body: SingleChildScrollView(child: ServicesRecentlyAddedSection()),
);

Finder _inRail(Finder matching) => find.descendant(
  of: find.byType(ServicesRecentlyAddedSection),
  matching: matching,
);

/// The tile's own box: the 60×90 the poster and its scrim live in.
Finder _tileOf(String title) => find
    .ancestor(of: _inRail(find.text(title)), matching: find.byType(SizedBox))
    .first;

/// The texts under [title] on its tile, the title itself left out.
List<String?> _namesUnder(String title) =>
    _namesUnderElement(_inRail(find.text(title)).evaluate().single);

List<String?> _namesUnderElement(Element title) {
  final column = find
      .ancestor(
        of: find.byElementPredicate((e) => e == title),
        matching: find.byType(Column),
      )
      .first;
  return [
    for (final text
        in find
            .descendant(of: column, matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data))
      if (text != (title.widget as Text).data) text,
  ];
}

void main() {
  testWidgets('P1 at 375 pt: the two Tears of Steel tiles name their Radarr', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: _region,
      surfaceSize: _phone,
    );

    // Each Radarr tile says which Radarr: the 4K's, and the HD's, which
    // nobody named.
    expect(_namesUnder('Spring'), ['Radarr 4K']);
    expect(_namesUnder('Coffee Run'), ['Radarr 1']);
    expect(_namesUnder('Tears of Steel'), ['Radarr 4K']);
    // The name is one line, and the tile keeps its 60×90.
    final name = tester.widget<Text>(_inRail(find.text('Radarr 4K')).first);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(_tileOf('Spring')), const Size(60, 90));
    // The HD's copy of the same movie, one tile further along the rail.
    await tester.drag(_inRail(find.byType(ListView)), const Offset(-300, 0));
    await tester.pump();
    expect(_inRail(find.text('Tears of Steel')), findsNWidgets(2));
    expect(
      _inRail(
        find.text('Tears of Steel'),
      ).evaluate().map((title) => _namesUnderElement(title)),
      unorderedEquals([
        ['Radarr 4K'],
        ['Radarr 1'],
      ]),
    );
    // Sonarr has one connection, so its tile names none.
    expect(_inRail(find.text('Cosmos Laundromat')), findsOne);
    expect(_inRail(find.text('Sonarr')), findsNothing);
    expect(tester.takeException(), isNull);

    await harness.unmount(tester);
  });

  testWidgets('P4 at 375 pt: one Radarr, no name, and the title keeps its '
      'two lines', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p4,
      child: _region,
      surfaceSize: _phone,
    );

    final title = tester.widget<Text>(_inRail(find.text('Coffee Run')));
    expect(title.maxLines, 2);
    expect(_inRail(find.text('Radarr')), findsNothing);
    expect(tester.getSize(_tileOf('Coffee Run')), const Size(60, 90));

    await harness.unmount(tester);
  });
}
