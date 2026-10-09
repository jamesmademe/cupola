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

/// What [alert] says, as a fault's headline.
///
/// A disk's uncorrectable errors (TrueNAS's "Uncorrected Errors Detected",
/// formatted from `ue`, `name` and `serial`) reads
/// `Disk sdd reports 8 uncorrectable errors`. Any other alert reads its own
/// message, up to its first full stop: TrueNAS writes them as sentences.
String trueNasAlertHeadline(TrueNasAlert alert) {
  var errors = alert.args['ue'];
  var disk = alert.args['name'];
  // The same alert when it came without its figures: TrueNAS's own sentence,
  // `8 uncorrectable errors reported for sdd (ZL2PQR7T).`
  if (errors is! int || disk is! String) {
    final match = _uncorrected.firstMatch(alert.message);
    errors = int.tryParse(match?.group(1) ?? '');
    disk = match?.group(2);
  }
  if (errors is int && disk is String && disk.isNotEmpty) {
    return 'Disk $disk reports $errors uncorrectable '
        '${errors == 1 ? 'error' : 'errors'}';
  }
  final message = alert.message.trim();
  final stop = message.indexOf('. ');
  final sentence = stop < 0 ? message : message.substring(0, stop);
  return sentence.endsWith('.')
      ? sentence.substring(0, sentence.length - 1)
      : sentence;
}
