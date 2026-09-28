import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/header_action_row.dart';

/// The floor for a control only a pointer reaches: the desktop's own chrome
/// may go to 38–40, never below.
const double _pointerFloor = 38;

/// Pumps [child] under the app theme built *for* [platform]: `ThemeData`
/// reads the platform for its density when it is constructed, which is where
/// the desktop's compact density comes from.
Future<void> _pump(
  WidgetTester tester,
  TargetPlatform platform,
  Widget child,
) async {
  debugDefaultTargetPlatformOverride = platform;
  final theme = AppTheme.darkTheme();
  debugDefaultTargetPlatformOverride = null;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(platform: platform),
      home: Material(child: Center(child: child)),
    ),
  );
}

void main() {
  group('on a desktop, theme buttons keep the pointer floor', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('${platform.name}: filled, outlined, text and icon buttons '
          'are at least $_pointerFloor tall', (tester) async {
        await _pump(
          tester,
          platform,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Grab')),
              OutlinedButton(onPressed: () {}, child: const Text('Update')),
              TextButton(onPressed: () {}, child: const Text('Retry')),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        );
        for (final type in [
          FilledButton,
          OutlinedButton,
          TextButton,
          IconButton,
        ]) {
          final size = tester.getSize(find.byType(type));
          expect(
            size.height,
            greaterThanOrEqualTo(_pointerFloor),
            reason: '$type is ${size.height} tall on ${platform.name}',
          );
        }
      });
    }
  });

  testWidgets('HeaderActionRow keeps one height on the desktop: the promoted '
      'and tonal buttons match the 48pt discs', (tester) async {
    await _pump(
      tester,
      TargetPlatform.macOS,
      SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              style: HeaderActionRow.expandedButtonStyle(),
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: const Text('Request'),
            ),
            OutlinedButton.icon(
              style: HeaderActionRow.tonalExpandedButtonStyle(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                borderColor: Colors.grey,
              ),
              onPressed: () {},
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search'),
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byWidgetPredicate((w) => w is FilledButton)).height,
      HeaderActionRow.buttonHeight,
    );
    expect(
      tester.getSize(find.byWidgetPredicate((w) => w is OutlinedButton)).height,
      HeaderActionRow.buttonHeight,
    );
  });
}
