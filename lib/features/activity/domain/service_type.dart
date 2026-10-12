import 'package:cupola/features/settings/domain/service_key.dart';

enum ServiceType { movies, series, music, discover }

/// Human-readable display titles for [ServiceType].
extension ServiceTypeDisplay on ServiceType {
  String get displayTitle {
    switch (this) {
      case ServiceType.movies:
        return 'Movies';
      case ServiceType.series:
        return 'Series';
      case ServiceType.music:
        return 'Music';
      case ServiceType.discover:
        return 'Requests';
    }
  }

  bool get supportsArrActivity => this != ServiceType.discover;

  /// The service this content axis is actually read from.
  ///
  /// Activity is grouped by *what* rather than by *which server*, which is why
  /// two Radarr fall into one Movies tab on their own. That is the right
  /// grouping, but it means the screen cannot say which connection it is
  /// showing unless it can name one, and this is the name.
  ServiceKey get service => switch (this) {
    ServiceType.movies => ServiceKey.radarr,
    ServiceType.series => ServiceKey.sonarr,
    ServiceType.music => ServiceKey.lidarr,
    ServiceType.discover => ServiceKey.seerr,
  };
}
