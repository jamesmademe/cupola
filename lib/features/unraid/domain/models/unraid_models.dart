/// Typed models for the Unraid GraphQL API.
///
/// Unraid's GraphQL schema evolves between releases, so field access is
/// deliberately tolerant: missing fields degrade to sensible defaults rather
/// than throwing. Confirm exact field names against the target instance's
/// schema (SDL / Apollo sandbox) before relying on any one of them.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// System information (`info`).
class UnraidInfo {
  const UnraidInfo({required this.distro, required this.version, this.uptime});

  final String distro;

  /// Unraid release string, surfaced as the service version.
  final String version;

  final String? uptime;

  factory UnraidInfo.fromJson(Map<String, dynamic> json) {
    final os = (json['os'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UnraidInfo(
      distro: (os['distro'] ?? 'Unraid').toString(),
      version: (os['release'] ?? '').toString(),
      uptime: os['uptime']?.toString(),
    );
  }
}

/// Storage array status (`array`).
class UnraidArray {
  const UnraidArray({
    required this.state,
    required this.usedFraction,
    required this.disks,
  });

  final String state;

  /// Fraction of total capacity used (0..1), or null when unknown.
  final double? usedFraction;

  final List<UnraidDisk> disks;

  int get usedPercent => ((usedFraction ?? 0) * 100).round();

  factory UnraidArray.fromJson(Map<String, dynamic> json) {
    double? usedFraction;
    final capacity = (json['capacity'] as Map?)?.cast<String, dynamic>();
    final bucket =
        (capacity?['kilobytes'] as Map?)?.cast<String, dynamic>() ??
        (capacity?['bytes'] as Map?)?.cast<String, dynamic>();
    if (bucket != null) {
      final total = doubleOrNull(bucket['total']) ?? 0.0;
      final used = doubleOrNull(bucket['used']) ?? 0.0;
      if (total > 0) usedFraction = (used / total).clamp(0, 1).toDouble();
    }
    final disks = (json['disks'] as List?) ?? const [];
    return UnraidArray(
      state: (json['state'] ?? 'UNKNOWN').toString(),
      usedFraction: usedFraction,
      disks: disks
          .whereType<Map>()
          .map((e) => UnraidDisk.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// A single array disk.
class UnraidDisk {
  const UnraidDisk({
    required this.name,
    required this.status,
    required this.temp,
  });

  final String name;
  final String status;

  /// Null when Unraid reported no temperature for this slot.
  final int? temp;

  /// Unraid's own default warning threshold, and the one the array board
  /// prints ("above the 45 °C warning threshold"). A drive at 47 °C is a fault
  /// the user can still act on, so it is amber; nothing here is ever red,
  /// because red on this canvas means the host did not answer at all.
  static const int warmThresholdCelsius = 45;

  /// A drive Unraid is not reading a temperature from is a drive that is
  /// **spun down**, not a drive at 0 °C. The whole reason this is a getter and
  /// not a `?? 0` at the call site: a figure nobody could take must never be
  /// printed as a number, least of all as the one number that would read as
  /// "ice cold".
  bool get spunDown => temp == null;

  bool get warm => (temp ?? 0) >= warmThresholdCelsius;

  /// Unraid reports slot health as `DISK_OK`, `DISK_NEW`, `DISK_NP` (no disk
  /// in the slot), `DISK_INVALID`, `DISK_DSBL` (disabled — the array is running
  /// without it) and a handful of `DISK_*` siblings. Only the first two are
  /// "nothing to do here"; everything else is the array telling us something is
  /// wrong with a slot it expected to use, which is a fault and therefore
  /// amber. An empty status is not a verdict, so it stays neutral rather than
  /// being guessed into one.
  StatusTone get tone {
    final value = status.trim().toUpperCase();
    if (value.isEmpty || value == 'DISK_OK' || value == 'DISK_NEW') {
      return warm ? StatusTone.warning : StatusTone.neutral;
    }
    return StatusTone.warning;
  }

  factory UnraidDisk.fromJson(Map<String, dynamic> json) {
    return UnraidDisk(
      name: (json['name'] ?? 'disk').toString(),
      status: (json['status'] ?? '').toString(),
      temp: intOrNull(json['temp']),
    );
  }
}

/// What a container's Docker status line actually says, once it is read rather
/// than skimmed.
///
/// The screen used to have exactly two states — `running` and everything else,
/// painted in the dim foreground — which collapsed three different facts into
/// one row: a container the user stopped yesterday, a container the kernel
/// OOM-killed an hour ago, and a container whose healthcheck is failing while
/// it is still up. Decision 15 needs them told apart, and they can be: Docker's
/// `Status` string carries the exit code and the health verdict, so this is
/// read out of the payload rather than guessed from the state enum.
enum UnraidContainerCondition {
  running,
  unhealthy,
  paused,

  /// Exited cleanly (code 0) — someone stopped it, and that is not damage.
  stopped,

  /// Exited with a non-zero code. `Exited (137)` is the OOM kill; 143 is a
  /// SIGTERM that the process did not handle in time.
  exitedUnexpectedly,

  /// In the restart policy's backoff. Docker only ever reports this after an
  /// exit, so a container sitting here is a container that keeps dying.
  restarting,

  /// Docker could not remove the container's filesystem — it is neither
  /// running nor cleanly stopped.
  dead,

  /// Created but never started.
  created,

  /// The status string was not one this parser recognises. Neutral on purpose:
  /// a shape we cannot read is not evidence of a fault.
  unknown;

  /// Decision 15's five arms, for one row.
  ///
  /// Green only for a container that is up and whose healthcheck (if it has
  /// one) agrees. Amber for the faults. Neutral for every deliberate state —
  /// stopped, paused, never started. Red appears nowhere here: red belongs to
  /// an Unraid that did not answer, and an answer saying "this container is
  /// down" is the opposite of silence.
  StatusTone get tone => switch (this) {
    UnraidContainerCondition.running => StatusTone.success,
    UnraidContainerCondition.unhealthy ||
    UnraidContainerCondition.exitedUnexpectedly ||
    UnraidContainerCondition.restarting ||
    UnraidContainerCondition.dead => StatusTone.warning,
    UnraidContainerCondition.stopped ||
    UnraidContainerCondition.paused ||
    UnraidContainerCondition.created ||
    UnraidContainerCondition.unknown => StatusTone.neutral,
  };

  /// The words the board prints. "stopped on purpose" is deliberately longer
  /// than "stopped": the row exists to say that nothing is wrong.
  String get label => switch (this) {
    UnraidContainerCondition.running => 'running',
    UnraidContainerCondition.unhealthy => 'unhealthy',
    UnraidContainerCondition.paused => 'paused',
    UnraidContainerCondition.stopped => 'stopped on purpose',
    UnraidContainerCondition.exitedUnexpectedly => 'exited unexpectedly',
    UnraidContainerCondition.restarting => 'restarting',
    UnraidContainerCondition.dead => 'dead',
    UnraidContainerCondition.created => 'created',
    UnraidContainerCondition.unknown => 'unknown',
  };
}

/// `Up 3 days`, `Up 20 minutes (unhealthy)`, `Up 2 hours (Paused)`.
final _upPattern = RegExp(
  r'^up\s*(.*?)\s*(?:\((healthy|unhealthy|health: starting|paused)\))?$',
  caseSensitive: false,
);

/// `Exited (137) 3 hours ago`, `Restarting (1) 5 seconds ago`.
final _exitPattern = RegExp(
  r'^(exited|restarting)\s*\((\d+)\)\s*(.*)$',
  caseSensitive: false,
);

/// A Docker container (`dockerContainers`).
class UnraidDockerContainer {
  const UnraidDockerContainer({
    required this.id,
    required this.name,
    required this.state,
    required this.status,
    required this.autoStart,
    required this.condition,
    required this.exitCode,
    required this.age,
  });

  final String id;
  final String name;
  final String state;

  /// Docker's own status line, kept verbatim as the fallback for anything
  /// [condition] could not parse.
  final String status;

  final bool autoStart;

  final UnraidContainerCondition condition;

  /// The process exit code, when the status line carried one. Null — never 0 —
  /// when it did not: 0 is "exited cleanly", which is a different claim from
  /// "we do not know how it exited".
  final int? exitCode;

  /// The human age Docker appended: `12 days`, `3 hours ago`. Empty when the
  /// status line had none.
  final String age;

  bool get running => condition == UnraidContainerCondition.running;

  StatusTone get tone => condition.tone;

  /// The row's second line: `stopped on purpose · exit 0 · 2 days ago`.
  ///
  /// Falls back to Docker's raw string rather than to a blank, so an
  /// unrecognised status still shows the user what the server said.
  String get summary {
    if (condition == UnraidContainerCondition.unknown) {
      return status.isEmpty ? 'unknown' : status;
    }
    return [
      condition.label,
      if (exitCode != null) 'exit $exitCode',
      if (age.isNotEmpty) age,
    ].join(' · ');
  }

  /// Reads the condition, exit code and age out of Docker's status line.
  ///
  /// [state] is only the tiebreak: the SDL types it as an enum with two members
  /// (`RUNNING`, `EXITED`), which cannot express unhealthy, paused or a restart
  /// loop. The status string can, and it is the field that carries the exit
  /// code the design asks the two kinds of stop to be told apart by.
  static UnraidDockerContainer _parse({
    required String id,
    required String name,
    required String state,
    required String status,
    required bool autoStart,
  }) {
    final trimmed = status.trim();
    final lower = trimmed.toLowerCase();

    UnraidContainerCondition condition;
    int? exitCode;
    String age = '';

    final exited = _exitPattern.firstMatch(trimmed);
    final up = _upPattern.firstMatch(trimmed);
    if (exited != null) {
      exitCode = int.tryParse(exited.group(2)!);
      age = exited.group(3)?.trim() ?? '';
      final restarting = exited.group(1)!.toLowerCase() == 'restarting';
      condition = restarting
          ? UnraidContainerCondition.restarting
          : (exitCode == 0
                ? UnraidContainerCondition.stopped
                : UnraidContainerCondition.exitedUnexpectedly);
    } else if (up != null) {
      age = up.group(1)?.trim() ?? '';
      final health = up.group(2)?.toLowerCase();
      condition = switch (health) {
        'unhealthy' => UnraidContainerCondition.unhealthy,
        'paused' => UnraidContainerCondition.paused,
        // `health: starting` is the grace period of a healthcheck that has not
        // reported yet. Not a fault, and not a lie either: the container is up.
        _ => UnraidContainerCondition.running,
      };
    } else if (lower.startsWith('paused')) {
      condition = UnraidContainerCondition.paused;
    } else if (lower.startsWith('created')) {
      condition = UnraidContainerCondition.created;
    } else if (lower.startsWith('dead')) {
      condition = UnraidContainerCondition.dead;
    } else if (lower.startsWith('exited')) {
      // `Exited` with no code at all. The container is down and nothing says
      // why, which is not enough to call it either deliberate or a crash.
      condition = UnraidContainerCondition.unknown;
    } else if (trimmed.isEmpty) {
      // No status line: fall back to the two-member state enum, which at least
      // says up or down.
      condition = state.toLowerCase() == 'running'
          ? UnraidContainerCondition.running
          : UnraidContainerCondition.unknown;
    } else {
      condition = UnraidContainerCondition.unknown;
    }

    return UnraidDockerContainer(
      id: id,
      name: name,
      state: state,
      status: trimmed,
      autoStart: autoStart,
      condition: condition,
      exitCode: exitCode,
      age: age,
    );
  }

  factory UnraidDockerContainer.fromJson(Map<String, dynamic> json) {
    final names = json['names'];
    String name;
    if (names is List && names.isNotEmpty) {
      name = names.first.toString().replaceFirst(RegExp(r'^/'), '');
    } else {
      name = (json['name'] ?? 'container').toString();
    }
    return _parse(
      id: (json['id'] ?? '').toString(),
      name: name,
      state: (json['state'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      autoStart: json['autoStart'] == true,
    );
  }
}
