import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/outside/data/outside_settings.dart';
import 'package:cupola/features/outside/data/outside_speaker.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/outside/presentation/settings_notifications_screen.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../../../test_helpers/settings_scope.dart';

/// Settings › Notifications: two switches, asked for at the switch, honest
/// about when the phone checks.
void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.iOS,
    Audience audience = Audience.operator,
    List<ServiceKey> configured = const [ServiceKey.seerr, ServiceKey.radarr],
    bool granted = true,
    bool? permission,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: configured),
        outsidePlatformProvider.overrideWithValue(platform),
        shellAudienceProvider.overrideWith(() => _Fixed(audience)),
        notificationPermissionProvider.overrideWith((ref) async => permission),
        releaseSearchNotificationsProvider.overrideWithValue(
          _Notifications(granted),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const SettingsNotificationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('the operator has both, off, and the honest line for iOS', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Ready to watch'), findsOneWidget);
    expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [
      false,
      false,
    ]);
    expect(
      find.text(
        'Cupola checks in the background when iOS allows it, which can be '
        'hours apart. A service that is only out of reach never sends one.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android says its own cadence', (tester) async {
    await pumpScreen(tester, platform: TargetPlatform.android);
    expect(
      find.textContaining('Cupola checks about every 15 minutes.'),
      findsOneWidget,
    );
  });

  testWidgets('without Seerr, nothing could arrive: no Ready to watch', (
    tester,
  ) async {
    await pumpScreen(tester, configured: const [ServiceKey.radarr]);
    expect(find.text('Ready to watch'), findsNothing);
    expect(find.text('Needs you'), findsOneWidget);
  });

  testWidgets('the requester has her arrivals and none of the operator', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      audience: Audience.requester,
      configured: const [ServiceKey.seerr],
    );
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('When something you asked for arrives.'), findsOneWidget);
    expect(find.textContaining('service'), findsNothing);
  });

  testWidgets('a switch turned on asks the OS first, and keeps its answer', (
    tester,
  ) async {
    final container = await pumpScreen(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(container.read(outsideNoticeKindsProvider), {
      OutsideNoticeKind.needsYou,
    });
  });

  testWidgets('refused, the switch stays off and says where it is off', (
    tester,
  ) async {
    final container = await pumpScreen(tester, granted: false);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(container.read(outsideNoticeKindsProvider), isEmpty);
    expect(
      find.text('Notifications are turned off for Cupola in system settings.'),
      findsOneWidget,
    );
  });

  testWidgets('a switch on that the OS blocks says so, with the way there', (
    tester,
  ) async {
    final container = await pumpScreen(tester, permission: false);
    expect(find.text('Notifications are blocked'), findsNothing);
    await container
        .read(outsideNoticeKindsProvider.notifier)
        .set(OutsideNoticeKind.needsYou, on: true);
    await tester.pumpAndSettle();
    expect(find.text('Notifications are blocked'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  group('a tap', () {
    test('opens the place its payload names', () {
      expect(outsideNoticeRouteOf('route:/activity'), '/activity');
      expect(outsideNoticeRouteOf('9f3c-job-id'), isNull);
      expect(outsideNoticeRouteOf('route:activity'), isNull);
      expect(outsideNoticeRouteOf(null), isNull);
    });
  });
}

class _Fixed extends ShellAudienceNotifier {
  _Fixed(this.audience);
  final Audience audience;

  @override
  Audience build() => audience;
}

class _Notifications extends ReleaseSearchNotifications {
  _Notifications(this.granted);
  final bool granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<bool?> permissionGranted() async => granted;
}
