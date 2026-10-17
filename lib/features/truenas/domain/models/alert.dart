import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// An alert from `alert.list`.
class TrueNasAlert {
  final String id;
  final String level;
  final String message;
  final bool dismissed;
  final int? datetimeMs;

  /// The alert's class (`klass`), e.g. `SMART`; empty when it gave none.
  final String klass;

  /// The figures the alert's message was formatted from (`args`), when it
  /// carried them as a map: what lets the app say it in its own words.
  final Map<String, dynamic> args;

  const TrueNasAlert({
    required this.id,
    required this.level,
    required this.message,
    required this.dismissed,
    this.datetimeMs,
    this.klass = '',
    this.args = const {},
  });

  /// TrueNAS's levels at which an alert needs somebody: warning and worse.
  /// `INFO` and `NOTICE` are news.
  bool get needsAttention => const {
    'WARNING',
    'ERROR',
    'CRITICAL',
    'ALERT',
    'EMERGENCY',
  }.contains(level.toUpperCase());

  factory TrueNasAlert.fromJson(Map<String, dynamic> json) {
    final datetime = json['datetime'];
    int? ms;
    if (datetime is Map) ms = intOrNull(datetime['\$date']);

    return TrueNasAlert(
      id: stringOrNull(json['uuid']) ?? stringOrNull(json['id']) ?? '',
      level: stringOrNull(json['level']) ?? 'INFO',
      message:
          stringOrNull(json['formatted']) ??
          stringOrNull(json['text']) ??
          'Alert',
      dismissed: json['dismissed'] == true,
      datetimeMs: ms,
      klass: stringOrNull(json['klass']) ?? '',
      args: switch (json['args']) {
        final Map<String, dynamic> args => args,
        _ => const {},
      },
    );
  }
}

final _uncorrected = RegExp(r'^(\d+) uncorrectable errors? reported for (\S+)');

/// The disk [alert] reports uncorrectable errors on, and how many: from its
/// `ue` and `name`, or from TrueNAS's own sentence when it came without them
/// (`8 uncorrectable errors reported for sdd (ZL2PQR7T).`). Null for any
/// other alert.
({String disk, int errors})? trueNasDiskErrors(TrueNasAlert alert) {
  var errors = alert.args['ue'];
  var disk = alert.args['name'];
  if (errors is! int || disk is! String) {
    final match = _uncorrected.firstMatch(alert.message);
    errors = int.tryParse(match?.group(1) ?? '');
    disk = match?.group(2);
  }
  if (errors is int && disk is String && disk.isNotEmpty) {
    return (disk: disk, errors: errors);
  }
  return null;
}

/// What [alert] says, as a fault's headline.
///
/// A disk's uncorrectable errors (TrueNAS's "Uncorrected Errors Detected",
/// formatted from `ue`, `name` and `serial`) reads
/// `Disk sdd reports 8 uncorrectable errors`, and a disk's SMART alert says
/// what the disk reported ([_smartHeadline]). Any other alert reads its own
/// message, up to its first full stop: TrueNAS writes them as sentences.
String trueNasAlertHeadline(TrueNasAlert alert) {
  if (trueNasDiskErrors(alert) case (:final disk, :final errors)) {
    return 'Disk $disk reports $errors uncorrectable '
        '${errors == 1 ? 'error' : 'errors'}';
  }
  if (_smartHeadline(alert) case final headline?) return headline;
  final message = alert.message.trim();
  final stop = message.indexOf('. ');
  final sentence = stop < 0 ? message : message.substring(0, stop);
  return sentence.endsWith('.')
      ? sentence.substring(0, sentence.length - 1)
      : sentence;
}

/// What a disk's SMART alert says, in the app's words, or null when [alert]
/// is not one.
///
/// TrueNAS has said it two ways. Up to 25.04 every SMART alert is the class
/// `SMART`, `device` (`/dev/sda ('ZL2PQR7T')`) and `message`, smartd's own
/// line: `Device: /dev/sda [SAT], 8 Currently unreadable (pending) sectors`.
/// From 25.10 each has its class and its figures: `SMARTFailedSelfTest`,
/// `SMARTSpareBlockCount`, `SMARTEraseCycleCount`, each with `name`. smartd's
/// line stays behind Why?, which reads the alert's own message.
String? _smartHeadline(TrueNasAlert alert) {
  final klass = alert.klass;
  if (!klass.startsWith('SMART')) return null;
  final disk = switch (alert.args['name']) {
    final String name when name.isNotEmpty => name,
    _ => _smartDevice(alert),
  };
  final who = disk == null ? 'A disk' : 'Disk $disk';
  switch (klass) {
    case 'SMARTFailedSelfTest':
      return '$who failed a SMART self-test';
    case 'SMARTSpareBlockCount':
      return '$who is running low on spare blocks';
    case 'SMARTEraseCycleCount':
      return '$who has a high erase count';
    case 'SMART':
      break;
    default:
      return '$who reports a SMART problem';
  }
  final line = switch (alert.args['message']) {
    final String message => message,
    _ => alert.message,
  };
  if (_count(line, r'(\d+) Currently unreadable \(pending\) sectors?')
      case final n?) {
    return '$who has $n unreadable ${n == 1 ? 'sector' : 'sectors'}';
  }
  if (_count(line, r'(\d+) Offline uncorrectable sectors?') case final n?) {
    return '$who has $n uncorrectable ${n == 1 ? 'sector' : 'sectors'}';
  }
  if (line.contains('FAILED SMART self-check')) {
    return '$who failed its SMART health check';
  }
  if (line.contains('Self-Test Log error count increased')) {
    return '$who failed a SMART self-test';
  }
  if (_count(line, r'ATA error count increased from \d+ to (\d+)')
      case final n?) {
    return '$who reports $n ATA ${n == 1 ? 'error' : 'errors'}';
  }
  return '$who reports a SMART problem';
}

/// The disk a pre-25.10 SMART alert names: `sda` from `device`
/// (`/dev/sda ('ZL2PQR7T')`), or from smartd's `Device: /dev/sda` in the
/// message when the args are gone.
String? _smartDevice(TrueNasAlert alert) {
  final device = switch (alert.args['device']) {
    final String device => device,
    _ => alert.message,
  };
  return RegExp(r'/dev/([A-Za-z0-9]+)').firstMatch(device)?.group(1);
}

int? _count(String line, String pattern) =>
    int.tryParse(RegExp(pattern).firstMatch(line)?.group(1) ?? '');
