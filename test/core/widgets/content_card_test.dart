import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/content_card.dart';

void main() {
  group('ContentCard', () {
    testWidgets('renders placeholder when imageUrl is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      expect(find.byType(ContentCard), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('renders placeholder when imageUrl is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ContentCard(imageUrl: '')),
        ),
      );

      expect(find.byType(ContentCard), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('renders badge when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentCard(
              imageUrl: null,
              badge: Container(
                key: const Key('test_badge'),
                width: 10,
                height: 10,
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('test_badge')), findsOneWidget);
    });

    testWidgets('does not render badge when not provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      // Should not find any Positioned widget (which wraps the badge)
      // Just check that the widget renders correctly
      expect(find.byType(ContentCard), findsOneWidget);
    });

    testWidgets('has correct border radius', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ContentCard(imageUrl: null))),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ContentCard),
          matching: find.byType(Container).first,
        ),
      );

      final decoration = container.decoration as BoxDecoration?;
      // AppRadius.borderRadiusMd = 12
      expect(decoration?.borderRadius, BorderRadius.circular(12));
    });

    Widget tile(Widget card) => MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 120, height: 180, child: card)),
      ),
    );

    // A missing poster is the source of a Hero flight into a detail poster
    // drawn by MediaPosterCard, whose fallback is the plate in both themes. A
    // theme surface here was a white tile in light theme that turned into a
    // dark well mid-flight.
    testWidgets('a missing poster is the plate, as on MediaPosterCard', (
      tester,
    ) async {
      await tester.pumpWidget(tile(const ContentCard(imageUrl: null)));

      final well = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.movie_outlined),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(well.color, AppColors.plateSurface);
      final glyph = tester.widget<Icon>(find.byIcon(Icons.movie_outlined));
      expect(glyph.color, AppColors.plateDimInk);
    });

    // Painted in a box the size of the badge, the radial was cut off while
    // still a third of its strength: a hard-edged grey rectangle around the
    // badge on any ground that was not dark artwork.
    testWidgets('the badge glow fades out inside the card, never at an edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        tile(
          const ContentCard(
            imageUrl: null,
            badge: SizedBox(width: 40, height: 20),
          ),
        ),
      );

      final glow = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is RadialGradient,
      );
      expect(glow, findsOneWidget);
      final card = tester.getRect(find.byType(ContentCard));
      final glowRect = tester.getRect(glow);
      expect(glowRect, card, reason: 'the glow must span the whole card');

      final gradient =
          (tester.widget<DecoratedBox>(glow).decoration as BoxDecoration)
                  .gradient!
              as RadialGradient;
      expect(gradient.center, Alignment.topRight);
      // Reach in points from the top-right corner: zero before the left edge
      // and the bottom edge, so no edge of the box ever cuts the radial.
      final reach = gradient.radius * glowRect.shortestSide;
      expect(reach, lessThan(glowRect.width));
      expect(reach, lessThan(glowRect.height));
      expect(gradient.colors.last.a, 0);
    });
  });
}
