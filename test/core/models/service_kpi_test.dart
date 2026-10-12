import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';

void main() {
  group('a figure whose source did not answer', () {
    test('reads "—", and never 0', () {
      // The rule, and the whole reason the constructor exists. The builders
      // used to write `?? 0`, so a download client that was down drew
      // `Queue 0`, indistinguishable from a queue that had just drained, and
      // the reading the user would act on is the opposite one.
      const kpi = ServiceKpi.unavailable(
        label: 'Queue',
        icon: Icons.download_rounded,
        note: 'client not answering',
      );

      expect(kpi.value, isNot('0'));
      expect(kpi.value, isNotEmpty);
      expect(kpi.isUnavailable, isTrue);
    });

    test(
      'carries no tone: a neighbour\'s outage is not this service\'s fault',
      () {
        const kpi = ServiceKpi.unavailable(
          label: 'Queue',
          icon: Icons.download_rounded,
        );
        expect(kpi.tone, isNull);
        expect(kpi.isNoteworthy, isFalse);
      },
    );

    test('says "unavailable" out loud, with the reason', () {
      // An em dash is the one character on the rail assistive technology cannot
      // render usefully: most screen readers say "dash" or skip it, so the
      // figure that matters most announced worst.
      const kpi = ServiceKpi.unavailable(
        label: 'Queue',
        icon: Icons.download_rounded,
        note: 'client not answering',
      );
      expect(kpi.semanticLabel, 'Queue: unavailable, client not answering');
    });

    test('an ordinary figure announces its value', () {
      const kpi = ServiceKpi(
        label: 'Missing',
        value: '34',
        icon: Icons.warning_rounded,
        tone: StatusTone.neutral,
      );
      expect(kpi.semanticLabel, 'Missing: 34');
      expect(kpi.isUnavailable, isFalse);
    });
  });

  group('the peek renders the absence as an absence', () {
    Future<void> pump(WidgetTester tester, ServiceKpi kpi) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceKpiPeek(
              kpis: AsyncValue.data([kpi]),
              accent: Colors.amber,
            ),
          ),
        ),
      );
    }

    testWidgets('the em dash does not wear the service accent', (tester) async {
      // Painting it in the accent would make an absence look like a reading.
      const accent = Colors.amber;
      await pump(
        tester,
        const ServiceKpi.unavailable(
          label: 'Queue',
          icon: Icons.download_rounded,
          note: 'client not answering',
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.download_rounded));
      expect(icon.color, isNot(accent));
      final scheme = Theme.of(
        tester.element(find.byType(ServiceKpiPeek)),
      ).colorScheme;
      expect(icon.color, scheme.onSurfaceVariant);
    });

    testWidgets('the card is one node, and it says why', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const ServiceKpi.unavailable(
          label: 'Queue',
          icon: Icons.download_rounded,
          note: 'client not answering',
        ),
      );

      // Not four fragments ("3", "QUEUE", "—", "CLIENT NOT ANSWERING") that a
      // listener has to reassemble in reading order.
      expect(
        find.bySemanticsLabel('Queue: unavailable, client not answering'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
