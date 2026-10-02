import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';

/// A selected chip's label is drawn on the ink fill in the ink's own
/// contrast, never in the ink itself.
///
/// The theme gave every chip one plain label style in `onSurface`, which is
/// the ink: a selected FilterChip, filled with that ink, drew its label in the
/// same colour, so the season chips of the request sheet and every selected
/// filter read as blank pills. ChoiceChip was spared only because it reads
/// `secondaryLabelStyle`.
void main() {
  for (final (room, theme) in [
    ('dark', AppTheme.darkTheme()),
    ('light', AppTheme.lightTheme()),
  ]) {
    testWidgets('$room: each chip label reads on its own fill', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Wrap(
              children: [
                FilterChip(
                  label: const Text('Filter on'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('Filter off'),
                  selected: false,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('Choice on'),
                  selected: true,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      Color? ink(String label) => tester
          .renderObject<RenderParagraph>(find.text(label))
          .text
          .style
          ?.color;
      final scheme = theme.colorScheme;
      expect(ink('Filter on'), scheme.onPrimary);
      expect(ink('Choice on'), scheme.onPrimary);
      expect(ink('Filter off'), scheme.onSurface);
    });
  }
}
