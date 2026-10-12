/// A download row as a last drawing keeps it: the title, how far it got, the
/// release under it and what a tap needs to open its page.
///
/// What is **not** kept, on purpose: whatever runs (the time left, the
/// transfer rate, a stall's clock), the fault and its remedy (a download that
/// was stuck is drawn as the download it was, and a fault is judged by the
/// live read and by nothing older), and every field the row does not draw (the
/// client's folder, the warning, the route). The picture is a `StoredImage`,
/// never an address with a key in it.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The row as JSON.
Map<String, Object?> serviceQueueItemToJson(ServiceQueueItem item) {
  final progress = item.progress;
  final poster = item.posterUrl;
  return {
    'service': item.service.name,
    'id': item.id,
    'downloadId': ?_text(item.downloadId),
    'title': item.title,
    'instanceId': item.instanceId,
    'connectionName': ?_text(item.connectionName),
    'clientService': ?item.clientService?.name,
    'progress': ?(progress != null && progress.isFinite ? progress : null),
    'poster': ?(poster == null || poster.isEmpty
        ? null
        : StoredImage.ofSource((url: poster, headers: null))?.toJson()),
    'release': ?_release(item),
  };
}

/// [json] read back, its picture resolved by [image] against the connections
/// as they are now; null for a row this version cannot read whole.
///
/// The row comes back with no fault, no time left and no rate: a drawing is
/// a download as it was last seen going, never one that is moving or stuck
/// now.
ServiceQueueItem? serviceQueueItemFromJson(
  Object? json,
  StoredImageResolver image,
) {
  if (json is! Map) return null;
  final service = ServiceKey.values.asNameMap()[json['service']];
  final id = json['id'];
  final title = json['title'];
  if (service == null || id is! String || title is! String) return null;
  final progress = switch (json['progress']) {
    final num value when value.isFinite => value.toDouble().clamp(0.0, 1.0),
    _ => null,
  };
  final posterAddress = StoredImage.fromJson(json['poster']);
  final poster = posterAddress == null ? '' : image(posterAddress).url;
  final release = _text(json['release']);
  return ServiceQueueItem(
    service: service,
    id: id,
    title: title,
    progress: progress,
    // Not drawn by the row: the client's name in words is the live read's.
    clientLabel: '',
    downloadId: _text(json['downloadId']),
    instanceId: _text(json['instanceId']) ?? '',
    connectionName: _text(json['connectionName']),
    clientService: ServiceKey.values.asNameMap()[json['clientService']],
    posterUrl: poster.isEmpty ? null : poster,
    names: release == null
        ? null
        : MediaNames(
            title: title,
            machineName: release,
            machineKind: MachineNameKind.release,
          ),
  );
}

String? _text(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text,
  _ => null,
};

/// The release the row draws under its title, when it draws one: the name a
/// download client or an arr gave it, never a place on a disk.
String? _release(ServiceQueueItem item) {
  final release = _text(item.names.machineName);
  if (release == null || release == item.title) return null;
  if (_looksLikePath(release)) return null;
  return release;
}

/// A folder or a drive, in either system's spelling.
bool _looksLikePath(String text) =>
    text.contains('/') ||
    text.contains(r'\') ||
    RegExp('^[A-Za-z]:').hasMatch(text);
