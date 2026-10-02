/// Typed models for the Unraid GraphQL API.
///
/// Unraid's GraphQL schema evolves between releases, so field access is
/// deliberately tolerant: a missing field degrades rather than throwing.
/// Tolerant is not the same as inventive — a field the server did not answer
/// degrades to **null**, so the page above can say it has no figure. It never
/// degrades to a zero, an empty list stated as a census, or a word nobody sent.
/// Confirm exact field names against the target instance's schema (SDL / Apollo
/// sandbox) before relying on any one of them.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';

/// The three `Resource` values the Unraid SDL declares that Cupola can write.
///
/// [share] is parsed and carried even though nothing writes a share yet: this
/// mirrors the server's own enum, and dropping a value the schema declares
/// would mean re-deriving it the day a Shares write lands. `canWrite(share)`
/// having no caller is the honest state, not a gap.
enum UnraidResource { vms, notifications, share }

/// What an Unraid API key may do, from `query { me { roles permissions } }`.
///
/// Any valid key may ask about itself: `Query.me` needs only `ME:READ_ANY`,
/// which every role inherits from `GUEST` (Unraid API v4.0.0+).
class UnraidCapabilities {
  const UnraidCapabilities({
    required this.isAdmin,
    required this.writable,
    this.answered = true,
  });

  final bool isAdmin;
  final Set<UnraidResource> writable;

  /// Whether the server answered with a `roles` list at all. False for a `me`
  /// object missing the field — an answer that says nothing, which the probe
  /// reads as "could not ask" rather than as read-only.
  final bool answered;

  /// The actions that change a resource. Only the `_ANY` forms: the resolvers
  /// Cupola calls guard on `UPDATE_ANY` / `DELETE_ANY` / `CREATE_ANY`, so a key
  /// holding only `UPDATE_OWN` cannot make them and must not be drawn live.
  static const writeActions = {'UPDATE_ANY', 'DELETE_ANY', 'CREATE_ANY'};

  bool canWrite(UnraidResource resource) =>
      isAdmin || writable.contains(resource);

  factory UnraidCapabilities.fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as List?) ?? const [];
    final writable = <UnraidResource>{};
    for (final raw in (json['permissions'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final permission = raw.cast<String, dynamic>();
      final actions =
          (permission['actions'] as List?)
              ?.map((e) => e.toString().toUpperCase())
              .toSet() ??
          const <String>{};
      // `me.permissions` lists only the key's **explicit** permissions, never
      // the ones its roles imply — and `VIEWER`, `CONNECT` and `GUEST` imply
      // no write on the resources Cupola changes, so this list is the whole
      // answer for a non-admin.
      if (!actions.any(writeActions.contains)) continue;
      final resource = switch (permission['resource']
          ?.toString()
          .toUpperCase()) {
        'VMS' => UnraidResource.vms,
        'NOTIFICATIONS' => UnraidResource.notifications,
        'SHARE' => UnraidResource.share,
        _ => null,
      };
      if (resource != null) writable.add(resource);
    }
    return UnraidCapabilities(
      isAdmin: roles.any((r) => r.toString().toUpperCase() == 'ADMIN'),
      writable: Set.unmodifiable(writable),
      answered: json['roles'] is List,
    );
  }
}

enum UnraidVmAction {
  start('start'),
  stop('stop'),
  pause('pause'),
  resume('resume'),
  forceStop('forceStop'),
  reboot('reboot');

  const UnraidVmAction(this.graphQl);
  final String graphQl;
}

class UnraidVm {
  const UnraidVm({required this.id, required this.name, required this.state});
  final String id;
  final String name;
  final String state;

  bool get isRunning => state.toUpperCase() == 'RUNNING';
  bool get isPaused => state.toUpperCase() == 'PAUSED';
  bool get isFaulted => state.toUpperCase() == 'CRASHED';
  StatusTone get tone => isFaulted
      ? StatusTone.warning
      : (isRunning ? StatusTone.success : StatusTone.neutral);

  factory UnraidVm.fromJson(Map<String, dynamic> json) => UnraidVm(
    id: json['id']?.toString() ?? '',
    // `stringOrNull` trims and folds empty to null in one step; the older
    // spelling tested the trimmed value and then stored the untrimmed one.
    name: stringOrNull(json['name']) ?? 'Unnamed VM',
    state: json['state']?.toString() ?? 'NOSTATE',
  );
}

enum UnraidNotificationType {
  unread('UNREAD'),
  archive('ARCHIVE');

  const UnraidNotificationType(this.graphQl);
  final String graphQl;
}

class UnraidNotificationCounts {
  const UnraidNotificationCounts({
    required this.info,
    required this.warning,
    required this.alert,
    required this.total,
  });
  final int? info;
  final int? warning;
  final int? alert;
  final int? total;

