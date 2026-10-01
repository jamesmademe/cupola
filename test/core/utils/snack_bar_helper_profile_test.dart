import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The write toast's plate, from a real write through the app's own
/// qBittorrent client: the tone comes out of the classification of what the
/// wire said, never out of the toast deciding for itself.
void main() {
  Future<Color?> plateAfterPause(
    WidgetTester tester,
    ConfigProfile profile,
  ) async {
    final harness = await ProfileHarness.start(profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => runTorrentAction(
                  context,
                  ref,
                  action: (qb) => qb.pauseTorrents(const ['abc']),
                  failureMessage: "Couldn't stop this torrent.",
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await harness.settle(tester);
    final plate = tester
        .widget<SnackBar>(find.byType(SnackBar))
        .backgroundColor;
    await harness.unmount(tester);
    return plate;
  }

  final scheme = AppTheme.darkTheme().colorScheme;

  testWidgets('P7: qBittorrent refused the sign-in, so the toast is amber', (
    tester,
  ) async {
    expect(
      await plateAfterPause(tester, Profiles.p7),
      statusToneFill(scheme, StatusTone.warning),
    );
  });

  testWidgets('P1, qBittorrent did not answer: the one red toast', (
    tester,
  ) async {
    expect(
      await plateAfterPause(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.qbittorrent,
          ConnectionBehaviour.didNotAnswer,
        ),
      ),
      statusToneFill(scheme, StatusTone.error),
    );
  });
}
