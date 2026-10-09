/// The words of a download on Activity: which way its bytes travel, how long
/// nothing has arrived, when a waiting one starts.
library;

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;

/// Who asked and who moves the bytes: `Radarr → qBittorrent`, `Radarr 4K →
/// SABnzbd`; the client alone on a transfer no arr asked for.
String downloadRoute(ServiceQueueItem item) {
  final client = item.clientService;
  if (client == null || client == item.service) {
    return item.clientLabel.isEmpty ? item.service.title : item.clientLabel;
  }
  final arr = serviceWithConnection(
    item.service,
    item.connectionName,
    joiner: ' ',
  );
  return '$arr → ${item.clientLabel}';
}

/// How long nothing has arrived, as the stuck row's proof says it: `nothing
/// for 3 h`, `nothing for 40 min`, `nothing for 2 days`. Null when the
/// client did not date it.
String? nothingForWords(DateTime? since, {required DateTime now}) {
  if (since == null) return null;
  final idle = now.difference(since);
  if (idle.isNegative) return null;
  final words = switch (idle) {
    _ when idle.inDays >= 2 => '${idle.inDays} days',
    _ when idle.inHours >= 1 => '${idle.inHours} h',
    _ => '${idle.inMinutes} min',
  };
  return 'nothing for $words';
}
