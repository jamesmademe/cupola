import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_stats_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets(
    'history and stats stop before their providers when Prowlarr is unconfigured',
    (tester) async {
      for (final screen in const <Widget>[
        ProwlarrHistoryScreen(),
        ProwlarrStatsScreen(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentSettingsProvider.overrideWith(
                (ref) => const SettingsModel(),
              ),
            ],
            child: MaterialApp(home: screen),
          ),
        );
        await tester.pump();

        expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      }
    },
  );

  testWidgets('history names the all filter as history entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              prowlarrUrl: 'http://prowlarr.local:9696',
              prowlarrApiKey: 'key',
            ),
          ),
          prowlarrHistoryPageProvider((
            page: 1,
            pageSize: 50,
            eventType: null,
          )).overrideWith((ref) async => const ProwlarrHistoryPage()),
        ],
        child: const MaterialApp(home: ProwlarrHistoryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Prowlarr has no history entries to show.'),
      findsOneWidget,
    );
    expect(find.text('Prowlarr has no all to show.'), findsNothing);
  });
}
