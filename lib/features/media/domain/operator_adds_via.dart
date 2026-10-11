/// How the operator adds a title that no Radarr or Sonarr holds.
///
/// Through Seerr, the request keeps its history and its notifications, and
/// Seerr hands it on to the arr once it is approved. Straight to the arr, the
/// title is added with no request in Seerr. One choice per device; the default
/// is through Seerr.
enum OperatorAddsVia {
  seerr('Through Seerr'),
  arr('Straight to Radarr and Sonarr');

  const OperatorAddsVia(this.label);

  /// The name of the choice on Seerr's connection page.
  final String label;
}
