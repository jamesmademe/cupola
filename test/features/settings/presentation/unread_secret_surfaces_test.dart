/// A connection whose secret this device would not hand over says so where it
/// is drawn: the screen that stands on it, Needs you, the words of the
/// classification; never `Set up Radarr`, never `did not answer`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/unread_secret.dart';

import '../../../test_helpers/settings_scope.dart';

SettingsModel _unread(SettingsModel settings, ServiceKey key) {
  final instance = settings
      .instancesOf(key)
      .single
      .copyWith(credential: '')
      .withUnreadSecret(UnreadSecret.credential);
  return settings.copyWithInstance(instance);
}

void main() {
  test('the classification says what happened on the device', () {
    const reason = ServiceFailureReason.secretUnread;
    expect(
      failureHeadline(reason, subject: 'Radarr'),
      "Cupola could not read Radarr's saved key",
    );
    expect(
      failureHeadline(
        reason,
        subject: 'qBittorrent',
        credential: kRefusedSignIn,
      ),
      "Cupola could not read qBittorrent's saved password",
    );
    expect(failureLabel(reason), 'Saved key unreadable');
    expect(failureRemedy(reason), 'Paste the key again');
    expect(failureRemedy(reason, credential: kRefusedSignIn), 'Sign in again');
    expect(failureRetryHelps(reason), isFalse);
    expect(failureIsFault(reason), isTrue);
    expect(failureDidNotAnswer(reason), isFalse);
  });

  test('the words name the platform\'s store', () {
    final instance = const ServiceInstance(
      id: 'plex',
      service: ServiceKey.plex,
      url: 'https://plex.test',
    ).withUnreadSecret(UnreadSecret.credential);
    final words = UnreadSecretWords.of(
      instance,
      platform: TargetPlatform.android,
    );
    expect(words.headline, "Cupola could not read Plex's saved token");
    expect(words.sentence, "Android's secure storage didn't hand it over.");
    expect(words.remedy, 'Paste the token again');
  });

  testWidgets('the screen standing on it leads to pasting it again', (
    tester,
  ) async {
    final overrides = await settingsScopeOverrides(
      configured: [ServiceKey.radarr],
      customize: (s) => _unread(s, ServiceKey.radarr),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: NotConfiguredPlaceholder.forService(ServiceKey.radarr),
          ),
        ),
      ),
    );

    expect(
      find.text("Cupola could not read Radarr's saved key"),
      findsOneWidget,
    );
    expect(find.text('Paste the key again'), findsOneWidget);
    expect(find.text('Set up Radarr'), findsNothing);
  });

  test('Needs you holds it, with the remedy to its form', () {
    final instance = const ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://radarr.test',
    ).withUnreadSecret(UnreadSecret.credential);

    final decision = unreadSecretDecision(instance, null);

    expect(decision.kind, DecisionKind.connectionFault);
    expect(decision.title, "Cupola could not read Radarr's saved key");
    expect(decision.remedy, 'Paste the key again');
    expect(decision.route, contains('radarr'));
  });
}
