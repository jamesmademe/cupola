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

  /// The lifecycle commands that reached the client, in order.
  final sent = <String>[];

  @override
  Future<void> joinCombinedTerminal(String stackName) async {}

  @override
  Future<void> startStack(String name) async => sent.add('start');
  @override
  Future<void> stopStack(String name) async => sent.add('stop');
  @override
  Future<void> restartStack(String name) async => sent.add('restart');
  @override
  Future<void> updateStack(String name) async => sent.add('update');
  @override
  Future<void> downStack(String name) async => sent.add('down');
  @override
  Future<void> deleteStack(String name) async => sent.add('delete');
}

Future<_QuietClient> _pump(WidgetTester tester) async {
  final client = _QuietClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(const [ServiceKey.dockge]),
        ),
        dockgeClientProvider.overrideWith((ref) => client),
        dockgeLensedClientProvider.overrideWith((ref) => client),
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
  return client;
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

  group('a command that interrupts the stack asks first', () {
    // Stop, Restart, Update and Down fired on the tap here, while the same
    // Stop and Restart on the Stacks list asked. The copy is the list row's.
    for (final (label, verb, title, confirm) in const [
      ('Stop', 'stop', 'Stop immich?', 'Stop stack'),
      ('Restart', 'restart', 'Restart immich?', 'Restart stack'),
      ('Update', 'update', 'Update immich?', 'Update stack'),
      ('Down', 'down', 'Take immich down?', 'Take down'),
    ]) {
      testWidgets('$label: Cancel sends nothing, confirm sends it', (
        tester,
      ) async {
        final client = await _pump(tester);

        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(client.sent, isEmpty);

        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, confirm));
        await tester.pumpAndSettle();
        expect(client.sent, [verb]);
      });
    }

    testWidgets('Delete asks in the same neutral dialog, naming what goes', (
      tester,
    ) async {
      final client = await _pump(tester);

      // The chip wears the accent every other chip wears: it used to be the
      // one red control on the row.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded)).color,
        tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete immich?'), findsOneWidget);
      expect(
        find.text(
          'This removes the stack and its compose files from Dockge. '
          'This cannot be undone.',
        ),
        findsOneWidget,
      );
      // The theme's own button, with a verb that names the object.
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete stack'),
      );
      expect(confirm.style, isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.sent, isEmpty);
    });

    testWidgets('Start interrupts nothing and stays one tap', (tester) async {
      final client = await _pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(client.sent, ['start']);
    });
  });
}
