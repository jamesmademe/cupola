import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/truenas/domain/models/dashboard.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';
import 'package:cupola/features/truenas/presentation/truenas_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('a pull re-asks TrueNAS for its dashboard', (tester) async {
    // The hub was the one service page without a pull: a rail that read "not
    // answering" stayed that way until the user left the page.
    var fetches = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              truenasUrl: 'https://nas.local',
              truenasApiKey: 'key',
            ),
          ),
          truenasDashboardProvider.overrideWith((ref) async {
            fetches++;
            return const TrueNasDashboard(
              system: TrueNasSystemInfo(),
              pools: [],
              alerts: [],
              services: [],
            );
          }),
          truenasVersionProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: TrueNasHubScreen()),
      ),
    );
    await tester.pump();
    expect(fetches, 1);

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(fetches, 2);
  });
}
