import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_title.dart';

Future<void> _pump(WidgetTester tester, Widget body) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.darkTheme(),
    home: AmbientScaffold(
      appBar: const GlassAppBar.inPage(pageTitle: 'Connections'),
      body: body,
    ),
  ),
);

Finder get _inBar => find.byKey(const ValueKey('page-title-in-bar'));

void main() {
  testWidgets('a page says its name once, in the page, in the room role', (
    tester,
  ) async {
    await _pump(
      tester,
      ListView(
        children: [
          const PageTitle(
            'Connections',
            summary: Text('15 set up\u00A0· 2 not set up'),
          ),
          for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i')),
        ],
      ),
    );

    expect(find.text('Connections'), findsOneWidget);
    expect(_inBar, findsNothing);
    final title = tester.widget<Text>(find.text('Connections'));
    expect(title.style!.fontSize, AppType.room.fontSize);
    expect(find.text('15 set up\u00A0· 2 not set up'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Connections')),
      containsSemantics(isHeader: true),
    );
  });

  testWidgets('the bar takes the name once the page has scrolled it under, '
      'and gives it back', (tester) async {
    await _pump(
      tester,
      ListView(
        children: [
          const PageTitle('Connections'),
          for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i')),
        ],
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_inBar, findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(_inBar, findsNothing);
  });

  testWidgets('a body that is not a list sits under the name', (tester) async {
    await _pump(
      tester,
      const TitledBody(
        title: 'Connections',
        child: Center(child: Text('Nothing here')),
      ),
    );

    final name = tester.getRect(find.text('Connections'));
    final body = tester.getRect(find.text('Nothing here'));
    expect(name.bottom, lessThan(body.top));
    expect(find.byType(ScrollEdgeFade), findsWidgets);
  });
}
