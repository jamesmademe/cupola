import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_actions.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_actions.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_actions.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/presentation/transmission_actions.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

class _FakeDockge extends Fake implements DockgeClient {}

class _FakeNpm extends Fake implements NpmClient {}

class _FakeNzbget extends Fake implements NzbgetClient {}

class _FakeQbittorrent extends Fake implements QbittorrentService {}

class _FakeSabnzbd extends Fake implements SabnzbdClient {}

class _FakeTransmission extends Fake implements TransmissionClient {}

typedef _Run =
    Future<bool> Function(
      BuildContext context,
      WidgetRef ref,
      Future<void> Function() body,
      ProviderOrFamily stale,
    );

/// One of the six wrappers every action button goes through, and what it needs
/// to run without a server.
typedef _Wrapper = ({
  List<Override> overrides,
  _Run run,

  /// Whether the wrapper says how it went once the page is gone: all six do.
  bool says,

  /// Whether a command that threw still has its providers read again: all six
  /// do (a refused write usually means the list moved under the person).
  bool rereadsOnFailure,
});

final _wrappers = <String, _Wrapper>{
  'Dockge': (
    overrides: [
      dockgeLensedClientProvider.overrideWith((ref) => _FakeDockge()),
    ],
    run: (context, ref, body, stale) => runDockgeAction(
      context,
      ref,
      action: (_) => body(),
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
  'NPM': (
    overrides: [npmClientProvider.overrideWith((ref) => _FakeNpm())],
    run: (context, ref, body, stale) => runNpmAction(
      context,
      ref,
      resource: NpmResource.certificates,
      action: (_) => body(),
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
  'qBittorrent': (
    overrides: [
      qbittorrentServiceProvider.overrideWith((ref) => _FakeQbittorrent()),
    ],
    run: (context, ref, body, stale) => runTorrentAction(
      context,
      ref,
      action: (_) => body(),
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
  'SABnzbd': (
    overrides: [sabnzbdClientProvider.overrideWith((ref) => _FakeSabnzbd())],
    run: (context, ref, body, stale) => runSabnzbdAction(
      context,
      ref,
      action: (_) => body(),
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
  'NZBGet': (
    overrides: [nzbgetClientProvider.overrideWith((ref) => _FakeNzbget())],
    run: (context, ref, body, stale) => runNzbgetAction(
      context,
      ref,
      action: (_) async {
        await body();
        return null;
      },
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
  'Transmission': (
    overrides: [
      transmissionClientProvider.overrideWith((ref) => _FakeTransmission()),
    ],
    run: (context, ref, body, stale) => runTransmissionAction(
      context,
      ref,
      action: (_) => body(),
      successMessage: 'Finished',
      failureMessage: 'Could not finish',
      invalidate: [stale],
    ),
    says: true,
    rereadsOnFailure: true,
  ),
};

void main() {
  for (final MapEntry(key: name, value: wrapper) in _wrappers.entries) {
    for (final fails in [false, true]) {
      testWidgets(
        '$name: ${fails ? 'a failure' : 'a success'} that lands after the page '
        'is gone is not an error',
        (tester) async {
          var reads = 0;
          final stale = FutureProvider<int>((ref) async => ++reads);
          final finish = Completer<void>();
          Future<bool>? outcome;

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentSettingsProvider.overrideWith(
                  (ref) => const SettingsModel(),
                ),
                ...wrapper.overrides,
              ],
              child: MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    // Kept alive by the page underneath, as a list or an
                    // Overview keeps what its actions invalidate.
                    ref.watch(stale);
                    return Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Consumer(
                              builder: (context, ref, _) => TextButton(
                                onPressed: () => outcome = wrapper.run(
                                  context,
                                  ref,
                                  () => finish.future,
                                  stale,
                                ),
                                child: const Text('Run'),
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(reads, 1);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Run'));
          await tester.pump();

          // The person leaves while the server is still working.
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();
          expect(find.text('Run'), findsNothing);

          if (fails) {
            finish.completeError(Exception('refused'));
          } else {
            finish.complete();
          }
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(await outcome, !fails);
          expect(
            reads,
            fails && !wrapper.rereadsOnFailure ? 1 : 2,
            reason: 'what the action changed was read again',
          );
          expect(
            find.text(fails ? 'Could not finish\nrefused' : 'Finished'),
            wrapper.says ? findsOneWidget : findsNothing,
          );
        },
      );
    }
  }
}
