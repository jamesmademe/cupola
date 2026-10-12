import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A Dockge instance reachable through the one this app is logged in to.
///
/// Dockge's multi-agent model is a hub: you connect to one instance, and it
/// relays every command to its agents through an `agent` envelope
/// (`emit("agent", endpoint, event, …)`) keyed by the agent's endpoint. The
/// local instance is the empty endpoint, which is why the client hardwired
/// `_endpoint` to `''` and could only ever see one Dockge, while
/// [DockgeStack.endpoint] was parsed off every row and read by nothing.
@immutable
class DockgeAgent {
  /// `host:port` for a remote agent; the empty string for the instance this app
  /// is logged in to. It is the routing key, not a display name.
  final String endpoint;

  /// What Dockge calls this agent, falling back to the endpoint itself.
  final String name;

  /// Dockge's own word for the connection: `online`, `offline`, `connecting`.
  final String status;

  const DockgeAgent({
    required this.endpoint,
    required this.name,
    this.status = 'online',
  });

  /// The hub itself: always present, never removable, and the one agent that
  /// exists whether or not Dockge has the multi-agent feature enabled.
  static const local = DockgeAgent(endpoint: '', name: 'local');

  bool get isLocal => endpoint.isEmpty;

  /// An agent that is not answering is the one red in this feature: red means a
  /// connection that did not answer, and this is that, exactly. `connecting` is
  /// informational rather than a fault: it has not failed yet.
  StatusTone get tone => switch (status.toLowerCase()) {
    'online' => StatusTone.success,
    'connecting' => StatusTone.info,
    'offline' => StatusTone.error,
    _ => StatusTone.neutral,
  };

  factory DockgeAgent.fromJson(Map<String, dynamic> json) {
    final endpoint = stringOrNull(json['endpoint']) ?? '';
    final url = stringOrNull(json['url']);
    return DockgeAgent(
      endpoint: endpoint,
      // Dockge does not always carry a friendly name, so the endpoint is the
      // name; an agent with neither is the local one and says so.
      name:
          stringOrNull(json['name']) ??
          (endpoint.isNotEmpty ? endpoint : (url ?? 'local')),
      status: stringOrNull(json['status']) ?? 'online',
    );
  }

  DockgeAgent copyWith({String? status}) => DockgeAgent(
    endpoint: endpoint,
    name: name,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      other is DockgeAgent &&
      other.endpoint == endpoint &&
      other.name == name &&
      other.status == status;

  @override
  int get hashCode => Object.hash(endpoint, name, status);
}
