/// A search source that stopped says so on one quiet line above the answer,
/// and offers what its cause allows, as every failure line does: the remedy the cause names in the amber fill, `Retry` only where
/// the same request can still succeed, and beside a red lane `Retry` as text
/// in ink.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _search(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  final harness = await pumpWithProfile(
    tester,
    profile,
    child: const DiscoverPage(),
    overrides: [globalSearchQueryProvider.overrideWith((ref) => 'sprite')],
    surfaceSize: const Size(430, 2400),
  );
  return harness;
}

/// The [T] whose label a screen reader hears as [label].
Finder _button<T extends Widget>(String label) =>
    find.ancestor(of: find.bySemanticsLabel(label), matching: find.byType(T));

/// Lets a slow answer the lane already gave up on arrive, so no timer is left
/// pending when the tree comes down.
Future<void> _drain(WidgetTester tester, ProfileHarness harness) async {
  await tester.pump(const Duration(seconds: 40));
  await harness.unmount(tester);
}

void main() {
  testWidgets('P8, Sonarr with no token: the lane offers Add a service token '
      'in the amber fill, and no Retry', (tester) async {
    final harness = await _search(tester, Profiles.p8);

    expect(
      find.text(
        'No Sonarr results: Cloudflare Access answered instead of Sonarr.',
      ),
      findsOneWidget,
    );
    final remedy = find.widgetWithText(FilledButton, 'Add a service token');
    expect(remedy, findsOneWidget);
    final room = CupolaRoom.of(tester.element(remedy));
    expect(
      tester
          .widget<FilledButton>(remedy)
          .style
          ?.backgroundColor
          ?.resolve(const {}),
      room.toneAmberFill,
    );
    // It names the server it fixes, for a screen with seven of these.
    expect(
      find.bySemanticsLabel('Add a service token for Sonarr'),
      findsOneWidget,
    );
    // The same request meets the same gateway: nothing to retry.
    expect(find.bySemanticsLabel('Retry Sonarr'), findsNothing);
    // A remedy is a phrase: it takes the row under the sentence, so the
    // sentence keeps the card's width instead of a third of it.
    final sentence = find.text(
      'No Sonarr results: Cloudflare Access answered instead of Sonarr.',
    );
    expect(
      tester.getTopLeft(remedy).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(sentence).dy),
    );
    // Seerr's token, sent and refused: the token is the fix, not a Retry.
    expect(find.bySemanticsLabel('Check the token for Seerr'), findsOneWidget);
    expect(find.bySemanticsLabel('Retry Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P8: a stopped source states its cause once, on its line', (
    tester,
  ) async {
    // A heading once said `Behind Cloudflare Access` one line above a card
    // that said `Cloudflare Access answered instead of Sonarr`: the same
    // cause, twice, with the remedy beside only one of them.
    final harness = await _search(tester, Profiles.p8);

    expect(
      find.text(
        'No Sonarr results: Cloudflare Access answered instead of Sonarr.',
      ),
      findsOneWidget,
    );
    expect(find.text('Behind Cloudflare Access'), findsNothing);
    expect(find.text('Service token not accepted'), findsNothing);
    // Each stopped source's cause, on screen once: in its line's sentence.
    expect(find.textContaining('Cloudflare Access'), findsNWidgets(2));

    await harness.unmount(tester);
  });

  testWidgets('P1, a Sonarr lane that timed out: Retry in the amber fill, no '
      'remedy', (tester) async {
    final harness = await _search(
      tester,
      Profiles.p1.withLatency(WorldIds.sonarr, const Duration(seconds: 30)),
    );

    expect(
      find.text('No Sonarr results: the search timed out.'),
      findsOneWidget,
    );
    final retry = _button<FilledButton>('Retry Sonarr');
    expect(retry, findsOneWidget);
    final room = CupolaRoom.of(tester.element(retry));
    expect(
      tester
          .widget<FilledButton>(retry)
          .style
          ?.backgroundColor
          ?.resolve(const {}),
      room.toneAmberFill,
    );
    expect(find.bySemanticsLabel('Retry Sonarr'), findsOneWidget);
    expect(find.textContaining('Retry is per lane'), findsNothing);

    await _drain(tester, harness);
  });

  testWidgets('P1, a Sonarr that did not answer: Retry as text in ink, never '
      'filled, never red', (tester) async {
    final harness = await _search(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.sonarr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    expect(
      find.text('No Sonarr results: Sonarr did not answer.'),
      findsOneWidget,
    );
    expect(_button<FilledButton>('Retry Sonarr'), findsNothing);
    final retry = _button<TextButton>('Retry Sonarr');
    expect(retry, findsOneWidget);
    final scheme = Theme.of(tester.element(retry)).colorScheme;
    expect(
      tester
          .widget<TextButton>(retry)
          .style
          ?.foregroundColor
          ?.resolve(const {}),
      scheme.primary,
    );
    // The target holds at 44pt, at standard density.
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(
      tester.widget<TextButton>(retry).style?.visualDensity,
      VisualDensity.standard,
    );

    await harness.unmount(tester);
  });
}
