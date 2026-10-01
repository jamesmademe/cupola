/// Activity's Streaming reads every connection of a media server.
///
/// It read the lens alone: with a Jellyfin at home and one at the cabin, the
/// cabin's viewers were not on Activity at all, and nothing said so. Each
/// connection is now asked, each session says which server it is playing
/// from once there are two, and Stop goes to that server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_activity_section.dart';

import '../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _pump(WidgetTester tester, ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const Scaffold(body: StreamActivitySection(bottomPadding: 0)),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  final twoJellyfin = Profiles.p1.withConnection(
    WorldConnections.jellyfinCabin,
  );

  testWidgets('P1 + the cabin Jellyfin: both servers\' sessions, each named', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = await _pump(tester, twoJellyfin);

    // Anna is watching on both, one card each, and each says which server.
    expect(
      find.text('Anna · Jellyfin Android TV · Living room TV · Jellyfin 1'),
      findsOne,
    );
    expect(
      find.text('Anna · Jellyfin Android TV · Living room TV · Jellyfin Cabin'),
      findsOne,
    );
    // And says it aloud, in the card's one sentence.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.value ?? '').contains('from Jellyfin Cabin'),
      ),
      findsOne,
    );

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('Stop on the cabin\'s session goes to the cabin', (tester) async {
    final harness = await _pump(tester, twoJellyfin);

    // The home server's card first, the cabin's second: the user's order.
    final home = find.textContaining('Jellyfin 1');
    final cabin = find.textContaining('Jellyfin Cabin');
    expect(
      tester.getTopLeft(cabin).dy,
      greaterThan(tester.getTopLeft(home).dy),
    );
    await tester.tap(find.byTooltip('Stop this playback').last);
    await harness.settle(tester);
    await tester.tap(find.text('Stop playback'));
    await harness.settle(tester);

    bool stops(NetworkRequest r) =>
        r.method == 'POST' && r.uri.path.endsWith('/Playing/Stop');
    expect(
      harness.network.requestsTo(WorldIds.jellyfinCabin).where(stops),
      hasLength(1),
    );
    expect(harness.network.requestsTo(WorldIds.jellyfin).where(stops), isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('the cabin dark: the home sessions stay, and the note names '
      'the cabin', (tester) async {
    final harness = await _pump(
      tester,
      twoJellyfin.withBehaviour(
        WorldIds.jellyfinCabin,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    expect(
      find.text('Anna · Jellyfin Android TV · Living room TV · Jellyfin 1'),
      findsOne,
    );
    expect(find.textContaining('Jellyfin Cabin did not answer'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P1: one Jellyfin is named nowhere', (tester) async {
    final harness = await _pump(tester, Profiles.p1);

    expect(find.text('Anna · Jellyfin Android TV · Living room TV'), findsOne);

    await harness.unmount(tester);
  });
}
