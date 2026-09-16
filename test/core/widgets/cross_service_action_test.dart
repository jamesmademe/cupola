import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

/// BONUS 3, as a set of rules rather than a look.
///
/// Both of the obvious implementations were in the tree and both failed the
/// same user in the same way: `onPressed: null` publishes
/// `Semantics(enabled: false)`, which VoiceOver and TalkBack **skip**, and
/// `SizedBox.shrink()` teaches that the feature does not exist. So what is
/// under test is reachability, not opacity.
Future<void> _pump(
  WidgetTester tester, {
  required List<ServiceKey> configured,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: await settingsScopeOverrides(configured: configured),
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
}

void main() {
  group('a target that is not configured', () {
    testWidgets('stays on the screen reader\'s path and says what it wants', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        configured: const [],
        child: CrossServiceAction(
          target: ServiceKey.qbittorrent,
          label: 'Open in qBittorrent',
          blockedMessage: 'Connect qBittorrent to open this transfer',
          onTap: () {},
          child: const Icon(Icons.open_in_new),
        ),
      );

      // Reachable, named, still a button, still enabled, still tappable — the
      // five things the two previous implementations took away between them.
      expect(
        tester.getSemantics(find.byType(CrossServiceAction)),
        containsSemantics(
          label: 'Open in qBittorrent',
          hint: 'requires qBittorrent',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('keeps a 44pt target', (tester) async {
      // A dimmed control that is also hard to hit is a control the user
      // concludes is broken.
      await _pump(
        tester,
        configured: const [],
        child: Align(
          alignment: Alignment.topLeft,
          child: CrossServiceAction(
            target: ServiceKey.qbittorrent,
            label: 'Open in qBittorrent',
            blockedMessage: 'Connect qBittorrent to open this transfer',
            onTap: () {},
            child: const SizedBox(width: 8, height: 8),
          ),
        ),
      );

      final size = tester.getSize(find.byType(CrossServiceAction));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('answers a tap with a toast whose action is the fix', (
      tester,
    ) async {
      var acted = 0;
      await _pump(
        tester,
        configured: const [],
        child: CrossServiceAction(
          target: ServiceKey.qbittorrent,
          label: 'Open in qBittorrent',
          blockedMessage: 'Connect qBittorrent to open this transfer',
          onTap: () => acted++,
          child: const Icon(Icons.open_in_new),
        ),
      );

      await tester.tap(find.byType(CrossServiceAction));
      await tester.pump();

      // The jump did not happen…
      expect(acted, 0);
      // …and the user was told what would make it happen, with one door.
      expect(
        find.text('Connect qBittorrent to open this transfer'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    });

    testWidgets('is dimmed, and dimming is the only thing it loses', (
      tester,
    ) async {
      await _pump(
        tester,
        configured: const [],
        child: CrossServiceAction(
          target: ServiceKey.qbittorrent,
          label: 'Open in qBittorrent',
          blockedMessage: 'Connect qBittorrent to open this transfer',
          onTap: () {},
          child: const Icon(Icons.open_in_new),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(CrossServiceAction),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, GatedAffordance.dimmedOpacity);
    });
  });

  group('a target that is configured', () {
    testWidgets('acts, at full ink, with no toast', (tester) async {
      var acted = 0;
      await _pump(
        tester,
        configured: const [ServiceKey.qbittorrent],
        child: CrossServiceAction(
          target: ServiceKey.qbittorrent,
          label: 'Open in qBittorrent',
          blockedMessage: 'Connect qBittorrent to open this transfer',
          onTap: () => acted++,
          child: const Icon(Icons.open_in_new),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(CrossServiceAction),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      await tester.tap(find.byType(CrossServiceAction));
      await tester.pump();
      expect(acted, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a configured service that is DOWN still acts', (tester) async {
      // "Not configured is not the same as not answering." The jump is still
      // the right thing to offer; the destination will say for itself that it
      // did not answer. Nothing here consults health, and that is the point.
      var acted = 0;
      await _pump(
        tester,
        configured: const [ServiceKey.qbittorrent],
        child: CrossServiceAction(
          target: ServiceKey.qbittorrent,
          label: 'Open in qBittorrent',
          blockedMessage: 'Connect qBittorrent to open this transfer',
          onTap: () => acted++,
          child: const Icon(Icons.open_in_new),
        ),
      );
      await tester.tap(find.byType(CrossServiceAction));
      await tester.pump();
      expect(acted, 1);
    });
  });

  group('the capability twin', () {
    testWidgets('a read-only key dims the write but keeps it reachable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var acted = 0;

      final container = ProviderContainer(
        overrides: await settingsScopeOverrides(
          configured: const [ServiceKey.unraid],
        ),
      );
      addTearDown(container.dispose);
      // The probe answers on connect, before the page builds — recorded here
      // rather than from a Consumer, which would be writing to a provider
      // during a build.
      container
          .read(capabilityScopeProvider.notifier)
          .record('unraid-1', CapabilityScope.readOnly);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: CapabilityGatedAction(
                service: ServiceKey.unraid,
                connectionId: 'unraid-1',
                label: 'Restart jellyfin',
                blockedMessage:
                    'This Unraid key can read. Restarting a container '
                    'needs a key with write scope.',
                onTap: () => acted++,
                child: const Icon(Icons.restart_alt),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(CapabilityGatedAction)),
        containsSemantics(
          label: 'Restart jellyfin',
          hint: 'requires a read-write key',
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byType(CapabilityGatedAction));
      await tester.pump();
      expect(acted, 0);
      expect(
        find.widgetWithText(SnackBarAction, 'Update the key'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an unprobed connection does not dim anything', (tester) async {
      // The window between connect and the probe answering. Dimming here and
      // un-dimming a frame later would make every healthy cold open flicker.
      var acted = 0;
      await _pump(
        tester,
        configured: const [ServiceKey.unraid],
        child: CapabilityGatedAction(
          service: ServiceKey.unraid,
          connectionId: 'not-probed-yet',
          label: 'Restart jellyfin',
          blockedMessage: 'needs write scope',
          onTap: () => acted++,
          child: const Icon(Icons.restart_alt),
        ),
      );
      await tester.tap(find.byType(CapabilityGatedAction));
      await tester.pump();
      expect(acted, 1);
    });
  });

  group('the banner', () {
    testWidgets('is not a fault: no fill, no border, and not the error tone', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CapabilityBanner(
              message:
                  'This Unraid key can read. Start, stop and update need a key '
                  'with write scope.',
              onFix: () {},
            ),
          ),
        ),
      );

      final scheme = Theme.of(
        tester.element(find.byType(CapabilityBanner)),
      ).colorScheme;
      final glyph = tester.widget<Icon>(find.byType(Icon)).color;

      // A credential that may only read is a configuration fact, not a fault —
      // amber or red would send the user hunting for breakage that is not there.
      expect(glyph, isNot(scheme.error));
      for (final decorated in tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(CapabilityBanner),
          matching: find.byType(DecoratedBox),
        ),
      )) {
        final decoration = decorated.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNull);
          expect(decoration.border, isNull);
        }
      }
    });

    testWidgets('offers one action and no dismiss', (tester) async {
      // Nothing to acknowledge: the scope is still what it is a second later,
      // and the controls below are still dimmed. Only a new key changes it.
      var fixed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CapabilityBanner(
              message: 'This key can read.',
              onFix: () => fixed++,
            ),
          ),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
      await tester.tap(find.text('Update the key'));
      await tester.pump();
      expect(fixed, 1);
    });
  });
}
