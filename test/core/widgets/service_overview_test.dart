import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The rules the four Overviews used to guard four times over, now once.
///
/// These are not renderings. Each case is a property that the extraction had to
/// carry across intact, and that the next nine Overviews inherit for free:
/// Prowlarr's capped trailing figure, the section link's spoken destination,
/// and the row's one-sentence label.
Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  group('ServiceOverviewRow', () {
    testWidgets(
      'the trailing figure ellipsises rather than overflowing at 3x',
      (tester) async {
        // The one feature Prowlarr's private copy had that the other three
        // lacked, and the reason it exists: an unconstrained figure beside an
        // `Expanded` title is a right-edge overflow at an accessibility reading
        // size, and a row that throws is worse than a figure that ellipsises:
        // the whole value is still in the sentence a screen reader hears.
        await tester.pumpWidget(
          _host(
            textScale: 3,
            const SizedBox(
              width: 360,
              child: ServiceOverviewRow(
                spoken: 'Nyaa, 298 queries, 4 grabs',
                leading: Icon(Icons.circle, size: 8),
                title: 'Nyaa',
                detail: 'torrent\u00A0· public',
                trailing: '298 queries',
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        final figure = tester.widget<Text>(find.text('298 queries'));
        expect(figure.maxLines, 1);
        expect(figure.overflow, TextOverflow.ellipsis);

        // The cap itself, not merely "it fits": a row that happened to fit at
        // this width would pass without it and overflow on a narrower one.
        final box = tester.renderObject<RenderBox>(find.text('298 queries'));
        expect(box.size.width, lessThanOrEqualTo(132));
      },
    );

    testWidgets('speaks one sentence and silences its parts', (tester) async {
      // Nothing in the row is interactive, so read separately the mark, the
      // title and the figure are three fragments of one fact.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewRow(
            spoken: 'Nyaa, 298 queries',
            leading: Icon(Icons.circle, size: 8),
            title: 'Nyaa',
            detail: 'torrent\u00A0· public',
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Nyaa, 298 queries'),
        findsOneWidget,
        reason: 'the row must be one container node, not three fragments',
      );
      expect(find.bySemanticsLabel('torrent\u00A0· public'), findsNothing);
      handle.dispose();
    });
  });

  group('ServiceOverviewSection', () {
    testWidgets('the link names the service and the tab it opens', (
      tester,
    ) async {
      // The link's glyph is "→", which a screen reader says as "rightwards
      // arrow". The destination has to arrive as a hint or it does not arrive.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewSection(
            service: ServiceKey.prowlarr,
            title: 'Indexers',
            destination: ServiceTab.indexers,
            child: Text('body'),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      final hints = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.hint)
          .whereType<String>();
      expect(hints, contains('opens the Prowlarr Indexers tab'));
      handle.dispose();
    });

    testWidgets('a section with no destination offers no link', (tester) async {
      // A region whose rows belong to several tabs at once has nowhere single
      // to send anyone, so it draws no affordance rather than a dead one.
      await tester.pumpWidget(
        _host(
          const ServiceOverviewSection(
            service: ServiceKey.bazarr,
            title: 'Needs attention',
            child: Text('body'),
          ),
        ),
      );

      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('bleed leaves the body on the window edge', (tester) async {
      // The poster-rail shape: the row runs off the column while its first tile
      // still aligns to it, so the section must NOT inset the body.
      for (final bleeding in [false, true]) {
        await tester.pumpWidget(
          _host(
            bleeding
                ? const ServiceOverviewSection.bleed(
                    service: ServiceKey.radarr,
                    title: 'Recently added',
                    child: SizedBox(key: ValueKey('body'), height: 20),
                  )
                : const ServiceOverviewSection(
                    service: ServiceKey.radarr,
                    title: 'Recently added',
                    child: SizedBox(key: ValueKey('body'), height: 20),
                  ),
          ),
        );

        final left = tester.getTopLeft(find.byKey(const ValueKey('body'))).dx;
        expect(
          left,
          bleeding ? 0 : greaterThan(0),
          reason: 'bleeding=$bleeding',
        );
      }
    });
  });
}
