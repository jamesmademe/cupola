import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The media server's own web client, deep-linked to item [itemId], or null
/// when there is no address to build one from: Plex needs its server's
/// [plexMachineId].
///
/// A web URL rather than an app scheme: neither Jellyfin nor Plex publishes a
/// documented, reliably-registered scheme across iOS, Android and macOS, and a
/// scheme that silently fails is worse than a browser that works. On a phone
/// the installed app usually claims the URL anyway through universal links.
Uri? streamItemWebUrl({
  required ServiceKey service,
  required String baseUrl,
  required String itemId,
  String? plexMachineId,
}) {
  final root = UrlUtils.normalizeBaseUrl(baseUrl);
  if (root.isEmpty) return null;
  if (service == ServiceKey.jellyfin) {
    return Uri.tryParse('$root/web/index.html#!/details?id=$itemId');
  }
  if (plexMachineId == null || plexMachineId.isEmpty) return null;
  final key = Uri.encodeComponent('/library/metadata/$itemId');
  return Uri.tryParse(
    '$root/web/index.html#!/server/$plexMachineId/details?key=$key',
  );
}
