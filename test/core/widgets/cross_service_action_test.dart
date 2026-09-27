import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/capability_overrides.dart';
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

  _gatedVariants();
  _bannerSlot();
}

const _unraid = 'unraid';

/// A gated control under a router, so the toast's fix has somewhere to land,
/// with the unraid connection answering [grant].
Future<GoRouter> _pumpGated(
  WidgetTester tester, {
  required CapabilityGrant grant,
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScaler.scale(1),
          maxScaleFactor: textScaler.scale(1),
          child: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) => const Scaffold(body: Text('settings')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.unraid]),
        capabilityOverride({_unraid: grant}),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// The shapes a write takes in the three gated services, each held to the same
/// four rules: reachable, dimmed, hinted, and answering a tap with the fix.
void _gatedVariants() {
  const blocked = 'This Unraid key can\'t start or stop VMs.';
  const hint = 'requires a key that can write VMs';

  Widget iconButton(VoidCallback onTap) => CapabilityGatedAction.icon(
    service: ServiceKey.unraid,
    connectionId: _unraid,
    resource: 'vms',
    icon: const Icon(Icons.play_arrow_rounded),
    tooltip: 'Start Home Assistant',
    blockedMessage: blocked,
    hint: hint,
    onTap: onTap,
  );

  Widget textButton(VoidCallback onTap) => CapabilityGatedAction.builder(
    service: ServiceKey.unraid,
    connectionId: _unraid,
    resource: 'vms',
    blockedMessage: blocked,
    hint: hint,
    onTap: onTap,
    builder: (context, onPressed, annotate) =>
        TextButton(onPressed: onPressed, child: annotate(const Text('Start'))),
  );

  Future<void> expectFix(WidgetTester tester, GoRouter router) async {
    expect(find.text(blocked), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Update the key'));
    await tester.pumpAndSettle();
    expect(_location(router), '/settings/service/unraid?i=unraid');
  }

  group('the icon shape', () {
    testWidgets(
      'blocked: reachable, dimmed, hinted, and answers with the fix',
      (tester) async {
        var acted = 0;
        final router = await _pumpGated(
          tester,
          grant: const CapabilityGrant.readOnly(),
          child: iconButton(() => acted++),
        );

        expect(
          tester.getSemantics(find.byType(IconButton)),
          containsSemantics(
            // The tooltip is the icon button's name; the hint sits beside it.
            tooltip: 'Start Home Assistant',
            hint: hint,
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        final opacity = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(IconButton),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacity.opacity, GatedAffordance.dimmedOpacity);
        // Material's 48pt target, never shrunk with the glyph.
        expect(tester.getSize(find.byType(IconButton)).height, 48);
        expect(find.byTooltip('Start Home Assistant'), findsOneWidget);

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        expect(acted, 0);
        await expectFix(tester, router);
      },
    );

    testWidgets('live: acts at full ink with no hint and no toast', (
      tester,
    ) async {
      var acted = 0;
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.readWrite(),
        child: iconButton(() => acted++),
      );
      expect(
        find.descendant(
          of: find.byType(IconButton),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(tester.getSemantics(find.byType(IconButton)).hint, isEmpty);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(acted, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('per resource: a partial grant gates only what it omits', (
      tester,
    ) async {
      var acted = 0;
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.partial({'vms'}),
        child: iconButton(() => acted++),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(acted, 1);
    });

    testWidgets('could not ask: its own hint, and the toast re-asks', (
      tester,
    ) async {
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.unanswered(),
        child: iconButton(() {}),
      );
      expect(
        tester.getSemantics(find.byType(IconButton)),
        containsSemantics(hint: 'this key\'s permissions are unknown'),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(
        find.text(CapabilityCopy.unansweredToast(ServiceKey.unraid)),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SnackBarAction, 'Check again'),
        findsOneWidget,
      );
    });
  });

  group('the builder shape', () {
    testWidgets('blocked: the button keeps its node, and the hint is on it', (
      tester,
    ) async {
      var acted = 0;
      final router = await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        child: textButton(() => acted++),
      );

      expect(
        tester.getSemantics(find.byType(TextButton)),
        containsSemantics(
          label: 'Start',
          hint: hint,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull,
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, GatedAffordance.dimmedOpacity);
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(acted, 0);
      await expectFix(tester, router);
    });

    testWidgets('live: acts, with no toast', (tester) async {
      var acted = 0;
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.unknown(),
        child: textButton(() => acted++),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(acted, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.getSemantics(find.byType(TextButton)).hint, isEmpty);
    });
  });

  group('the toggle shape', () {
    Widget toggle(List<bool> changes, {required bool value}) =>
        CapabilityGatedAction.toggle(
          service: ServiceKey.unraid,
          connectionId: _unraid,
          value: value,
          onChanged: changes.add,
          blockedMessage: blocked,
          hint: hint,
        );

    testWidgets('blocked: a tap answers and does not flip the switch', (
      tester,
    ) async {
      final changes = <bool>[];
      final router = await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        child: toggle(changes, value: true),
      );

      expect(
        tester.getSemantics(find.byType(Switch)),
        containsSemantics(
          hint: hint,
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.byType(Switch), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, GatedAffordance.dimmedOpacity);
      expect(
        tester.getSize(find.byType(Switch)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await expectFix(tester, router);
    });

    testWidgets('live: the change goes through', (tester) async {
      final changes = <bool>[];
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.readWrite(),
        child: toggle(changes, value: true),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(changes, [false]);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the menu shape', () {
    Widget menu(List<String> acted) => Consumer(
      builder: (context, ref, _) => PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (value) {
          if (!capabilityWriteAllowed(
            context,
            ref,
            service: ServiceKey.unraid,
            connectionId: _unraid,
            resource: 'vms',
            blockedMessage: blocked,
          )) {
            return;
          }
          acted.add(value);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'stop',
            child: CapabilityGatedMenuLabel(
              service: ServiceKey.unraid,
              connectionId: _unraid,
              resource: 'vms',
              text: 'Stop',
              hint: hint,
            ),
          ),
        ],
      ),
    );

    testWidgets('blocked: the item stays enabled, hinted, and toasts', (
      tester,
    ) async {
      final acted = <String>[];
      final router = await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        child: menu(acted),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
            .enabled,
        isTrue,
      );
      expect(
        tester.getSemantics(find.text('Stop')),
        containsSemantics(label: 'Stop', hint: hint, isEnabled: true),
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('Stop'), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, GatedAffordance.dimmedOpacity);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(acted, isEmpty);
      await expectFix(tester, router);
    });

    testWidgets('live: the item acts', (tester) async {
      final acted = <String>[];
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.readWrite(),
        child: menu(acted),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(acted, ['stop']);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the cross-service builder shape', () {
    testWidgets('an unconfigured target dims the caller\'s own button', (
      tester,
    ) async {
      var acted = 0;
      await _pump(
        tester,
        configured: const [],
        child: CrossServiceAction.builder(
          target: ServiceKey.radarr,
          blockedMessage: 'Connect Radarr to open this movie',
          onTap: () => acted++,
          builder: (context, onPressed, annotate) => TextButton(
            onPressed: onPressed,
            child: annotate(const Text('Open in Radarr')),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(TextButton)),
        containsSemantics(
          label: 'Open in Radarr',
          hint: 'requires Radarr',
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(acted, 0);
      expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    });
  });
}

void _bannerSlot() {
  const copy = CapabilityCopy(
    service: ServiceKey.unraid,
    answered:
        'This Unraid key can read. Starting and stopping VMs needs a key '
        'with write access to VMs.',
    scope: 'write access to VMs',
    hint: 'requires a key that can write VMs',
  );

  Widget slot({Set<String>? resources}) => CapabilityBannerSlot(
    connectionId: _unraid,
    copy: copy,
    resources: resources,
  );

  group('the banner slot', () {
    testWidgets('says nothing while unknown or read-write', (tester) async {
      for (final grant in const [
        CapabilityGrant.unknown(),
        CapabilityGrant.readWrite(),
        CapabilityGrant.partial({'vms'}),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpGated(
          tester,
          grant: grant,
          child: slot(resources: {'vms'}),
        );
        expect(find.byType(CapabilityBanner), findsNothing, reason: '$grant');
      }
    });

    testWidgets('a read-only answer gets the answered sentence and the fix', (
      tester,
    ) async {
      final router = await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        child: slot(resources: {'vms'}),
      );
      expect(find.text(copy.answered), findsOneWidget);
      await tester.tap(find.text('Update the key'));
      await tester.pumpAndSettle();
      expect(_location(router), '/settings/service/unraid?i=unraid');
    });

    testWidgets('a refusal says it was refused', (tester) async {
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.refused(),
        child: slot(),
      );
      expect(find.text(copy.refused), findsOneWidget);
    });

    testWidgets('could not ask: Check again, and it re-runs the probe', (
      tester,
    ) async {
      var probes = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: slot()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.unraid],
            ),
            capabilityProbesProvider.overrideWithValue({
              ServiceKey.unraid: (ref, id) async {
                probes++;
                return const CapabilityGrant.unanswered();
              },
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(copy.unanswered), findsOneWidget);
      expect(probes, 1);

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(probes, 2);
    });

    testWidgets('respects the page\'s resources', (tester) async {
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.partial({'vms'}),
        child: slot(resources: {'notifications'}),
      );
      expect(find.byType(CapabilityBanner), findsOneWidget);
    });

    testWidgets('stacks at a 3x reading size without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        textScaler: const TextScaler.linear(3),
        child: slot(),
      );
      expect(tester.takeException(), isNull);
      final message = tester.getRect(find.text(copy.answered));
      final action = tester.getRect(find.text('Update the key'));
      // The action sits under the sentence, not beside it.
      expect(action.top, greaterThanOrEqualTo(message.bottom));
    });

    testWidgets('is not a live region', (tester) async {
      // A standing state, not an event: drawn on every visit to a read-only
      // connection's pages, it would otherwise interrupt each of them.
      await _pumpGated(
        tester,
        grant: const CapabilityGrant.readOnly(),
        child: slot(),
      );
      expect(
        tester.getSemantics(find.byType(CapabilityBanner)),
        isNot(containsSemantics(isLiveRegion: true)),
      );
    });
  });
}
