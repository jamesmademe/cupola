import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_action.dart';
import 'package:cupola/core/widgets/media_detail_actions.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('resolveMediaAction', () {
    const all = MediaActionCapabilities(
      canSearch: true,
      canInteractiveSearch: true,
      canImport: true,
      canMonitor: true,
      canOpenQueue: true,
      canRequest: true,
      canAdd: true,
    );
    const none = MediaActionCapabilities();

    MediaPrimaryAction resolve(
      MediaStatusInfo status, [
      MediaActionCapabilities caps = all,
    ]) => resolveMediaAction(status, caps, serviceName: 'Radarr');

    test('an unreachable download client promotes the queue', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(
        action.consequence,
        'Nothing moves until the download client answers.',
      );
    });

    test('a failed transfer promotes another release', () {
      final action = resolve(
        const MediaStatusInfo(
          pipeline: MediaPipeline.failed,
          detail: 'No files found',
        ),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Interactive search');
      expect(
        action.consequence,
        "This release won't finish. Radarr reports: No files found.",
      );
    });

    test('a blocked import promotes the manual import', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
      );
      expect(action.kind, MediaActionKind.manualImport);
      expect(action.label, 'Finish import');
      expect(action.consequence, contains('Radarr'));
    });

    test('a blocked import falls back to the queue without an import path', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
        const MediaActionCapabilities(canOpenQueue: true),
      );
      expect(action.kind, MediaActionKind.openQueue);
    });

    test('a stalled transfer keeps its frozen percentage', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.43),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(
        action.consequence,
        'No bytes are moving right now; it sits at 43%.',
      );
    });

    test('an in-flight download promotes the queue with its progress', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.downloading,
          progress: 0.6,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(action.consequence, 'The download client has it, 60% through.');
    });

    test('a queued item does not advertise its undrawn progress', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.queued,
          progress: 0.6,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(
        action.consequence,
        'This title is waiting its turn; no bytes have moved yet.',
      );
    });

    test('the pipeline beats being unmonitored', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.downloading,
          unmonitored: true,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
    });

    test('an unmonitored item promotes monitoring', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          unmonitored: true,
        ),
      );
      expect(action.kind, MediaActionKind.monitor);
      expect(action.consequence, "Radarr isn't searching for this title.");
    });

    test('an untracked item prefers a request over an add', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
      );
      expect(action.kind, MediaActionKind.request);

      final adding = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
        const MediaActionCapabilities(canAdd: true),
      );
      expect(adding.kind, MediaActionKind.add);
      expect(adding.label, 'Add to Radarr');
    });

    test('an untracked item with no add path yields a sentence', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
        none,
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        'Nothing happens until Radarr is tracking this title.',
      );
    });

    test('a missing item promotes a search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.missing),
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Automatic search');
    });

    test('a partial item promotes a search for the gap', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.partial),
        all,
        serviceName: 'Sonarr',
        partialSummary: '41 of 48 episodes on disk.',
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Automatic search');
      expect(action.consequence, '41 of 48 episodes on disk.');
    });

    test('an upgradable item promotes an interactive search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.upgradable),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Interactive search');
    });

    test('an available item promotes nothing at all', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.available),
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        "Radarr has everything it expects, so it isn't searching.",
      );
    });

    test('an unreleased item can carry its own date', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.unavailable),
        all,
        serviceName: 'Radarr',
        consequenceOverride: 'Jul 17, 2026',
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        "There's nothing to search for until Jul 17, 2026.",
      );
    });

    test('a deleted item names the service it left', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.deleted),
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        'Nothing changes here until this title is back in Radarr.',
      );
    });

    test('an unknown status falls back to what the service said', () {
      expect(
        resolve(const MediaStatusInfo(detail: 'Nothing came back')).consequence,
        'Radarr reports: Nothing came back.',
      );
      expect(
        resolve(const MediaStatusInfo.unknown()).consequence,
        "Radarr didn't report a state for this title.",
      );
    });

    test('every capability withheld promotes nothing, never a dead button', () {
      for (final status in const [
        MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
        MediaStatusInfo(pipeline: MediaPipeline.failed),
        MediaStatusInfo(pipeline: MediaPipeline.stalled),
        MediaStatusInfo(pipeline: MediaPipeline.downloading),
        MediaStatusInfo(availability: MediaAvailability.missing),
        MediaStatusInfo(availability: MediaAvailability.partial),
        MediaStatusInfo(availability: MediaAvailability.upgradable),
        MediaStatusInfo(
          availability: MediaAvailability.missing,
          unmonitored: true,
        ),
      ]) {
        final action = resolve(status, none);
        expect(action.kind, MediaActionKind.none, reason: '$status');
        expect(action.consequence, isNotEmpty, reason: '$status');
      }
    });
  });

  group('showMediaDetailActions', () {
    testWidgets('Delete is not a peer of Import', (tester) async {
      await _openSheet(tester);

      final divider = find.byType(Divider);
      expect(divider, findsOneWidget);

      final importY = tester.getCenter(find.text('Manual import')).dy;
      final dividerY = tester.getCenter(divider).dy;
      final deleteY = tester.getCenter(find.text('Delete from Radarr')).dy;

      // Delete sits below a divider, last, rather than roughly ten points from
      // Import in the same group told apart by hue alone.
      expect(importY, lessThan(dividerY));
      expect(dividerY, lessThan(deleteY));
      for (final label in const [
        'Interactive search',
        'Automatic search',
        'Manual import',
      ]) {
        expect(tester.getCenter(find.text(label)).dy, lessThan(deleteY));
      }
    });

    testWidgets('a destructive row takes the same ink as every other row', (
      tester,
    ) async {
      await _openSheet(tester);

      // Red means unreachable and nothing else. Delete is set apart by where
      // it sits, below the divider and last, never by colour.
      final scheme = Theme.of(
        tester.element(find.text('Delete from Radarr')),
      ).colorScheme;
      final deleteLabel = tester
          .widget<Text>(find.text('Delete from Radarr'))
          .style
          ?.color;
      final deleteGlyph = tester
          .widget<Icon>(find.byIcon(Icons.delete_outline_rounded))
          .color;
      expect(deleteLabel, scheme.onSurface);
      expect(deleteGlyph, scheme.onSurfaceVariant);
      expect(
        deleteLabel,
        tester.widget<Text>(find.text('Manual import')).style?.color,
      );
      for (final red in [
        scheme.error,
        statusToneColor(
          scheme,
          StatusTone.error,
          surface: scheme.surfaceContainer,
        ),
      ]) {
        expect(deleteLabel, isNot(red));
        expect(deleteGlyph, isNot(red));
      }
    });

    testWidgets('every row clears the 44pt touch minimum', (tester) async {
      await _openSheet(tester);

      for (final label in const ['Manual import', 'Delete from Radarr']) {
        expect(
          tester.getSize(_rowOf(tester, label)).height,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('a spent sheet goes inert while it leaves', (tester) async {
      var imports = 0;
      var deletes = 0;

      await _openSheet(
        tester,
        onImport: () => imports++,
        onDelete: () => deletes++,
      );

      await tester.tap(find.text('Manual import'));
      // One frame in: the sheet has popped but is still on screen for the
      // length of its exit, and every row on it is a bare closure that pops
      // before the host learns anything. A sheet is spent on one action, so
      // nothing on it is live any more: not the row that was tapped and not
      // the destructive one beside it.
      await tester.pump();

      PressableScale row(String label) =>
          tester.widget<PressableScale>(_rowOf(tester, label));
      expect(row('Manual import').onTap, isNull);
      expect(row('Delete from Radarr').onTap, isNull);

      await tester.pumpAndSettle();

      expect(imports, 1);
      expect(deletes, 0);
      // ...and the page underneath is still there.
      expect(find.text('Open actions'), findsOneWidget);
    });
  });
}

Finder _rowOf(WidgetTester tester, String label) => find
    .ancestor(of: find.text(label), matching: find.byType(PressableScale))
    .first;

/// Opens the actions sheet over a page with one button, the way a detail page
/// does, with every row a service can offer and Delete the one destructive.
Future<void> _openSheet(
  WidgetTester tester, {
  VoidCallback? onImport,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMediaDetailActions(
              context,
              accent: ServiceKey.radarr.accent,
              title: 'Inception',
              actions: [
                MediaOverflowAction(
                  label: 'Interactive search',
                  icon: Icons.search_rounded,
                  onInvoke: () {},
                ),
                MediaOverflowAction(
                  label: 'Automatic search',
                  icon: Icons.saved_search_rounded,
                  onInvoke: () {},
                ),
                MediaOverflowAction(
                  label: 'Manual import',
                  icon: Icons.download_for_offline_outlined,
                  onInvoke: onImport ?? () {},
                ),
                MediaOverflowAction.destructive(
                  label: 'Delete from Radarr',
                  icon: Icons.delete_outline_rounded,
                  onInvoke: onDelete ?? () {},
                ),
              ],
            ),
            child: const Text('Open actions'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open actions'));
  await tester.pumpAndSettle();
}
