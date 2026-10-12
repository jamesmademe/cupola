/// An arr history record as a last drawing keeps it: every field, the times
/// as instants, the artwork as the plain addresses the record already holds
/// (an arr's history carries no credential in them: its key travels in a
/// header the drawing puts back).
library;

import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Map<String, Object?> arrHistoryEntryToJson(ArrHistoryEntry entry) => {
  'service': entry.service.name,
  'id': entry.id,
  'mediaId': entry.mediaId,
  'title': entry.title,
  'unitId': ?entry.unitId,
  'detail': ?entry.detail,
  'posterUrl': entry.posterUrl,
  'outcome': entry.outcome.name,
  'at': ?entry.at?.toUtc().toIso8601String(),
  'reason': ?entry.reason,
  'instanceId': entry.instanceId,
  'connectionName': ?entry.connectionName,
  'tmdbId': ?entry.tmdbId,
  'backdropUrl': entry.backdropUrl,
  'mediaAddedAt': ?entry.mediaAddedAt?.toUtc().toIso8601String(),
  'fileName': ?entry.fileName,
  'downloadId': ?entry.downloadId,
};

/// [json] read back; null for a record this version cannot read whole.
ArrHistoryEntry? arrHistoryEntryFromJson(Object? json) {
  if (json is! Map) return null;
  final service = ServiceKey.values.asNameMap()[json['service']];
  final outcome = ArrImportOutcome.values.asNameMap()[json['outcome']];
  final id = json['id'];
  final mediaId = json['mediaId'];
  final title = json['title'];
  if (service == null ||
      outcome == null ||
      id is! int ||
      mediaId is! int ||
      title is! String) {
    return null;
  }
  DateTime? instant(String key) => switch (json[key]) {
    final String raw => DateTime.tryParse(raw)?.toLocal(),
    _ => null,
  };
  String? text(String key) => switch (json[key]) {
    final String value => value,
    _ => null,
  };
  int? number(String key) => switch (json[key]) {
    final int value => value,
    _ => null,
  };
  return ArrHistoryEntry(
    service: service,
    id: id,
    mediaId: mediaId,
    title: title,
    unitId: number('unitId'),
    detail: text('detail'),
    posterUrl: text('posterUrl') ?? '',
    outcome: outcome,
    at: instant('at'),
    reason: text('reason'),
    instanceId: text('instanceId') ?? '',
    connectionName: text('connectionName'),
    tmdbId: number('tmdbId'),
    backdropUrl: text('backdropUrl') ?? '',
    mediaAddedAt: instant('mediaAddedAt'),
    fileName: text('fileName'),
    downloadId: text('downloadId'),
  );
}
