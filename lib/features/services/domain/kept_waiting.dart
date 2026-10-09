/// Keep waiting: a stuck download given more time on purpose.
///
/// The brand book's third remedy for a stuck download, beside trying another
/// and removing it: the fault leaves every place that counts faults for
/// [keptWaitingFor], and comes back if nothing has moved by then. A download
/// that moves in the meantime has answered the question, so its choice lapses
/// at once, and if it sticks again it is a new fault.
///
/// Pure: the choice, its test, and its wire form. The store is
/// `keptWaitingProvider`.
library;

/// How long Keep waiting hides a stuck download.
const Duration keptWaitingFor = Duration(hours: 24);

/// One download kept waiting: until when, and how much of it had arrived
/// when the choice was made.
class KeptWaiting {
  const KeptWaiting({required this.until, required this.progress});

  /// The choice made at [now] for a download at [progress].
  factory KeptWaiting.from({
    required DateTime now,
    required double? progress,
  }) => KeptWaiting(until: now.add(keptWaitingFor), progress: progress ?? 0);

  final DateTime until;

  /// The share that had arrived, 0 to 1.
  final double progress;

  /// Whether a download now at [currentProgress] is still kept waiting at
  /// [now]: before [until], and nothing more has arrived.
  bool holds({required double? currentProgress, required DateTime now}) =>
      now.isBefore(until) && (currentProgress ?? 0) <= progress + _moved;

  /// Below this a change in progress is rounding between two reads, not a
  /// byte arriving: a thousandth of the download.
  static const double _moved = 0.001;

  Map<String, Object> toJson() => {
    'until': until.millisecondsSinceEpoch,
    'progress': progress,
  };

  /// Null for anything that is not a choice this app wrote.
  static KeptWaiting? fromJson(Object? json) {
    if (json is! Map) return null;
    final until = json['until'];
    final progress = json['progress'];
    if (until is! int || progress is! num) return null;
    return KeptWaiting(
      until: DateTime.fromMillisecondsSinceEpoch(until),
      progress: progress.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeptWaiting &&
      other.until == until &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(until, progress);
}
