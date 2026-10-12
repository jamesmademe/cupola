import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../../../test_helpers/settings_scope.dart';

/// The inspector, in the theme it was never checked in.
///
/// The pane painted three `AppColors` constants straight onto the canvas:
/// `navActivity` for its own glyph, `warning` for a troubled transfer's bar,
/// `success` for a finished row's dot. Those are dark-palette values (2.20:1,
/// 1.39:1 and 2.07:1 against surface-light), so the pane rendered the dark
/// palette on the Light canvas and its three coloured marks were the three
/// least legible things on it.
///
/// And the dot was worse than dim: it painted **red** for a failed import. Red
/// in this app means one thing: a connection that did not answer, and an
/// import the service reported as failed is the opposite of that.
GlobalActivityItem _queueItem({required bool warning}) => GlobalActivityItem(
  kind: GlobalActivityKind.queue,
  service: ServiceKey.radarr,
  serviceType: ServiceType.movies,
  title: 'Dune.Part.Two.2024',
  subtitle: '2.1 GB left',
  status: MediaStatusInfo(
    labelOverride: warning ? 'Stuck' : 'Downloading',
    toneOverride: warning ? StatusTone.warning : StatusTone.info,
    hasWarning: warning,
    progress: 0.63,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  required List<GlobalActivityItem> queue,
  List<ServiceKey> unreachable = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(),
      globalNowItemsProvider.overrideWith(
        (ref) async => ActivityFeed(items: queue, results: const []),
      ),
      // Nothing unreachable unless asked: the pane's red line is correct when
      // it appears, and most of this file is not about it.
      unreachableServicesProvider.overrideWithValue(unreachable),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: SizedBox(width: 380, child: InspectorPane()),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('InspectorPane ink', () {
    // Every coloured mark the pane draws has to change between themes. A colour
    // that is byte-identical in light and dark is a palette constant that never
    // went through the walk, which is exactly what `AppColors.navActivity`,
    // `AppColors.warning` and `AppColors.success` were doing here.
    testWidgets('paints nothing at its raw dark-palette value', (tester) async {
      Color glyph() {
        return tester
            .widget<Icon>(
              find.descendant(
                of: find.byType(InspectorPane),
                matching: find.byIcon(Icons.insights_rounded),
              ),
            )
            .color!;
      }

      await _pump(tester, theme: AppTheme.darkTheme(), queue: const []);
      final dark = glyph();

      await _pump(tester, theme: AppTheme.lightTheme(), queue: const []);
      final light = glyph();

      expect(
        light,
        isNot(dark),
        reason: 'the pane glyph must be walked against the light ground',
      );
      expect(light, isNot(AppColors.navActivity));
    });

    // The bar spends the row's already-resolved tone instead of re-deciding
    // from a boolean, and the tone goes through the same walk every other status
    // colour in the app goes through.
    testWidgets('a troubled transfer takes the walked warning tone', (
      tester,
    ) async {
      final light = AppTheme.lightTheme();
      await _pump(tester, theme: light, queue: [_queueItem(warning: true)]);

      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(InspectorPane),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      final painted = bar.valueColor!.value;

      expect(painted, isNot(AppColors.warning));
      expect(
        painted,
        statusToneColor(
          light.colorScheme,
          StatusTone.warning,
          surface: light.colorScheme.surfaceContainerLowest,
        ),
      );
    });

    // A calm transfer keeps the scheme's primary, so the amber is a signal
    // rather than the pane's normal colour.
    testWidgets('a healthy transfer stays on the scheme primary', (
      tester,
    ) async {
      final light = AppTheme.lightTheme();
      await _pump(tester, theme: light, queue: [_queueItem(warning: false)]);

      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(InspectorPane),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.valueColor!.value, light.colorScheme.primary);
    });
  });

  group('InspectorPane did not answer', () {
    testWidgets('is a quiet line: red on the glyph and the title only', (
      tester,
    ) async {
      final light = AppTheme.lightTheme();
      await _pump(
        tester,
        theme: light,
        queue: const [],
        unreachable: const [ServiceKey.sonarr],
      );

      final line = find.byKey(const ValueKey('inspector-did-not-answer'));
      expect(line, findsOneWidget);
      final red = statusToneColor(
        light.colorScheme,
        StatusTone.error,
        surface: light.colorScheme.surfaceContainerLowest,
      );
      final glyph = tester.widget<Icon>(
        find.descendant(of: line, matching: find.byType(Icon)),
      );
      expect(glyph.icon, Icons.cloud_off_rounded);
      expect(glyph.color, red);
      final title = tester.widget<Text>(
        find.descendant(of: line, matching: find.text('Sonarr did not answer')),
      );
      expect(title.style?.color, red);
      expect(find.textContaining('No response'), findsNothing);

      // No fill and no border behind it: the Presence Rule.
      for (final box in tester.widgetList<Container>(
        find.descendant(of: line, matching: find.byType(Container)),
      )) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNull);
          expect(decoration.border, isNull);
        }
      }
      // Retry in ink, never red.
      final retry = tester.widget<Text>(
        find.descendant(of: line, matching: find.text('Retry')),
      );
      expect(retry.style?.color, isNot(red));
    });
  });
}
