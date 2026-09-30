import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_detail_section_label.dart';

void main() {
  testWidgets('past 1.4x the action drops under the label, leading-aligned', (
    tester,
  ) async {
    // It was wrapped in a tight full-width box, which centred the IconButton's
    // glyph in the middle of the line under nothing.
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: ListView(
              children: [
                SizedBox(
                  width: 358,
                  child: MediaDetailSectionLabel(
                    label: 'Missing subtitles',
                    accent: const Color(0xFF8B5CF6),
                    action: IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh from Bazarr',
                      onPressed: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final label = tester.getRect(find.text('Missing subtitles'));
    final button = tester.getRect(find.byType(IconButton));
    expect(button.top, greaterThanOrEqualTo(label.bottom));
    expect(button.left, closeTo(label.left, 0.5));
    // Its own 48pt target, not a line-wide one.
    expect(button.width, lessThan(64));
  });
}