  factory UnraidNotificationCounts.fromJson(Map<String, dynamic>? json) =>
      UnraidNotificationCounts(
        info: intOrNull(json?['info']),
        warning: intOrNull(json?['warning']),
        alert: intOrNull(json?['alert']),
        total: intOrNull(json?['total']),
      );
}

class UnraidNotification {
  const UnraidNotification({
    required this.id,
    required this.title,
    required this.subject,
    required this.description,
    required this.importance,
    required this.type,
    this.timestamp,
    this.link,
  });
  final String id;
  final String title;
  final String subject;
  final String description;
  final String importance;
  final String type;
  final DateTime? timestamp;
  final String? link;

  StatusTone get tone => switch (importance.toUpperCase()) {
    'ALERT' || 'WARNING' => StatusTone.warning,
    'INFO' => StatusTone.info,
    _ => StatusTone.neutral,
  };

  factory UnraidNotification.fromJson(Map<String, dynamic> json) =>
      UnraidNotification(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        importance: json['importance']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        // `??` only covers a *missing* `timestamp`. Unraid also sends one it
        // cannot format, so the fallback has to be on the parse rather than on
        // the key, or a notification with a junk timestamp reads as undated
        // while `formattedTimestamp` was sitting right there.
        timestamp:
            DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.tryParse(json['formattedTimestamp']?.toString() ?? ''),
        link: json['link']?.toString(),
      );
}

class UnraidNotifications {
  const UnraidNotifications({
    required this.unread,
    required this.archived,
    required this.items,
  });
  final UnraidNotificationCounts unread;
  final UnraidNotificationCounts archived;
  final List<UnraidNotification> items;

