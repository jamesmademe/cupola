/// A household member's Jellyfin token, read the same way on every surface,
/// per connection.
///
/// A non-administrator's token plays, browses and controls its own sessions,
/// and is refused the elevated reads: `/Users`, `/Devices`, `/ScheduledTasks`
/// and `/Library/VirtualFolders`. Devices, Tasks and Libraries said so
/// calmly; Users drew the refusal as a fault, the Overview's Libraries region
/// did too, the viewer picker said the server reports no users, the
/// connection test said the token was refused, and Activity read every
/// connection without saying which ones show only their own playback. The credential kind was the lens's alone. It is now asked per
/// connection and read wherever an elevated read is made.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';

import '../../test_helpers/profiles/profiles.dart';

/// P1 with the cabin's Jellyfin, signed in with a household member's token,
/// beside the one at home on its API key.
final _memberAtTheCabin = Profiles.p1.withConnection(
  WorldConnections.jellyfinCabin.withBehaviour(ConnectionBehaviour.readOnly),
);

const _ownPlayback = 'Showing only this account\'s playback';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// No refusal drawn anywhere in [scope] (the whole screen when null).
void _expectNoFault([Finder? scope]) {
  Finder within(Finder matching) =>
      scope == null ? matching : find.descendant(of: scope, matching: matching);
  expect(within(find.textContaining('refused')), findsNothing);
  expect(within(find.byType(AppErrorState)), findsNothing);
  expect(within(find.byType(InlineErrorRetry)), findsNothing);
}

void main() {
  group('the credential kind, per connection', () {
    test('each connection answers for its own token, and the lens is asked '
        'once', () async {
      final harness = await ProfileHarness.start(_memberAtTheCabin);
      final container = harness.container(retry: (_, _) => null);

      await container.read(
        jellyfinCredentialKindForProvider(WorldIds.jellyfinCabin).future,
      );
      await container.read(
        jellyfinCredentialKindForProvider(WorldIds.jellyfin).future,
      );
      await container.read(jellyfinCredentialKindForProvider('').future);

      expect(
        container.read(
          jellyfinLacksAdministratorForProvider(WorldIds.jellyfinCabin),
        ),
        isTrue,
      );
      expect(
        container.read(
          jellyfinLacksAdministratorForProvider(WorldIds.jellyfin),
        ),
        isFalse,
      );
      // The lens by its id and by the empty id: one `/Users/Me`.
      expect(
        harness.network
            .requestsTo(WorldIds.jellyfin)
            .where((r) => r.path == '/Users/Me'),
        hasLength(1),
      );
    });
  });

  group('P2+J, Anna\'s own token', () {
    test(
      'the connection test accepts it, as the Dashboard\'s probe does',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2WithJellyfin);
        final diagnosis = await harness
            .container(retry: (_, _) => null)
            .read(instanceDiagnosisProvider(WorldIds.jellyfin).future);

        expect(diagnosis.status, ServiceConnectionStatus.connected);
      },
    );

    testWidgets('Users: the administrator placeholder, as Devices and Tasks '
        'have', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const JellyfinUsersScreen(),
      );

      expect(find.text(jellyfinNeedsAdministratorTitle), findsOneWidget);
      expect(find.textContaining('list users'), findsOneWidget);
      _expectNoFault();
      await harness.unmount(tester);
    });

    testWidgets('the Overview\'s Libraries says it needs an administrator, '
        'never a refusal', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const Scaffold(
          body: StreamOverviewScreen(service: ServiceKey.jellyfin),
        ),
      );

      final libraries = find.byWidgetPredicate(
        (widget) =>
            widget is ServiceOverviewSection && widget.title == 'Libraries',
      );
      expect(libraries, findsOneWidget);
      expect(
        find.descendant(
          of: libraries,
          matching: find.text(jellyfinNeedsAdministratorTitle),
        ),
        findsOneWidget,
      );
      _expectNoFault(libraries);
      await harness.unmount(tester);
    });

    testWidgets('the viewer picker offers the token\'s own person', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const Scaffold(
          body: JellyfinViewerPicker(instanceId: WorldIds.jellyfin),
        ),
      );

      expect(find.widgetWithText(ChoiceChip, WorldPeople.anna), findsOneWidget);
      expect(find.text('This server reports no users.'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('the Overview says the one Jellyfin shows only her playback', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const Scaffold(
          body: StreamOverviewScreen(service: ServiceKey.jellyfin),
        ),
      );

      expect(find.text(_ownPlayback), findsOneWidget);
      expect(
        find.text('Other people\'s sessions need an administrator to see.'),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });
  });
}
