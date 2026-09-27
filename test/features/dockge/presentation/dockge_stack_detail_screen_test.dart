import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_detail_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// A [DockgeClient] whose terminal join goes nowhere, so the log pane can
/// mount without a socket.
class _QuietClient extends DockgeClient {
  _QuietClient() : super(baseUrl: 'https://dockge.local');

  @override
  Future<void> joinCombinedTerminal(String stackName) async {}
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(const [ServiceKey.dockge]),
        ),
        dockgeClientProvider.overrideWith((ref) => _QuietClient()),
        dockgeStackDetailProvider.overrideWith(
          (ref, name) async => DockgeStackDetail(
            stack: DockgeStack(name: name, status: DockgeStackStatus.running),
          ),
        ),
        dockgeServiceStatusProvider.overrideWith(
          (ref, name) async => const <DockgeServiceStatus>[],
        ),
      ],
      child: const MaterialApp(home: DockgeStackDetailScreen(name: 'immich')),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'every stack action is a finger target',
    (tester) async {
      await _pump(tester);

      // The chips measured 34pt: padding plus one labelMedium line.
      for (final label in [
        'Start',
        'Stop',
        'Restart',
        'Update',
        'Down',
        'Delete',
      ]) {
        final chip = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(chip, findsOneWidget, reason: label);
        expect(
          tester.getSize(chip).height,
          greaterThanOrEqualTo(44),
          reason: '$label is ${tester.getSize(chip).height} tall',
        );
      }
    },
    variant: TargetPlatformVariant.mobile(),
  );
}
