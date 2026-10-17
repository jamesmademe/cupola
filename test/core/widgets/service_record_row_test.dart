import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_record_row.dart';
import 'package:cupola/core/widgets/status_badge.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 390, child: child),
      ),
    ),
  );

  ServiceRecordRow row({required String title, required String trailing}) =>
      ServiceRecordRow(
        icon: Icons.sync_rounded,
        tone: StatusTone.info,
        title: title,
        detail: 'Started 2 min ago',
        trailing: trailing,
        semanticLabel: '$title, $trailing',
      );

  group('ServiceRecordRow', () {
    testWidgets('a short figure sits on the trailing edge', (tester) async {
      // A Flexible beside the Expanded body was handed half the free width,
      // so "Failed" floated mid-row with the card's right half empty.
      await tester.pumpWidget(
        host(row(title: 'Extract chapter images', trailing: 'Failed')),
      );

      final card = tester.getRect(find.byType(ServiceRecordRow));
      final figure = tester.getRect(find.text('Failed'));
      // The card's own padding (12) and 1px outline are all that separate
      // the figure from the edge.
      expect(card.right - figure.right, lessThan(16));
    });

    testWidgets('the title keeps the width a short figure leaves', (
      tester,
    ) async {
      // With the width split in half the title was offered ~160pt while the
      // figure used a fraction of its share.
      await tester.pumpWidget(
        host(row(title: 'Clean transcode directory', trailing: 'Idle')),
      );

      final title = tester.renderObject<RenderParagraph>(
        find.text('Clean transcode directory'),
      );
      // 390 − 26 (padding, outline) − 36 (icon, gap) − 8 − the figure: the
      // body is offered ~280pt, where the half split offered ~160.
      expect(title.constraints.maxWidth, greaterThan(250));
    });

    testWidgets('a long figure is capped and cannot crush the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          row(
            title: 'Living room projector',
            trailing:
                'client\u00A0· player\u00A0· pubsub-player\u00A0· controller\u00A0· cast',
          ),
        ),
      );

      final card = tester.getRect(find.byType(ServiceRecordRow));
      final figure = tester.getRect(
        find.text(
          'client\u00A0· player\u00A0· pubsub-player\u00A0· controller\u00A0· cast',
        ),
      );
      final content = card.width - 2 * 12 - 2;
      expect(
        figure.width,
        lessThanOrEqualTo(content * ServiceRecordRow.trailingMaxFraction + 1),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
