/// A list scrolled up under a bar fades into the room at the bar's edge
/// instead of being sliced there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';

void main() {
  final fade = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_FadePaint',
  );

  Widget rows() => ListView(
    children: [
      for (var i = 0; i < 40; i++) SizedBox(height: 56, child: Text('Row $i')),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    PreferredSizeWidget? appBar,
    required Widget body,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: AmbientScaffold(appBar: appBar, body: body),
      ),
    );
  }

  testWidgets('a list at rest under a bar is drawn whole', (tester) async {
    await pump(
      tester,
      appBar: const GlassAppBar(title: Text('Settings')),
      body: rows(),
    );

    expect(tester.renderObject(fade), paintsNothing);
  });

  testWidgets('scrolled up, it fades into the room across its width', (
    tester,
  ) async {
    await pump(
      tester,
      appBar: const GlassAppBar(title: Text('Settings')),
      body: rows(),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();

    expect(
      tester.renderObject(fade),
      paints..rect(rect: const Rect.fromLTWH(0, 0, 800, 24)),
    );
  });

  testWidgets('a list under something fixed is not faded', (tester) async {
    await pump(
      tester,
      appBar: const GlassAppBar(title: Text('Library')),
      body: Column(
        children: [
          const SizedBox(height: 64, child: Text('A field')),
          Expanded(child: rows()),
        ],
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();

    expect(tester.renderObject(fade), paintsNothing);
  });

  testWidgets('without a bar there is nothing to fade under', (tester) async {
    await pump(tester, body: rows());

    expect(fade, findsNothing);
  });
}
