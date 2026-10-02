import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// An application Prowlarr syncs its indexers to, as `GET
/// /api/v1/applications` reports it: its name, its implementation, and the
/// two addresses in its fields.
///
/// Prowlarr knows where each arr is, as Prowlarr reaches it ([baseUrl]), and
/// never says with which key: every field of privacy `ApiKey` or `Password`
/// comes back as `********` (`PRIVATE_VALUE` in Prowlarr's
/// `ClientSchema/SchemaBuilder.cs`). So the key is absent here, not the mask:
/// there is no field for it, and an arr found through Prowlarr is set up with
/// a key the person adds.
///
/// Read from Prowlarr's `Applications/*/…Settings.cs` (`ProwlarrUrl` at 0,
/// `BaseUrl` at 1, `ApiKey` at 2 for Radarr, Sonarr, Lidarr and Readarr).
class ProwlarrKnownApplication {
  const ProwlarrKnownApplication({
    required this.id,
    required this.name,
    required this.implementation,
    this.baseUrl,
    this.prowlarrUrl,
  });

  factory ProwlarrKnownApplication.fromJson(Map<String, dynamic> json) {
    String? field(String name) {
      final fields = json['fields'];
      if (fields is! List) return null;
      for (final raw in fields) {
        final field = mapOrNull(raw);
        if (field != null && field['name'] == name) {
          final value = stringOrNull(field['value']);
          // A credential written into an address is a secret too, and this
          // one would print.
          return value == null ? null : UrlUtils.withoutCredentials(value);
        }
      }
      return null;
    }

    return ProwlarrKnownApplication(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']) ?? '',
      implementation: stringOrNull(json['implementation']) ?? '',
      baseUrl: field('baseUrl'),
      prowlarrUrl: field('prowlarrUrl'),
    );
  }

  /// Prowlarr's own id for the application.
  final int id;

  /// What the Prowlarr admin called it, e.g. `Radarr 4K`. May be empty.
  final String name;

  /// What it is, as Prowlarr names the implementation: `Radarr`, `Sonarr`,
  /// `Lidarr`, `Readarr`, `Whisparr`, `Mylar`, `LazyLibrarian`.
  final String implementation;

  /// The application's address as Prowlarr reaches it (the "Radarr Server"
  /// field, `baseUrl`): scheme, host, port and base path, as Prowlarr reports
  /// it. Often a container name this device cannot reach: see
  /// `proposeFoundAddress`. Null when the field is empty.
  final String? baseUrl;

  /// Prowlarr's own address as the application reaches it (the "Prowlarr
  /// Server" field, `prowlarrUrl`). Says how the stack names Prowlarr, never
  /// where this device reaches it. Null when the field is empty.
  final String? prowlarrUrl;

  /// The Cupola service [implementation] is, or null for one Cupola does not
  /// connect to (Whisparr, Mylar, LazyLibrarian).
  ServiceKey? get service => switch (implementation.toLowerCase()) {
    'radarr' => ServiceKey.radarr,
    'sonarr' => ServiceKey.sonarr,
    'lidarr' => ServiceKey.lidarr,
    'readarr' => ServiceKey.readarr,
    _ => null,
  };

  @override
  String toString() =>
      'ProwlarrKnownApplication($id, $implementation, "$name", '
      '${baseUrl ?? 'no address'})';
}
