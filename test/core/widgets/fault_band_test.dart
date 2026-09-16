import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/fault_band.dart';

/// Every assertion here guards a **rule**, not a rendering.
///
/// The three rules the design settles on are the whole of this widget, and they
/// are all invisible to a screenshot: a fill that should not be there, a tone
/// on the wrong element, a control that reads as disabled. So they are checked
/// as resolved semantics and resolved colours — never a hex, never a pixel.
Future<void> _pump(WidgetTester tester, Widget band) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: [band])),
    ),
  );
}

/// The colour a band actually paints its one glyph in.
Color _glyphColour(WidgetTester tester) {
  return tester.widget<Icon>(find.byType(Icon).first).color!;
}

/// The colour a band actually paints a named verb in.
Color _verbColour(WidgetTester tester, String label) {
  final button = tester.widget<TextButton>(
    find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
  );
  return button.style!.foregroundColor!.resolve({})!;
}

void main() {
  group('rule 1 — presence is the signal', () {
    testWidgets('no band paints a fill or a border', (tester) async {
      // The band used to be a card: a tinted fill behind an error-tone stroke.
      // In a stack where something is down most Tuesdays, that is alarm chrome
      // on most Tuesdays, and alarm chrome that appears constantly is chrome
      // nobody reads on the day it matters.
      final bands = <Widget>[
        FaultBand.unreachable(serviceName: 'TrueNAS', onRetry: () {}),
        FaultBand.section(
          message: 'qBittorrent is not answering.',
          onRetry: () {},
        ),
        FaultBand.stale(
          age: const Duration(minutes: 4),
          detail: 'Radarr is answering; its queue has not returned a sample.',
          onRefresh: () {},
        ),
        FaultBand.offlinePush(serviceName: 'Radarr', onRetry: () {}),
      ];

      for (final band in bands) {
        await _pump(tester, band);
        for (final decorated in tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(FaultBand),
            matching: find.byType(DecoratedBox),
          ),
        )) {
          final decoration = decorated.decoration;
          if (decoration is BoxDecoration) {
            expect(decoration.color, isNull, reason: 'no fill');
            expect(decoration.border, isNull, reason: 'no border');
          }
        }
      }
    });

    testWidgets('the tone lands on exactly one glyph', (tester) async {
      await _pump(
        tester,
        FaultBand.unreachable(serviceName: 'TrueNAS', onRetry: () {}),
      );
      // One glyph carrying the alarm, and no second one competing with it.
      expect(
        find.descendant(
          of: find.byType(FaultBand),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
    });
  });

  group('rule 2 — the recovery verb is never the fault tone', () {
    testWidgets('Retry and Settings are the brand, not the alarm', (
      tester,
    ) async {
      await _pump(
        tester,
        FaultBand.unreachable(
          serviceName: 'TrueNAS',
          onRetry: () {},
          onOpenSettings: () {},
        ),
      );

      final alarm = _glyphColour(tester);
      final scheme = Theme.of(
        tester.element(find.byType(FaultBand)),
      ).colorScheme;

      for (final verb in ['Retry', 'Settings']) {
        final colour = _verbColour(tester, verb);
        expect(colour, scheme.primary);
        // A red Retry makes the cure look like the disease.
        expect(colour, isNot(alarm));
      }
    });

    testWidgets('the stale band paints Refresh in the brand too', (
      tester,
    ) async {
      await _pump(
        tester,
        FaultBand.stale(
          age: const Duration(minutes: 4),
          detail: 'Nothing below is moving.',
          onRefresh: () {},
        ),
      );
      expect(_verbColour(tester, 'Refresh'), isNot(_glyphColour(tester)));
    });
  });

  group('the four levels say four different things', () {
    testWidgets('unreachable names the age, and keeps the readout', (
      tester,
    ) async {
      await _pump(
        tester,
        FaultBand.unreachable(
          serviceName: 'TrueNAS',
          since: const Duration(minutes: 6),
          onRetry: () {},
        ),
      );
      // The age is the only thing on this band the user does not already know:
      // thirty seconds is a restart, six minutes is an outage, and those are
      // different decisions.
      expect(find.textContaining('6 minutes'), findsOneWidget);
      expect(find.textContaining('what it said last'), findsOneWidget);
    });

    testWidgets('unreachable drops the span rather than inventing one', (
      tester,
    ) async {
      await _pump(
        tester,
        FaultBand.unreachable(serviceName: 'TrueNAS', onRetry: () {}),
      );
      expect(find.textContaining('TrueNAS did not answer'), findsOneWidget);
      expect(find.textContaining('for 0'), findsNothing);
    });

    testWidgets('stale is a warning, not an error', (tester) async {
      // The distinction the whole level exists for: nothing is unreachable and
      // nothing failed. The figures are simply older than they should be, and
      // painting that red would spend the alarm colour on a working service.
      await _pump(
        tester,
        FaultBand.stale(
          age: const Duration(minutes: 4),
          detail: 'Nothing below is moving.',
          onRefresh: () {},
        ),
      );
      final band = tester.widget<FaultBand>(find.byType(FaultBand));
      expect(band.tone, StatusTone.warning);
      expect(find.textContaining('4 min ago'), findsOneWidget);
    });

    testWidgets('stale offers no dismiss and no second action', (tester) async {
      // A stale reading is a property of the data, still true the instant after
      // it is acknowledged — a dismiss would only teach the user to hide it.
      await _pump(
        tester,
        FaultBand.stale(
          age: const Duration(minutes: 4),
          detail: 'Nothing below is moving.',
          onRefresh: () {},
        ),
      );
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('offlinePush warns that a write will fail', (tester) async {
      await _pump(
        tester,
        FaultBand.offlinePush(
          serviceName: 'Radarr',
          onRetry: () {},
          onOpen: () {},
        ),
      );
      expect(find.textContaining('last render'), findsOneWidget);
      expect(find.textContaining('a write will fail'), findsOneWidget);
      expect(find.text('Open Radarr'), findsOneWidget);
    });
  });

  group('screen reader', () {
    testWidgets('the band is one statement, and its verbs stay reachable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FaultBand.unreachable(
          serviceName: 'TrueNAS',
          since: const Duration(minutes: 6),
          onRetry: () {},
          onOpenSettings: () {},
        ),
      );

      // One node for the sentence — not a glyph, three text fragments and two
      // buttons that a listener has to reassemble.
      expect(
        find.bySemanticsLabel(RegExp('TrueNAS has not answered for 6 minutes')),
        findsOneWidget,
      );
      // And the verbs are still their own controls.
      expect(find.bySemanticsLabel('Retry'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('the verbs actually fire', (tester) async {
    var retried = 0;
    var settings = 0;
    await _pump(
      tester,
      FaultBand.unreachable(
        serviceName: 'TrueNAS',
        onRetry: () => retried++,
        onOpenSettings: () => settings++,
      ),
    );
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(retried, 1);
    expect(settings, 1);
  });
}
