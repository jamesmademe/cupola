/// Activity's Streaming names a media server it could not read in the words
/// and tone of what happened.
///
/// The note said "did not answer", in red, for every failure, a refused token
/// included: red is for a server that did not answer and nothing else, and a
/// refusal sent the user to check a server that had just answered. The note
/// now takes its tone and words from the classification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_activity_section.dart';

import '../../test_helpers/profiles/profiles.dart';

/// P1 with its Plex set up on a token Plex refuses, and the cabin's Jellyfin
/// set up but silent, beside the Jellyfin at home that answers.
final _profile = Profiles.p1
    .withConnection(
      WorldConnections.plex.withBehaviour(ConnectionBehaviour.refusesKey),
    )
    .withConnection(
      WorldConnections.jellyfinCabin.withBehaviour(
        ConnectionBehaviour.didNotAnswer,
      ),
    );

/// The glyph's colour on the line that reads [message].
Color? _glyphOf(WidgetTester tester, String message) {
  final line = find.ancestor(
    of: find.text(message),
    matching: find.byType(Row),
  );
  return tester
      .widget<Icon>(
        find.descendant(of: line.first, matching: find.byType(Icon)),
      )
      .color;
}

void main() {
  testWidgets('a refused token is amber in its own words; a server that did '
      'not answer is red', (tester) async {
    final harness = await ProfileHarness.start(_profile);
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

    const refused = 'Plex answered but refused the token.';
    const silent = 'Jellyfin Cabin did not answer.';
    expect(find.text(refused), findsOneWidget);
    expect(find.text(silent), findsOneWidget);
    // Never said to be silent when it answered.
    expect(find.textContaining('Plex did not answer'), findsNothing);
    expect(find.textContaining('Plex and'), findsNothing);
    // The answering Jellyfin's session is still there.
    expect(find.text(WorldTitles.sintel.title), findsOneWidget);

    final colorScheme = Theme.of(
      tester.element(find.text(refused)),
    ).colorScheme;
    expect(
      _glyphOf(tester, refused),
      statusToneColor(colorScheme, StatusTone.warning),
    );
    expect(
      _glyphOf(tester, silent),
      statusToneColor(colorScheme, StatusTone.error),
    );
    await harness.unmount(tester);
  });
}
