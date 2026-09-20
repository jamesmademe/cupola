import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_terminal_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('requires a stack before joining the combined terminal', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.dockge],
          ),
          dockgeStackListProvider.overrideWith(
            (ref) => Stream.value(const [
              DockgeStack(name: 'immich', status: DockgeStackStatus.running),
            ]),
          ),
          dockgeTerminalTextProvider.overrideWith(
            (ref, stack) => Stream.value('container started\n'),
          ),
        ],
        child: const MaterialApp(home: DockgeTerminalScreen(showAppBar: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('immich'), findsOneWidget);
    expect(find.textContaining('container started'), findsNothing);

    await tester.tap(find.text('immich'));
    await tester.pumpAndSettle();

    expect(find.text('immich · combined log'), findsOneWidget);
    expect(find.textContaining('container started'), findsOneWidget);
  });

  testWidgets('not configured never reaches Socket.IO providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await settingsScopeOverrides(),
        child: const MaterialApp(home: DockgeTerminalScreen(showAppBar: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.text('Choose a stack'), findsNothing);
  });

  testWidgets('a disconnected terminal stream has a recoverable error state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dockgeTerminalTextProvider.overrideWith(
            (ref, stack) => Stream.error(Exception('disconnected')),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DockgeTerminalPane(stackName: 'immich')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terminal stream disconnected'), findsOneWidget);
  });
}
