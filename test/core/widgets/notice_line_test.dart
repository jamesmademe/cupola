import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// The notice a flow ends a step with: its glyph and ink follow the tone, its
/// verbs are the one fill an amber fault gets and text in ink beside anything
/// else, and it is heard as one sentence.
Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(NoticeLine))).colorScheme;

void main() {
  group('the glyph and its ink', () {
    for (final (tone, glyph) in [
      (StatusTone.error, Icons.cloud_off_rounded),
      (StatusTone.info, Icons.info_outline_rounded),
      (StatusTone.warning, Icons.error_outline_rounded),
    ]) {
      for (final (room, theme) in [
        ('dark', AppTheme.darkTheme()),
        ('light', AppTheme.lightTheme()),
      ]) {
        testWidgets('${tone.name} draws $glyph in its tone, in the $room '
            'room', (tester) async {
          await tester.pumpWidget(
            _host(
              NoticeLine(tone: tone, title: 'Title', sentence: 'Sentence.'),
              theme: theme,
            ),
          );
          final scheme = _scheme(tester);
          final ink = statusToneColor(scheme, tone, surface: scheme.surface);

          expect(tester.widget<Icon>(find.byIcon(glyph)).color, ink);
          expect(tester.widget<Text>(find.text('Title')).style?.color, ink);
        });
      }
    }
  });

  testWidgets('says a sentence only when it has one, and is heard as one '
      'sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            NoticeLine(
              tone: StatusTone.info,
              title: 'Nothing yet',
              sentence: 'Come back later.',
            ),
            NoticeLine(tone: StatusTone.info, title: 'Only a title'),
          ],
        ),
      ),
    );

    expect(find.text('Come back later.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Nothing yet. Come back later.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Only a title.'), findsOneWidget);
    // Neither part is a node of its own.
    expect(find.bySemanticsLabel('Nothing yet'), findsNothing);
    handle.dispose();
  });

  group('the verbs', () {
    testWidgets('without a fill, text in ink', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => NoticeLine(
              tone: StatusTone.error,
              title: 'Title',
              actions: [noticeAction(context, 'Retry', () => pressed++)],
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      expect(pressed, 1);
    });

    testWidgets('a fault\'s fill is amber, and any other tone\'s is ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Column(
              children: [
                noticeAction(
                  context,
                  'Fix it',
                  () {},
                  fill: StatusTone.warning,
                ),
                noticeAction(context, 'Go on', () {}, fill: StatusTone.info),
              ],
            ),
          ),
        ),
      );

      final room = Theme.of(
        tester.element(find.text('Fix it')),
      ).extension<CupolaRoom>()!;
      Color? fillOf(String label) => tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, label))
          .style!
          .backgroundColor
          ?.resolve({});

      expect(fillOf('Fix it'), room.toneAmberFill);
      expect(fillOf('Go on'), isNull);
    });

    testWidgets('keep the touch floor beside body text', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => NoticeLine(
              tone: StatusTone.warning,
              title: 'Title',
              actions: [
                noticeAction(context, 'One', () {}, fill: StatusTone.warning),
                noticeAction(context, 'Two', () {}),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'One')).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Two')).height,
        greaterThanOrEqualTo(44),
      );
    });
  });
}
