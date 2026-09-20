import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_stats_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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
}
