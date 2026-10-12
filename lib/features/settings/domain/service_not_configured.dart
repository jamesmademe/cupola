import 'package:cupola/features/settings/domain/service_key.dart';

/// A provider was asked for [service] and there is no connection to use.
///
/// Thrown before any client is built, by every provider that needs a saved
/// connection, and recognised **by type** wherever a failure is drawn:
/// `AsyncValueWidget` and its peers answer it with `NotConfiguredPlaceholder`
/// ("Radarr is not set up", "Set up Radarr") instead of an error, because the
/// remedy is a form in Settings and no retry changes it. They used to match
/// the words of [toString], so a rewording of the throw, or a server error
/// that happened to contain the phrase, silently changed which page a person
/// saw; `test/features/settings/domain/service_not_configured_guard_test.dart`
/// keeps the match on the type.
///
/// [toString] keeps the old wording, `<Service> not configured`, for logs and
/// tests. It is a marker, never drawn.
class ServiceNotConfigured implements Exception {
  const ServiceNotConfigured(this.service);

  /// The service nobody has set up, which the placeholder names.
  final ServiceKey service;

  @override
  String toString() => '${service.title} not configured';
}
