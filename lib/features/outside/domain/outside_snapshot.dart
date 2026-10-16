/// What Cupola shows outside itself: the widgets on the home screen and the
/// lock screen, drawn by native code from a file the app writes.
///
/// **Every word is written here, in Dart, and none by the widget.** A widget
/// cannot run Dart when it is drawn, and a second copy of the app's words in
/// Swift and Kotlin would drift from the first within a release. So the run
/// that reads the servers (`OutsideRun`) writes each widget as a short list of
/// [OutsideFrame]s, each one already in words and figures and each valid from
/// an instant: the drawing as it is now, as it is past midnight (`Today`
/// becomes `Yesterday`, an episode that aired leaves), and as it is once its
/// running figures stop being true (a time left is a lie an hour later). The
/// widget draws the last frame whose [OutsideFrame.from] has passed, which is
/// what WidgetKit's timeline is for, and Android's widget does the same each
/// time it is updated.
///
/// **Nothing secret goes out.** The file lives where the widget can read it
/// (the App Group on iOS), which is outside the keychain: no key, no address,
/// no header. A picture is a file name beside the snapshot, fetched by the run
/// with the connection's credentials, which never leave the run.
///
/// **Red is never drawn.** A server out of reach is not a fact about the
/// server, it is where the phone is: the widget keeps its last frames and
/// says how old they are ([OutsideFace.age]).
library;

import 'package:flutter/foundation.dart';

/// The widgets Cupola has. Which of them a person can add depends on who
/// they are: [comingUp] and [downloads] are the operator's, [requests] the
/// requester's.
enum OutsideWidget { comingUp, downloads, requests }

/// The tone a word or a bar is painted in, by name: the native side maps
/// each to the same token the app paints it with, in the room the system is
/// in. The five-tone rule without its red ([OutsideSnapshot] says why).
enum OutsideTone { green, amber, blue, neutral }

/// One thing in a widget: a title to come, a download, a request.
@immutable
class OutsideItem {
  const OutsideItem({
    required this.title,
    this.eyebrow,
    this.words,
    this.tone,
    this.progress,
    this.poster,
    this.backdrop,
    this.route,
  });

  /// The line above the title: `Today · 21:00`, `Ready to watch`.
  final String? eyebrow;

  final String title;

  /// What it is and where it stands: `S1 E4 · not aired`, `68% · 6 min`.
  final String? words;

  /// The tone of [words] and of the bar; null is the ink.
  final OutsideTone? tone;

  /// How far it got, 0 to 1, for the bar; null draws none.
  final double? progress;

  /// File names beside the snapshot, null when there is no picture.
  final String? poster;
  final String? backdrop;

  /// Where a tap opens, a location of the app's router.
  final String? route;

  Map<String, Object?> toJson() => {
    'title': title,
    'eyebrow': ?eyebrow,
    'words': ?words,
    'tone': ?tone?.name,
    'progress': ?progress,
    'poster': ?poster,
    'backdrop': ?backdrop,
    'route': ?route,
  };

  @override
  bool operator ==(Object other) =>
      other is OutsideItem &&
      other.title == title &&
      other.eyebrow == eyebrow &&
      other.words == words &&
      other.tone == tone &&
      other.progress == progress &&
      other.poster == poster &&
      other.backdrop == backdrop &&
      other.route == route;

  @override
  int get hashCode => Object.hash(
    title,
    eyebrow,
    words,
    tone,
    progress,
    poster,
    backdrop,
    route,
  );

  @override
  String toString() => 'OutsideItem($title, $eyebrow, $words, $tone)';
}

/// What one widget draws at one moment, in every size: each size takes what
/// it has room for, in this order.
@immutable
class OutsideFace {
  const OutsideFace({
    required this.title,
    required this.age,
    this.aged = false,
    this.subtitle,
    this.figure,
    this.figureWords,
    this.lead,
    this.items = const [],
    this.calm,
    this.route,
  });

  /// The widget's name, as the Home's module says it: `Coming up`.
  final String title;

  /// The module's line: `3 moving · 1 stuck · 2.4 MB/s`.
  final String? subtitle;

