import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Lifecycle state of a Dockge stack.
///
/// Mirrors the integer status constants used by the Dockge backend
/// (`common/util-common.ts`): `UNKNOWN=0`, `CREATED_FILE=1`,
/// `CREATED_STACK=2`, `RUNNING=3`, `EXITED=4`.
enum DockgeStackStatus {
  unknown(0, 'Unknown'),
  createdFile(1, 'Inactive'),
  createdStack(2, 'Inactive'),
  running(3, 'Running'),
  exited(4, 'Exited');

  const DockgeStackStatus(this.code, this.label);

  final int code;
  final String label;

  static DockgeStackStatus fromCode(int? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return DockgeStackStatus.unknown;
  }

  bool get isActive => this == DockgeStackStatus.running;

  /// How this state reads, resolved to a colour by the presentation layer.
  ///
  /// It used to be a `Color` built from four raw hexes — none of them a palette
  /// token, one of them an unregistered green sitting beside `AppColors.success`
  /// — which is the only reason this domain file imported `material.dart`. Two
  /// of the four were also wrong about what they were describing:
  ///
  ///  * **exited** was red. Red on this canvas means a connection that did not
  ///    answer, and Dockge answered: it told us the stack is down. That is a
  ///    fault, and a fault is amber.
  ///  * **inactive** was amber. A stack that was never started is not a fault —
  ///    nothing stopped, nothing failed. A container stopped on purpose is
  ///    neutral, and so is one that has not been started yet.
  StatusTone get tone => switch (this) {
    DockgeStackStatus.running => StatusTone.success,
    DockgeStackStatus.exited => StatusTone.warning,
    DockgeStackStatus.createdFile ||
    DockgeStackStatus.createdStack ||
    DockgeStackStatus.unknown => StatusTone.neutral,
  };
}

/// A Docker Compose stack as summarised by Dockge's `stackList` push event.
///
/// Corresponds to `Stack.toSimpleJSON()` on the backend.
@immutable
class DockgeStack {
  final String name;
  final DockgeStackStatus status;
  final List<String> tags;
  final bool isManagedByDockge;
  final String? composeFileName;

  /// The Dockge endpoint (agent) this stack belongs to. Empty string for a
  /// direct (single-instance) connection.
  final String endpoint;

  const DockgeStack({
    required this.name,
    required this.status,
    this.tags = const [],
    this.isManagedByDockge = true,
    this.composeFileName,
    this.endpoint = '',
  });

  factory DockgeStack.fromJson(Map<String, dynamic> json) {
    return DockgeStack(
      name: stringOrNull(json['name']) ?? '',
      status: DockgeStackStatus.fromCode(intOrNull(json['status'])),
      tags: _parseTags(json['tags']),
      isManagedByDockge: json['isManagedByDockge'] == true,
      composeFileName: stringOrNull(json['composeFileName']),
      endpoint: stringOrNull(json['endpoint']) ?? '',
    );
  }

  DockgeStack copyWith({
    String? name,
    DockgeStackStatus? status,
    List<String>? tags,
    bool? isManagedByDockge,
    String? composeFileName,
    String? endpoint,
  }) {
    return DockgeStack(
      name: name ?? this.name,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      isManagedByDockge: isManagedByDockge ?? this.isManagedByDockge,
      composeFileName: composeFileName ?? this.composeFileName,
      endpoint: endpoint ?? this.endpoint,
    );
  }

  static List<String> _parseTags(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }
}
