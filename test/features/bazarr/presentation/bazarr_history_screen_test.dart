import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets(
    'history stops before its providers when Bazarr is unconfigured',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
          child: const MaterialApp(home: BazarrHistoryScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    },
  );

  testWidgets('history names the all filter as subtitle history', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              bazarrUrl: 'http://bazarr.local',
              bazarrApiKey: 'key',
            ),
          ),
          bazarrServiceProvider.overrideWith((ref) => FakeBazarrService()),
        ],
        child: const MaterialApp(home: BazarrHistoryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Bazarr has no subtitle history to show.'),
      findsOneWidget,
    );
    expect(find.text('Bazarr has no all to show.'), findsNothing);
  });
}
