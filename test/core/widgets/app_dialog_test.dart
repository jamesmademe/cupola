import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/status_badge.dart';

void main() {
  group('showAppConfirmDialog destructive', () {
    for (final brightness in Brightness.values) {
      testWidgets('keeps its red legible on the ${brightness.name} dialog', (
        tester,
      ) async {
        final theme = brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppConfirmDialog(
                  context: context,
                  title: 'Delete movie',
                  message: 'Remove it from the library?',
                  confirmLabel: 'Delete',
                  destructive: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final scheme = theme.colorScheme;
        final dialogSurface =
            theme.dialogTheme.backgroundColor ?? scheme.surfaceContainerHigh;
        final noteGround = Color.alphaBlend(
          scheme.error.withValues(alpha: 0.10),
          dialogSurface,
        );

        // Red in an action means irreversible, so the destructive variant
        // keeps it — but as a walked ink, never the raw byte, which measured
        // 3.4:1 as text on the light dialog.
        final header = tester
            .widget<Icon>(find.byIcon(Icons.warning_amber_rounded))
            .color!;
        expect(
          header,
          statusToneColor(scheme, StatusTone.error, surface: dialogSurface),
        );
        expect(_contrast(header, dialogSurface), greaterThanOrEqualTo(4.5));

        final note = tester
            .widget<Text>(find.text('This cannot be undone.'))
            .style!
            .color!;
        expect(_contrast(note, noteGround), greaterThanOrEqualTo(4.5));
        final noteGlyph = tester
            .widget<Icon>(find.byIcon(Icons.warning_rounded))
            .color!;
        expect(_contrast(noteGlyph, noteGround), greaterThanOrEqualTo(4.5));

        // The fill keeps the tone's own byte; the label is chosen against it.
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final fill = button.style!.backgroundColor!.resolve({})!;
        final label = button.style!.foregroundColor!.resolve({})!;
        expect(fill, scheme.error);
        expect(label, ServiceTheme.foregroundOn(fill));
        expect(_contrast(label, fill), greaterThanOrEqualTo(4.5));
      });
    }
  });
}

/// WCAG 2.1 relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
