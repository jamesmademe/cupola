import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_history_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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
}
