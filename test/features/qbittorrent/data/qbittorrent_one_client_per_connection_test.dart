/// One qBittorrent client per connection, whoever asks, so a wrong password is
/// sent once and not on every refresh.
///
/// qBittorrent bans an address after five failed sign-ins (for an hour by
/// default), and behind a reverse proxy the address is everybody's. The
/// Dashboard's probe and the Settings readouts each built a client of their
/// own per run, so every pull, every "Test all" and every settings write that
/// re-ran a readout sent the wrong password again. These count the sign-ins
/// the server saw.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_test_command.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _loginPath = '/api/v2/auth/login';

/// P1 with qBittorrent refusing the password (`200 Fails.`).
final _wrongPassword = Profiles.p1.withBehaviour(
  WorldIds.qbittorrent,
  ConnectionBehaviour.refusesKey,
);

const InstanceRef _qb = (
  service: ServiceKey.qbittorrent,
  instanceId: WorldIds.qbittorrent,
);

int _signIns(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.qbittorrent)
    .where((request) => request.path == _loginPath)
    .length;

Future<ServiceSummary> _probe(ProviderContainer container) =>
    container.read(instanceSummaryProvider(_qb).future);

void main() {
  test(
    'the Dashboard probe signs in once, however often it is refreshed',
    () async {
      final harness = await ProfileHarness.start(_wrongPassword);
      final container = harness.container();

      final first = await _probe(container);
      expect(first.isFault, isTrue);
      expect(first.failureReason, ServiceFailureReason.unauthorized);

      for (var pull = 0; pull < 6; pull++) {
        container.invalidate(instanceSummaryProvider);
        container.invalidate(serviceSummaryProvider(ServiceKey.qbittorrent));
        final again = await _probe(container);
        // Still a refused sign-in, read from the hold rather than asked again.
        expect(again.failureReason, ServiceFailureReason.unauthorized);
      }

      expect(_signIns(harness), 1);
    },
  );

  test(
    'the Settings readouts share the sign-in, through tests and settings writes',
    () async {
      final harness = await ProfileHarness.start(_wrongPassword);
      final container = harness.container();

      await _probe(container);
      for (var run = 0; run < 3; run++) {
        final row = await container.read(
          serviceDiagnosisProvider(ServiceKey.qbittorrent).future,
        );
        final form = await container.read(
          instanceDiagnosisProvider(WorldIds.qbittorrent).future,
        );
        expect(row.reason, ServiceFailureReason.unauthorized);
        expect(form.reason, ServiceFailureReason.unauthorized);
        container.invalidate(serviceDiagnosisProvider);
        container.invalidate(instanceDiagnosisProvider);
      }

      // A write that has nothing to do with qBittorrent re-runs both readouts,
      // which watch the whole model. It must not reach the WebUI's login.
      final settings = container.read(currentSettingsProvider);
      await container
          .read(settingsProvider.notifier)
          .updateSettings(settings.copyWith(themeMode: AppThemeMode.light));
      final afterWrite = await container.read(
        serviceDiagnosisProvider(ServiceKey.qbittorrent).future,
      );
      expect(afterWrite.reason, ServiceFailureReason.unauthorized);

      expect(_signIns(harness), 1);
    },
  );

  test(
    'the qBittorrent pages and Home read the refusal the probe met',
    () async {
      final harness = await ProfileHarness.start(_wrongPassword);
      final container = harness.container();

      await _probe(container);

      for (final read in [
        () => container.read(qbittorrentServiceProvider).getTorrents(),
        () => container
            .read(qbittorrentServiceForProvider(WorldIds.qbittorrent))
            .getTorrents(),
      ]) {
        try {
          await read();
          fail('expected the held refusal');
        } on QbittorrentException catch (error) {
          expect(error.reason, ServiceFailureReason.unauthorized);
        }
      }

      expect(
        identical(
          container.read(qbittorrentClientForProvider('')),
          container.read(qbittorrentClientForProvider(WorldIds.qbittorrent)),
        ),
        isTrue,
        reason: 'the lens and the connection name the same client',
      );
      expect(_signIns(harness), 1);
    },
  );

  test('an answering qBittorrent keeps its session across refreshes', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container();

    expect((await _probe(container)).isOnline, isTrue);
    await container.read(qbittorrentServiceProvider).getTorrents();
    for (var pull = 0; pull < 3; pull++) {
      container.invalidate(instanceSummaryProvider);
      expect((await _probe(container)).isOnline, isTrue);
    }

    expect(_signIns(harness), 1);
  });

  group('a person asking again sends the sign-in once', () {
    Future<(ProfileHarness, WidgetRef)> pump(WidgetTester tester) async {
      final harness = await ProfileHarness.start(_wrongPassword);
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return (harness, captured);
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(SizedBox)));

    testWidgets('the Dashboard Retry beside the failure', (tester) async {
      final (harness, ref) = await pump(tester);
      final container = containerOf(tester);

      await tester.runAsync(() async {
        await _probe(container);
        expect(_signIns(harness), 1);

        retryDashboardServices(ref, {ServiceKey.qbittorrent});
        final retried = await _probe(container);
        expect(retried.failureReason, ServiceFailureReason.unauthorized);
        expect(_signIns(harness), 2);

        // A refresh after it is a refresh again: the new refusal holds.
        container.invalidate(instanceSummaryProvider);
        await _probe(container);
        expect(_signIns(harness), 2);
      });
    });

    testWidgets('Test all in Settings', (tester) async {
      final (harness, ref) = await pump(tester);
      final container = containerOf(tester);

      await tester.runAsync(() async {
        await container.read(
          serviceDiagnosisProvider(ServiceKey.qbittorrent).future,
        );
        expect(_signIns(harness), 1);

        testAllConnections(ref);
        final tested = await container.read(
          serviceDiagnosisProvider(ServiceKey.qbittorrent).future,
        );
        expect(tested.reason, ServiceFailureReason.unauthorized);
        expect(_signIns(harness), 2);
      });
    });

    testWidgets('a Retry on a qBittorrent page', (tester) async {
      final (harness, ref) = await pump(tester);
      final container = containerOf(tester);

      await tester.runAsync(() async {
        await _probe(container);
        clearQbittorrentLoginRefusal(ref);
        container.invalidate(instanceSummaryProvider);
        await _probe(container);
        expect(_signIns(harness), 2);
      });
    });
  });

  group('a passing Test in the connection form', () {
    // The form tests with a client of its own. It read `Answering` while the
    // Dashboard kept its client's refusal until a Retry somewhere else.
    Future<(ProfileHarness, ProviderContainer, void Function())> pumpForm(
      WidgetTester tester, {
      String password = '',
    }) async {
      var fixed = false;
      final profile = Profiles.p1;
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: ServiceSettingsScreen(
          service: ServiceKey.qbittorrent,
          instanceId: WorldIds.qbittorrent,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
        surfaceSize: const Size(430, 2400),
        settle: false,
      );
      // The password is wrong at the server until the person fixes it there.
      harness.network.on(
        WorldIds.qbittorrent,
        'POST',
        _loginPath,
        (_) => fixed ? null : NetworkReply.text('Fails.'),
      );
      await harness.settle(tester);
      if (password.isNotEmpty) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          password,
        );
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServiceSettingsScreen)),
      );
      return (harness, container, () => fixed = true);
    }

    testWidgets('with the saved sign-in lets the Dashboard sign in again', (
      tester,
    ) async {
      final (harness, container, fixAtServer) = await pumpForm(tester);

      await tester.runAsync(() async {
        expect((await _probe(container)).isFault, isTrue);
      });
      final refused = _signIns(harness);
      fixAtServer();
      await tester.runAsync(() async {
        container.invalidate(instanceSummaryProvider);
        expect((await _probe(container)).isFault, isTrue);
      });
      expect(_signIns(harness), refused, reason: 'a refresh is held');

      await tester.tap(find.text('Test connection'));
      await harness.settle(tester);
      expect(_signIns(harness), refused + 1, reason: "the form's own test");

      await tester.runAsync(() async {
        container.invalidate(instanceSummaryProvider);
        expect((await _probe(container)).isOnline, isTrue);
      });
      expect(_signIns(harness), refused + 2);

      await harness.unmount(tester);
    });

    testWidgets('with values not saved leaves the saved hold alone', (
      tester,
    ) async {
      final (harness, container, fixAtServer) = await pumpForm(
        tester,
        password: 'typed-not-saved',
      );
      await tester.runAsync(() async => _probe(container));
      fixAtServer();

      await tester.tap(find.text('Test connection'));
      await harness.settle(tester);
      final afterTest = _signIns(harness);

      await tester.runAsync(() async {
        container.invalidate(instanceSummaryProvider);
        expect((await _probe(container)).isFault, isTrue);
      });
      expect(_signIns(harness), afterTest);

      await harness.unmount(tester);
    });
  });
}
