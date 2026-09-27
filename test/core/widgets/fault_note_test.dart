import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/status_badge.dart';

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget note) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: note)),
    ),
  );
}

void main() {
  for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
    final scheme = theme.colorScheme;
    final name = theme.brightness.name;

    group('FaultNote ($name)', () {
      testWidgets('unreachable spends red on the glyph and nowhere else', (
        tester,
      ) async {
        await _pump(
          tester,
          theme,
          FaultNote.unreachable(
            message: 'Failed to load servers',
            surface: scheme.surfaceContainer,
          ),
        );

        expect(
          tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).color,
          statusToneColor(
            scheme,
            StatusTone.error,
            surface: scheme.surfaceContainer,
          ),
        );
        expect(
          tester.widget<Text>(find.text('Failed to load servers')).style!.color,
          scheme.onSurfaceVariant,
        );
      });

      testWidgets('a fault is amber, never red', (tester) async {
        await _pump(
          tester,
          theme,
          const FaultNote.fault(message: 'Purchase failed.'),
        );

        expect(
          tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded)).color,
          statusToneColor(scheme, StatusTone.warning),
        );
        expect(
          tester.widget<Text>(find.text('Purchase failed.')).style!.color,
          scheme.onSurfaceVariant,
        );
      });

      testWidgets('speaks the sentence once, not the glyph', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          theme,
          const FaultNote.unreachable(message: 'Failed to load requests'),
        );

        expect(
          find.bySemanticsLabel('Failed to load requests'),
          findsOneWidget,
        );
        handle.dispose();
      });
    });
  }
}
