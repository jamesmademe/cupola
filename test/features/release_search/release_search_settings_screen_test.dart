import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_screen.dart';

import '../../test_helpers/settings_scope.dart';

void main() {
  /// Mounts the screen for [platform]. Null means "ask the host", which under
  /// test is a desktop — the case the status row answers.
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    TargetPlatform? platform,
    bool backgroundEnabled = false,
    // Null is the honest default here: without a plugin behind it the OS has no
    // answer, which is exactly what an unconfigured host reports.
    bool? permission,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(),
        releaseSearchPlatformProvider.overrideWith((ref) => platform),
        notificationPermissionProvider.overrideWith((ref) async => permission),
      ],
    );
    addTearDown(container.dispose);
    if (backgroundEnabled) {
      container
          .read(releaseSearchSettingsProvider.notifier)
          .setBackgroundEnabled(true);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const ReleaseSearchSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The switch in the row whose label starts with [labelPrefix].
  Switch switchIn(WidgetTester tester, String labelPrefix) {
    return tester.widgetList<Switch>(find.byType(Switch)).firstWhere((s) {
      return true;
    }, orElse: () => throw StateError('no Switch for $labelPrefix'));
  }

  group('on a phone', () {
    testWidgets('the master switch is off and says what off means', (
      tester,
    ) async {
      await pumpScreen(tester, platform: TargetPlatform.iOS);

      expect(find.text('Background search'), findsWidgets);
      expect(
        find.textContaining('Searches end when you leave Cupola'),
        findsOneWidget,
      );
      expect(
        switchIn(tester, 'Background search').value,
        isFalse,
        reason: 'the shipped default is off, and the UI must show that',
      );
    });

    testWidgets('the trade-off is disclosed before it bites', (tester) async {
      await pumpScreen(tester, platform: TargetPlatform.iOS);

      // The headline is unconditional: it is the sentence that names the cost.
      expect(
        find.textContaining('admin API key', findRichText: true),
        findsOneWidget,
        reason:
            'the key being administrative is the whole reason this is a '
            'disclosure and not a footnote',
      );
      // And the detail is behind a node a screen reader can find and open,
      // rather than an information glyph.
      expect(find.text('What is stored, and for how long'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
    });

    testWidgets('the iOS detail names the backup and its mitigation', (
      tester,
    ) async {
      await pumpScreen(tester, platform: TargetPlatform.iOS);
      await tester.tap(find.text('What is stored, and for how long'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Advanced Data Protection'),
        findsOneWidget,
        reason:
            'the plist inside a device backup is the one copy that can leave '
            'the device, so the mitigation belongs next to it',
      );
      expect(find.textContaining('11 minutes'), findsOneWidget);
    });

    testWidgets('the Android detail names the absence of a backup instead', (
      tester,
    ) async {
      await pumpScreen(tester, platform: TargetPlatform.android);
      await tester.tap(find.text('What is stored, and for how long'));
      await tester.pumpAndSettle();

      expect(find.textContaining('excluded from every backup'), findsOneWidget);
      expect(
        find.textContaining('Advanced Data Protection'),
        findsNothing,
        reason: 'naming an Apple mitigation on Android would be noise',
      );
    });

    testWidgets('notifications cannot be armed while the master is off', (
      tester,
    ) async {
      await pumpScreen(tester, platform: TargetPlatform.android);

      expect(
        find.textContaining('Needs Background search'),
        findsOneWidget,
        reason: 'a disabled control has to say what would enable it',
      );
      final notify = tester
          .widgetList<Switch>(find.byType(Switch))
          .firstWhere((s) => s.onChanged == null);
      expect(notify.value, isFalse);
    });

    testWidgets('notifications are armable once the master is on', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        platform: TargetPlatform.android,
        backgroundEnabled: true,
      );

      expect(find.textContaining('Needs Background search'), findsNothing);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).every(
          (s) => s.onChanged != null,
        ),
        isTrue,
        reason: 'with the master on, nothing on this screen is inert',
      );
    });

    testWidgets('with the master off the limits card describes the in-app mode',
        (tester) async {
      await pumpScreen(tester, platform: TargetPlatform.android);

      expect(
        find.textContaining('A search runs as long as Cupola is running'),
        findsOneWidget,
      );
      expect(
        find.textContaining('the outcome is lost'),
        findsNothing,
        reason:
            'losing an outcome to a system kill is a background-mode risk, and '
            'describing it while the mode is off describes a mode nobody is in',
      );
      expect(
        find.textContaining('Android stops background work'),
        findsNothing,
        reason: 'an unreachable ceiling is not a limit, it is trivia',
      );
    });

    testWidgets('with the master on it describes the background mode', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        platform: TargetPlatform.android,
        backgroundEnabled: true,
      );

      expect(find.textContaining('the outcome is lost'), findsOneWidget);
      expect(
        find.textContaining('Android stops background work'),
        findsOneWidget,
        reason: 'the nine-minute ceiling is reachable again',
      );
    });

    testWidgets('the grab window is stated whichever mode is on', (
      tester,
    ) async {
      // Sonarr's own limit, true of the feature rather than of the mode — so
      // the switch must not take it away.
      await pumpScreen(tester, platform: TargetPlatform.iOS);
      expect(find.textContaining('30 minutes'), findsOneWidget);
    });

    testWidgets('and so is the grab window with the master on', (tester) async {
      await pumpScreen(
        tester,
        platform: TargetPlatform.iOS,
        backgroundEnabled: true,
      );
      expect(find.textContaining('30 minutes'), findsOneWidget);
    });
  });

  group('the system permission line', () {
    testWidgets('says granted when the OS allows it', (tester) async {
      await pumpScreen(
        tester,
        platform: TargetPlatform.iOS,
        backgroundEnabled: true,
        permission: true,
      );
      expect(find.text('System permission: granted'), findsOneWidget);
    });

    testWidgets('names the route when the OS has blocked it', (tester) async {
      // The drift this closes: a permission revoked in system settings leaves
      // the app's own toggle on and every notice silently dropped, which reads
      // as a broken feature rather than a withdrawn permission.
      await pumpScreen(
        tester,
        platform: TargetPlatform.iOS,
        backgroundEnabled: true,
        permission: false,
      );
      expect(
        find.textContaining('Blocked in Settings'),
        findsOneWidget,
        reason: 'a denial has to name where to lift it, not just report itself',
      );
    });

    testWidgets('stays silent when the platform cannot answer', (tester) async {
      // Unknown is not denied: rendering it as a denial would send someone to
      // fix a permission nothing ever asked for.
      await pumpScreen(
        tester,
        platform: TargetPlatform.iOS,
        backgroundEnabled: true,
      );
      expect(find.textContaining('System permission'), findsNothing);
      expect(find.textContaining('Blocked'), findsNothing);
    });

    testWidgets('stays silent while the master switch is off', (tester) async {
      // The row already explains why it is disabled; a second sentence about a
      // permission that currently changes nothing is noise.
      await pumpScreen(
        tester,
        platform: TargetPlatform.iOS,
        permission: true,
      );
      expect(find.textContaining('System permission'), findsNothing);
    });
  });

  group('on desktop', () {
    testWidgets('there is no switch, and no warning either', (tester) async {
      // The capability is already there and no record exists to warn about. A
      // switched-off toggle would advertise a missing feature; a disclosure
      // would attach a risk to a platform that does not carry it.
      await pumpScreen(tester);

      expect(
        find.textContaining('desktop never suspends the app'),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(
        find.textContaining('admin API key'),
        findsNothing,
        reason: 'nothing is handed to the system here, so there is no cost to '
            'disclose',
      );
    });

    testWidgets('the stepper settings still work — they govern the foreground '
        'path too', (tester) async {
      // The reason this screen is not simply disabled wholesale: concurrency
      // and the timeout apply to a search that runs in the app as well.
      final container = await pumpScreen(tester);

      expect(find.text('At the same time'), findsOneWidget);
      expect(find.text('Give up after'), findsOneWidget);

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(
        container.read(releaseSearchSettingsProvider).concurrency,
        kDefaultSearchConcurrency + 1,
      );
    });

    testWidgets('notifications stay available — the app is simply running', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('Needs Background search'), findsNothing);
      expect(find.textContaining('Not needed here'), findsOneWidget);
    });
  });
}
