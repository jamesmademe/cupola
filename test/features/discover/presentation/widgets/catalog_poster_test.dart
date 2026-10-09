import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';

const _sintel = MediaPreview(
  id: 45745,
  title: 'Sintel',
  mediaType: 'movie',
  voteAverage: 7.4,
  mediaInfo: {'status': 5},
);

Future<void> _pump(
  WidgetTester tester,
  MediaPreview item, {
  Audience audience = Audience.operator,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audienceProvider.overrideWithValue(audience),
        seerrNumberingProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                // The rail's own height for this width: what the tile asks
                // for is what it is given.
                child: SizedBox(
                  height: CatalogPoster.heightFor(context, 104),
                  child: CatalogPoster(
                    item: item,
                    heroTag: 'poster_${item.id}',
                    width: 104,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a title Seerr holds wears its state, its name and its score', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _sintel);

    expect(find.byType(StatusBadge), findsOneWidget);
    expect(find.text('Sintel'), findsOneWidget);
    expect(find.text('TMDB\u00A07.4'), findsOneWidget);
    // One sentence for the tile: the title, then its state and score.
    expect(find.bySemanticsLabel('Sintel'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Sintel'));
    expect(node.value, 'Available, TMDB\u00A07.4');
    semantics.dispose();
  });

  testWidgets('a title Seerr holds no record of wears no badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const MediaPreview(id: 1, title: 'Caligari', mediaType: 'movie'),
    );

    expect(find.byType(StatusBadge), findsNothing);
  });

  testWidgets("TMDB's zero is nobody's rating, and no score is drawn", (
    tester,
  ) async {
    await _pump(
      tester,
      const MediaPreview(
        id: 2,
        title: 'Charge',
        mediaType: 'movie',
        voteAverage: 0,
      ),
    );

    expect(find.textContaining('TMDB'), findsNothing);
  });

  testWidgets('an average of a handful of votes is not drawn', (tester) async {
    await _pump(
      tester,
      const MediaPreview(
        id: 3,
        title: 'Die Brad Pitt Story',
        mediaType: 'movie',
        voteAverage: 10,
        voteCount: 1,
      ),
    );

    expect(find.textContaining('TMDB'), findsNothing);
  });

  testWidgets('the requester reads her own word', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _sintel, audience: Audience.requester);

    final node = tester.getSemantics(find.bySemanticsLabel('Sintel'));
    expect(node.value, 'On the server, TMDB\u00A07.4');
    semantics.dispose();
  });

  testWidgets('at twice the reading size the words fit the height it asks '
      'for', (tester) async {
    await _pump(
      tester,
      const MediaPreview(
        id: 3,
        title: 'The Cabinet of Dr. Caligari',
        mediaType: 'movie',
        voteAverage: 8,
      ),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });

  // The test font draws every letter a square em wide: a word of six letters
  // at the body's 15 is 90 wide, at 1.6 it is 144, wider than the 104 tile.
  RenderParagraph titleOf(WidgetTester tester, String title) =>
      tester.renderObject<RenderParagraph>(find.text(title));
  double sizeOf(RenderParagraph paragraph) => paragraph.text.style!.fontSize!;
  double titleScaleOf(WidgetTester tester, String title) {
    final paragraph = titleOf(tester, title);
    return paragraph.textScaler.scale(sizeOf(paragraph)) / sizeOf(paragraph);
  }

  testWidgets('at twice the reading size a word wider than the tile is never '
      'broken inside: the title steps down as far as its longest word needs', (
    tester,
  ) async {
    await _pump(
      tester,
      const MediaPreview(id: 4, title: 'Animal Farm', mediaType: 'movie'),
      textScale: 2,
    );

    final scale = titleScaleOf(tester, 'Animal Farm');
    expect(scale, greaterThan(1));
    expect(
      6 * sizeOf(titleOf(tester, 'Animal Farm')) * scale,
      lessThanOrEqualTo(104),
    );
  });

  testWidgets('short words keep the tile\'s ceiling', (tester) async {
    // The control: nothing to keep whole, nothing taken off.
    await _pump(
      tester,
      const MediaPreview(id: 5, title: 'Up', mediaType: 'movie'),
      textScale: 2,
    );

    expect(
      titleScaleOf(tester, 'Up'),
      closeTo(TextScaleMetrics.defaultMaxScaleFactor, 0.001),
    );
  });
}