  /// The one figure a small widget leads with, and its word: `3`, `moving`.
  final String? figure;
  final String? figureWords;

  /// The thing a widget leads with: the next title, the newest arrival.
  final OutsideItem? lead;

  /// The rest, in drawing order; a widget draws as many as fit.
  final List<OutsideItem> items;

  /// What a widget with nothing to show says: `Nothing is downloading`.
  final String? calm;

  /// `As of 14:02`: always drawn where there is room, and drawn by every
  /// size once [aged].
  final String age;

  /// Old enough that the small widget gives a line to its age.
  final bool aged;

  /// Where a tap on the widget, away from its items, opens.
  final String? route;

  Map<String, Object?> toJson() => {
    'title': title,
    'subtitle': ?subtitle,
    'figure': ?figure,
    'figureWords': ?figureWords,
    'lead': ?lead?.toJson(),
    'items': [for (final item in items) item.toJson()],
    'calm': ?calm,
    'age': age,
    'aged': aged,
    'route': ?route,
  };

  @override
  bool operator ==(Object other) =>
      other is OutsideFace &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.figure == figure &&
      other.figureWords == figureWords &&
      other.lead == lead &&
      listEquals(other.items, items) &&
      other.calm == calm &&
      other.age == age &&
      other.aged == aged &&
      other.route == route;

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    figure,
    figureWords,
    lead,
    Object.hashAll(items),
    calm,
    age,
    aged,
    route,
  );
}

/// A face and the instant from which it is the true one.
@immutable
class OutsideFrame {
  const OutsideFrame(this.from, this.face);

  final DateTime from;
  final OutsideFace face;

  Map<String, Object?> toJson() => {
    'from': from.toUtc().toIso8601String(),
    'face': face.toJson(),
  };
}

/// What the run writes: who the widgets are for, when the servers were
/// read, and each widget's frames. A widget with no frames is one this
/// person has nothing for (no calendar set up, no Seerr): it says so with
/// its own empty state, never with a frame of zeros.
@immutable
class OutsideSnapshot {
  const OutsideSnapshot({
    required this.takenAt,
    required this.audience,
    required this.frames,
  });

  /// The shape of the file. The native side draws nothing from a file of
  /// another version, rather than misread it.
  static const version = 1;

  /// How many frames a widget keeps: enough for three days of midnights
  /// and the times things air, few enough that the file stays small.
  static const maxFrames = 12;

  final DateTime takenAt;

  /// `operator` or `requester`, as the shell names them.
  final String audience;

  final Map<OutsideWidget, List<OutsideFrame>> frames;

  Map<String, Object?> toJson() => {
    'version': version,
    'takenAt': takenAt.toUtc().toIso8601String(),
    'audience': audience,
    'widgets': {
      for (final MapEntry(:key, :value) in frames.entries)
        key.name: [for (final frame in value) frame.toJson()],
    },
  };
}

/// [build] at each of [moments], as frames, the first at [takenAt]: a moment
/// before it, or that draws the face the frame before it drew, adds nothing
/// and is left out. At most [OutsideSnapshot.maxFrames].
List<OutsideFrame> outsideFramesAt(
  DateTime takenAt,
  Iterable<DateTime> moments,
  OutsideFace Function(DateTime at) build,
) {
  final times = {
    takenAt,
    for (final moment in moments)
      if (moment.isAfter(takenAt)) moment,
  }.toList()..sort();
  final frames = <OutsideFrame>[];
  for (final at in times) {
    final face = build(at);
    if (frames.isNotEmpty && frames.last.face == face) continue;
    frames.add(OutsideFrame(at, face));
    if (frames.length == OutsideSnapshot.maxFrames) break;
  }
  return frames;
}

/// The local midnights after [from], [count] of them: where `Today`,
/// `Tomorrow` and `As of 14:02` change their words.
List<DateTime> outsideMidnights(DateTime from, {int count = 3}) {
  final local = from.toLocal();
  return [
    for (var day = 1; day <= count; day++)
      DateTime(local.year, local.month, local.day + day),
  ];
}
