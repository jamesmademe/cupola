/// A request that waits on the operator, as a last drawing keeps its row:
/// everything the row draws and its Approve and Decline need.
///
/// Only that kind is kept. A fault of yesterday is a false alarm today, so no
/// module draws one from a last drawing, and what only a fault carries (its
/// remedy, the transfer's keys, the faults a row folds) is not written: a
/// record of another kind is read as nothing.
///
/// **Who asked is kept by name and never by address.** The row says who asked
/// where the connection sees everyone's requests, and Seerr's own display name
/// falls back to the account's email when nobody chose one: a part of the
/// line that is an address is dropped, so the row says when and where, and the
/// name comes back with the live answer. The time is kept as an instant: the
/// row says it again (`2 h ago`) against the moment it is drawn.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/home/data/last_known/stored_fields.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';

final _address = RegExp(r'[^\s@]+@[^\s@]+');

/// [decision] as a record, or null for anything but a request that waits.
Map<String, Object?>? dashboardDecisionToJson(DashboardDecision decision) {
  if (decision.kind != DecisionKind.pendingRequest) return null;
  final detail = _detailWithoutAddresses(decision.detail);
  return {
    'kind': decision.kind.name,
    'id': decision.id,
    'service': decision.service.name,
    'title': decision.title,
    if (detail.isNotEmpty) 'detail': detail,
    'occurredAt': ?decision.occurredAt?.toUtc().toIso8601String(),
    'route': ?_keptPath(decision.route),
    'posterUrl': ?_keptPoster(decision.posterUrl),
    'actionId': ?decision.actionId,
    if (decision.count != 1) 'count': decision.count,
    if (decision.instanceId.isNotEmpty) 'instanceId': decision.instanceId,
    'connectionName': ?decision.connectionName,
    if (decision.actionInstanceId.isNotEmpty)
      'actionInstanceId': decision.actionInstanceId,
  };
}

/// [json] read back; null for a record this version cannot read whole, and
/// for one that is not a request that waits.
DashboardDecision? dashboardDecisionFromJson(Object? json) {
  final fields = StoredFields(json);
  final kind = fields.named(DecisionKind.values, 'kind', required: true);
  final id = fields.text('id', required: true);
  final service = fields.service('service', required: true);
  final title = fields.text('title');
  final detail = fields.text('detail');
  final occurredAt = fields.instant('occurredAt');
  final route = fields.text('route');
  final posterUrl = fields.text('posterUrl');
  final actionId = fields.whole('actionId');
  final count = fields.whole('count');
  final instanceId = fields.text('instanceId');
  final connectionName = fields.text('connectionName');
  final actionInstanceId = fields.text('actionInstanceId');
  if (fields.isBroken ||
      kind != DecisionKind.pendingRequest ||
      id == null ||
      service == null ||
      title == null) {
    return null;
  }
  return DashboardDecision(
    kind: DecisionKind.pendingRequest,
    id: id,
    service: service,
    title: title,
    detail: detail ?? '',
    occurredAt: occurredAt,
    route: route,
    posterUrl: posterUrl ?? '',
    actionId: actionId,
    count: count ?? 1,
    instanceId: instanceId ?? '',
    connectionName: connectionName,
    actionInstanceId: actionInstanceId ?? '',
  );
}

/// The row's line without the parts that are an email address.
String _detailWithoutAddresses(String detail) => splitParts(
  detail,
).where((part) => !_address.hasMatch(part)).join(dotSeparator).trim();

String? _keptPath(String? path) {
  if (path == null || path.isEmpty) return null;
  return StoredImage.carriesCredential(path) ? null : path;
}

String? _keptPoster(String url) =>
    StoredImage.ofSource((url: url, headers: null)) is StoredUrl ? url : null;
