import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_profile_selector.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _profiles = <Map<String, dynamic>>[
  {'id': 1, 'name': 'HD-1080p'},
  {'id': 2, 'name': 'Ultra-HD'},
];

void main() {
  group('showMediaProfileSelector', () {
    testWidgets('every row is a PressableScale target of at least 44pt', (
      tester,
    ) async {
      await _pumpPicker(tester);

      expect(find.byType(PressableScale), findsNWidgets(_profiles.length));
      expect(find.byType(ListTile), findsNothing);
      for (final name in const ['HD-1080p', 'Ultra-HD']) {
        final row = find
            .ancestor(
              of: find.text(name),
              matching: find.byType(PressableScale),
            )
            .first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the selected row is announced, not only coloured', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPicker(tester);

      expect(
        find.semantics.byLabel('HD-1080p').first,
        containsSemantics(value: 'Selected'),
      );
      handle.dispose();
    });

    testWidgets('the selected row takes the page accent, not primary', (
      tester,
    ) async {
      await _pumpPicker(tester, accent: ServiceKey.sonarr.accent);

      final check = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_rounded),
      );
      final context = tester.element(find.text('HD-1080p'));
      expect(check.color, isNot(Theme.of(context).colorScheme.primary));
    });

    testWidgets('re-picking the current profile writes nothing', (
      tester,
    ) async {
      var writes = 0;
      await _pumpPicker(tester, onProfileSelected: (_) async => writes++);

      await tester.tap(find.text('HD-1080p'));
      await tester.pumpAndSettle();
      // A no-op write to a quality profile can still queue an upgrade sweep.
      expect(writes, 0);
    });

    testWidgets('picking a different profile writes once', (tester) async {
      var written = <int>[];
      await _pumpPicker(
        tester,
        onProfileSelected: (id) async => written.add(id),
      );

      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();
      expect(written, [2]);
    });
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  Color? accent,
  Future<void> Function(int profileId)? onProfileSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMediaProfileSelector(
              context,
              currentProfileName: 'HD-1080p',
              currentProfileId: 1,
              qualityProfiles: _profiles,
              onProfileSelected: onProfileSelected ?? (_) async {},
              accent: accent,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
