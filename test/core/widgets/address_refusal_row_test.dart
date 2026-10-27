import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

/// qBittorrent's 401 at sign-in is the host check refusing the address, not a
/// wrong password: the row must say so and point at the server domains, never
/// at the sign-in.
void main() {
  testWidgets('a refused address reads as the address, not the sign-in', (
    tester,
  ) async {
    final overrides = await settingsScopeOverrides(
      configured: [ServiceKey.qbittorrent],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ServiceOfflineState.failure(
              service: ServiceKey.qbittorrent,
              error: const QbittorrentException(
                'qBittorrent refused this address (401).',
                reason: ServiceFailureReason.addressRefused,
                detail:
                    'If the password is right, add this address to Server '
                    'domains in qBittorrent\'s Web UI settings, or turn off Host '
                    'header validation there.',
              ),
              onRetry: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('qBittorrent answered but refused this address'),
      findsOneWidget,
    );
    expect(find.textContaining('Server domains'), findsOneWidget);
    expect(find.textContaining('refused the sign-in'), findsNothing);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Allow this address'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