  factory UnraidNotifications.fromJson(Map<String, dynamic> json) {
    final overview = (json['overview'] as Map?)?.cast<String, dynamic>();
    return UnraidNotifications(
      unread: UnraidNotificationCounts.fromJson(
        (overview?['unread'] as Map?)?.cast<String, dynamic>(),
      ),
      archived: UnraidNotificationCounts.fromJson(
        (overview?['archive'] as Map?)?.cast<String, dynamic>(),
      ),
      items: ((json['list'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => UnraidNotification.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class UnraidShare {
  const UnraidShare({
    required this.id,
    required this.name,
    this.usedKilobytes,
    this.sizeKilobytes,
    this.comment = '',
    this.cached,
    this.luksStatus = '',
  });
  final String id;
  final String name;
  final int? usedKilobytes;
  final int? sizeKilobytes;
  final String comment;
  final bool? cached;
  final String luksStatus;

  double? get usedFraction =>
      usedKilobytes != null && sizeKilobytes != null && sizeKilobytes! > 0
      ? (usedKilobytes! / sizeKilobytes!).clamp(0, 1).toDouble()
      : null;

  factory UnraidShare.fromJson(Map<String, dynamic> json) => UnraidShare(
    id: json['id']?.toString() ?? '',
    name: stringOrNull(json['name']) ?? 'Unnamed share',
    usedKilobytes: intOrNull(json['used']),
    sizeKilobytes: intOrNull(json['size']),
    comment: json['comment']?.toString() ?? '',
    cached: json['cache'] is bool ? json['cache'] as bool : null,
    luksStatus: json['luksStatus']?.toString() ?? '',
  );
}

/// System information (`info`).
class UnraidInfo {
  const UnraidInfo({required this.distro, required this.version, this.uptime});

  final String distro;

  /// Unraid release string, surfaced as the service version.
  final String version;

  final String? uptime;

  factory UnraidInfo.fromJson(Map<String, dynamic> json) {
    final os = (json['os'] as Map?)?.cast<String, dynamic>() ?? const {};
    // Empty, never `'Unraid'`: both `distro` and `release` are nullable in the
    // committed SDL, and a server that answered `info: null` — or an `os` block
    // without them — has stated no release. Filling the word in here would put
    // a string the server never sent under a row labelled `Release`, in the one
    // slot the page reserves for what the server said; the fold above this
    // reads an empty join as `—`, which is the truthful reading.
    return UnraidInfo(
      distro: (os['distro'] ?? '').toString(),
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
    required List<UnraidDisk>? disks,
    this.usedBytes,
    this.totalBytes,
  }) : _disks = disks;

  final String state;

  /// Fraction of total capacity used (0..1), or null when unknown.
  final double? usedFraction;

  /// The slot list exactly as the array answered it — **null when it answered
  /// with none at all**.
  ///
  /// `disks: [ArrayDisk!]` is nullable in the committed SDL, and this library
  /// is deliberately tolerant of a field a release renamed. Folding both of
  /// those into `const []` made an absent list indistinguishable from an empty
  /// one, and the header that counts it then says `0 disks` — an assertion that
  /// the array has no drives, built out of silence.
  final List<UnraidDisk>? _disks;

  /// The slots, empty when the array reported none *and* when it reported
  /// nothing. Read [reportedDisks] before stating the length as a census.
  List<UnraidDisk> get disks => _disks ?? const [];

  /// Whether the payload carried a slot list at all.
  ///
  /// True for an array that answered `disks: []` — that is a real census of an
  /// array with no drives in it — and false only for silence.
  bool get reportedDisks => _disks != null;

  /// The absolute capacity figures, normalised to **bytes**, or null when the
  /// server reported no capacity block at all.
  ///
  /// Kept beside [usedFraction] rather than derived from it, because they
  /// cannot be: a fraction is unitless and the board's headline readout —
  /// `31.2 of 40.0 TB` — is the pair of absolute figures. The query has always
  /// asked for `capacity { kilobytes { free used total } }`; the mapper simply
  /// threw the numerator and denominator away after dividing them, so the
  /// Overview had a percentage and no way to say what it was a percentage of.
  ///
  /// Null, never 0: a server that answered with no capacity block is a figure
  /// nobody has, and `0 B` is a claim that the array is empty.
  final int? usedBytes;
  final int? totalBytes;

  /// The used share as a whole percentage, or **null** when the array reported
  /// no capacity block.
  ///
  /// Null and never 0, for the same reason [usedBytes] is: `Used 0%` on the
  /// readout rail reads as an empty array, which is the one conclusion a user
  /// acts on, and it would contradict the Array section an inch below — whose
  /// capacity clause correctly disappears for exactly this input.
  int? get usedPercent {
    final fraction = usedFraction;
    return fraction == null ? null : wholePercent(fraction * 100);
  }

  factory UnraidArray.fromJson(Map<String, dynamic> json) {
    double? usedFraction;
    int? usedBytes;
    int? totalBytes;
    final capacity = (json['capacity'] as Map?)?.cast<String, dynamic>();
    final kilobytes = (capacity?['kilobytes'] as Map?)?.cast<String, dynamic>();
    final bytes = (capacity?['bytes'] as Map?)?.cast<String, dynamic>();
    // Which bucket answered decides the unit, and the unit has to be settled
    // here: the fraction below is unitless and did not care, but an absolute
    // figure read out of the kilobyte bucket and printed as bytes is off by
    // 1024 — a 40 TB array rendered as 39 GB.
    final bucket = kilobytes ?? bytes;
    final scale = kilobytes != null ? 1024 : 1;
    if (bucket != null) {
      final total = doubleOrNull(bucket['total']) ?? 0.0;
      final used = doubleOrNull(bucket['used']) ?? 0.0;
      if (total > 0) {
        usedFraction = (used / total).clamp(0, 1).toDouble();
        totalBytes = (total * scale).round();
        // `used` alone is kept only when the array reported a total as well:
        // a used figure with nothing to compare it against is half a sentence,
        // and the label this feeds says "x of y".
        usedBytes = (used * scale).round();
      }
    }
    // Left null when the field is absent, rather than collapsed to an empty
    // list: see [_disks]. An array that answered `disks: []` still lands here
    // as a list, and that one is a census.
    final disks = json['disks'] as List?;
    return UnraidArray(
      state: (json['state'] ?? 'UNKNOWN').toString(),
      usedFraction: usedFraction,
      usedBytes: usedBytes,
      totalBytes: totalBytes,
      disks: disks
          ?.whereType<Map>()
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

  /// Whether the array has flagged this slot.
  ///
  /// Unraid reports slot health as `DISK_OK`, `DISK_NEW`, `DISK_NP` (no disk in
  /// the slot), `DISK_INVALID`, `DISK_DSBL` (disabled — the array is running
  /// without it) and a handful of `DISK_*` siblings. Only the first two are
  /// "nothing to do here"; everything else is the array telling us something is
  /// wrong with a slot it expected to use. An empty status is not a verdict, so
  /// it is not one here either.
  ///
  /// Separate from [tone] because the header counts the two kinds of trouble
  /// apart: a drive can be flagged *and* over temperature, and the count that
  /// names the more serious of the two must never be the one that drops it.
  bool get flagged {
    final value = status.trim().toUpperCase();
    return value.isNotEmpty && value != 'DISK_OK' && value != 'DISK_NEW';
  }

  /// Amber for a slot the array has [flagged] or a drive over the warning
  /// threshold — both are faults the user can act on — and neutral otherwise.
  /// Nothing here is ever red, because red on this canvas means the host did
  /// not answer at all.
  StatusTone get tone =>
      flagged || warm ? StatusTone.warning : StatusTone.neutral;

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
