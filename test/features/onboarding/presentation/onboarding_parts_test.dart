import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_glyph_row.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The beats' own rules, tested on the widgets rather than through the whole
/// flow: what the close is allowed to promise, how far the result row is allowed
/// to wrap, and which of a field's two lines a validation message may replace.
Widget _host(Widget child, {double width = 560}) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('OnboardingGlyphRow', () {
    testWidgets('draws one tile per service while they fit two rows', (
      tester,
    ) async {
      final services = ServiceKey.values.take(8).toList();
      await tester.pumpWidget(_host(OnboardingGlyphRow(services: services)));

      expect(find.byType(Icon), findsNWidgets(8));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('stops at twelve and counts the rest', (tester) async {
      // The maximum case, which is what the narrowest frame is drawn at: every
      // registry service picked and answering. A third row of glyphs stops
      // being a result and becomes an inventory.
      await tester.pumpWidget(
        _host(
          const OnboardingGlyphRow(services: ServiceKey.values),
          width: 344,
        ),
      );

      expect(find.byType(Icon), findsNWidgets(OnboardingGlyphRow.maxTiles));
      expect(
        find.text('+${ServiceKey.values.length - OnboardingGlyphRow.maxTiles}'),
        findsOneWidget,
      );
    });

    testWidgets('says what it drew and how much it did not', (tester) async {
      // The row is one stop for a screen reader rather than seventeen, and the
      // count is the part the drawing cannot say at all.
      await tester.pumpWidget(
        _host(
          const OnboardingGlyphRow(services: ServiceKey.values),
          width: 344,
        ),
      );

      final spoken = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>()
          .firstWhere((label) => label.contains(ServiceKey.values.first.title));
      expect(spoken, contains(ServiceKey.values.first.title));
      expect(
        spoken,
        contains(
          'and ${ServiceKey.values.length - OnboardingGlyphRow.maxTiles} more',
        ),
      );
    });
  });

  group('OnboardingClose', () {
    Widget close({
      required List<ServiceKey> connected,
      List<ServiceKey> silent = const [],
    }) => _host(
      OnboardingClose(
        connected: connected,
        silent: silent,
        onFix: (_) {},
        onFinish: () async {},
        onReview: () {},
      ),
    );

    testWidgets('counts what answered instead of claiming the whole stack', (
      tester,
    ) async {
      // The body used to open with "Your whole stack is in one place" whatever
      // fraction of it had actually been set up — a claim that teaches someone
      // not to read the next one.
      await tester.pumpWidget(
        close(connected: [ServiceKey.radarr, ServiceKey.sonarr]),
      );

      expect(
        find.textContaining('2/${ServiceKey.values.length} services answered'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Everything you set up is ready to use'),
        findsOneWidget,
      );
    });

    testWidgets('offers a service that still exists, never Readarr', (
      tester,
    ) async {
      // Readarr is retired upstream, so naming it as the thing to add later is
      // advice with a dead end — the whole reason the example is pinned.
      await tester.pumpWidget(close(connected: [ServiceKey.radarr]));

      expect(find.textContaining('Lidarr and the rest'), findsOneWidget);
      expect(find.textContaining('Readarr'), findsNothing);
      // And the home the sentence points at is the Dashboard, which is what
      // that screen is called now.
      expect(find.textContaining('on the Dashboard'), findsOneWidget);
    });

    testWidgets('does not offer a service the user just connected', (
      tester,
    ) async {
      // Same defect in different clothes: the example has to be something that
      // is actually still missing.
      await tester.pumpWidget(
        close(connected: [ServiceKey.lidarr, ServiceKey.radarr]),
      );

      expect(find.textContaining('Lidarr and the rest'), findsNothing);
      expect(find.textContaining('and the rest can be added'), findsOneWidget);
    });

    testWidgets('the empty outcome points at the Dashboard, not Services', (
      tester,
    ) async {
      await tester.pumpWidget(close(connected: const []));

      expect(find.textContaining('Cupola will stay empty'), findsOneWidget);
      expect(find.textContaining('on the Dashboard'), findsOneWidget);
      expect(find.textContaining('on Services'), findsNothing);
    });
  });

  group('OnboardingField', () {
    testWidgets('a validation message joins the guidance rather than '
        'replacing it', (tester) async {
      // One slot held the breadcrumb, the steady note *and* the validation
      // result, so typing a bad address deleted the two lines that say how to
      // fix it. The breadcrumb moved up to the label row and the note stayed
      // put; only the validation line is new.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          OnboardingField(
            label: 'Address',
            controller: controller,
            isUrl: true,
            breadcrumb: 'Radarr → Settings → General',
            help: "Radarr's default port is 7878.",
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'http://not a host');
      await tester.pump();

      expect(find.text('Radarr → Settings → General'), findsOneWidget);
      expect(find.text("Radarr's default port is 7878."), findsOneWidget);
      // Whatever the validator's wording, there is a third line now — and it is
      // the one painted in the error tone.
      final notes = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) => t.style?.color == AppTheme.darkTheme().colorScheme.error,
          )
          .toList();
      expect(notes, isNotEmpty);
    });
  });
}
