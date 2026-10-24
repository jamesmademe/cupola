import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';

/// The sheet paints its own fill. Ink (a ListTile's tap, its selected tint)
/// is drawn on the nearest Material, which used to be the route's, under that
/// fill: every tap in every sheet was invisible, and Flutter 3.47 says so with
/// an assertion. The manual import's language picker is where it showed.
void main() {
  testWidgets('a ListTile in a sheet draws its ink above the sheet\'s fill', (
    tester,
  ) async {
    // A phone: on a wide window the same call opens a dialog, which has a
    // Material of its own.
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppBottomSheet.show<void>(
                context: context,
                title: 'Select languages',
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      value: true,
                      title: const Text('Italian'),
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Between the row and the sheet's fill there is now a Material of the
    // sheet's own, which is where the row's ink lands.
    final materials = tester.widgetList<Material>(
      find.ancestor(of: find.text('Italian'), matching: find.byType(Material)),
    );
    expect(
      materials.any((material) => material.type == MaterialType.transparency),
      isTrue,
    );
  });
}
