import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;

/// The platform's secure storage, by the name a person knows it by.
String secureStoreName([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'The Keychain',
      TargetPlatform.android => "Android's secure storage",
      TargetPlatform.windows => 'Windows Credential Manager',
      _ => 'The system keyring',
    };

/// What a connection whose secret could not be read says, wherever it is
/// drawn: the screen that stands on it, its fault in Needs you.
///
/// Said as what happened on this device, never as a refusal: nothing was
/// sent, because a connection with a secret missing is not used
/// ([ServiceInstance.isConfigured]). The remedy is the one a refused secret
/// has (`Paste the key again`, `Sign in again`), and it opens that
/// connection's form.
@immutable
class UnreadSecretWords {
  const UnreadSecretWords._({
    required this.headline,
    required this.sentence,
    required this.remedy,
    required this.route,
  });

  factory UnreadSecretWords.of(
    ServiceInstance instance, {
    String? connectionName,
    TargetPlatform? platform,
  }) {
    final service = instance.service;
    final subject = serviceWithConnection(service, connectionName, joiner: ' ');
    final secret = instance.unreadSecret ?? UnreadSecret.credential;
    final credential = refusedCredentialOf(service);
    const reason = ServiceFailureReason.secretUnread;
    return UnreadSecretWords._(
      headline: switch (secret) {
        UnreadSecret.access => "Cupola could not read $subject's saved access",
        UnreadSecret.credential => failureHeadline(
          reason,
          subject: subject,
          credential: credential,
        ),
      },
      sentence: "${secureStoreName(platform)} didn't hand it over.",
      remedy: switch (secret) {
        UnreadSecret.access => 'Add access again',
        UnreadSecret.credential => failureRemedy(
          reason,
          credential: credential,
        )!,
      },
      route: ServiceRoutes.settingsForConnection(
        service,
        instance.id,
        access: secret == UnreadSecret.access ? instance.access.kind : null,
      ),
    );
  }

  /// `Cupola could not read Radarr's saved key`.
  final String headline;

  /// `The Keychain didn't hand it over.`
  final String sentence;

  /// `Paste the key again`, `Sign in again`, `Paste the token again`,
  /// `Add access again`.
  final String remedy;

  /// The connection's form, on its access row for an access secret.
  final String route;
}
