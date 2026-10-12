/// The requester's requests as she reads them: where each one stands, in
/// her words, and when.
///
/// Everything comes from her own Seerr session: `GET /request` answers an
/// account without the right to manage requests with its own only, and each
/// row carries what Seerr follows of the title's download
/// (`downloadStatus`), Seerr's link to it in the player and the time the
/// player first held it. Never a service's name, a release or a fault: a
/// download the operator sees stuck is, to her, on its way.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_download.dart';

/// How long a title she asked for stays [MyRequestStage.readyToWatch] after
/// it arrived; then it is [MyRequestStage.onTheServer].
const myRequestFreshFor = Duration(days: 7);

/// Where one request stands, as she reads it.
enum MyRequestStage {
  /// Nobody has answered it yet: the one she may take back.
  waiting(StatusTone.info),

  /// Approved and moving, with a figure.
  downloading(StatusTone.info),

  /// Downloaded, and being put in place.
  finishing(StatusTone.info),

  /// Approved and coming, with nothing Seerr can measure: queued, held up,
  /// waiting for the release, or stuck where only the operator can mend it.
  onItsWay(StatusTone.info),

  /// On the server, and new there.
  readyToWatch(StatusTone.success),

  /// On the server for a while.
  onTheServer(StatusTone.success),

  /// Whoever runs the server said no.
  declined(StatusTone.neutral),

  /// It failed on the stack; whoever runs the server can send it again.
  didNotGoThrough(StatusTone.neutral),

  /// Its files were taken off the server.
  removed(StatusTone.neutral),

  /// Whoever runs the server barred the title.
  blocked(StatusTone.neutral);

  const MyRequestStage(this.tone);

  /// Blue while on its way, green on the server, neutral for an answer.
  /// Never amber: faults are the operator's.
  final StatusTone tone;

  /// Whether it is still coming: `2 on the way` counts these.
  bool get onTheWay => switch (this) {
    waiting || downloading || finishing || onItsWay => true,
    _ => false,
  };

  /// Whether it is on the server.
  bool get arrived => this == readyToWatch || this == onTheServer;
}

/// One of her requests, read.
@immutable
class MyRequest {
  const MyRequest({
    required this.request,
    required this.stage,
    this.progress,
    this.readyAround,
    this.askedAt,
    this.answeredAt,
    this.arrivedAt,
  });

  final SeerrRequest request;
  final MyRequestStage stage;

  /// How far the download got, 0 to 1, while [MyRequestStage.downloading].
  final double? progress;

  /// When the download should end, while [MyRequestStage.downloading] and
  /// the client says.
  final DateTime? readyAround;

  /// When she asked.
  final DateTime? askedAt;

  /// When it was answered: approved or declined.
  final DateTime? answeredAt;

  /// When the player first held the title, once it [MyRequestStage.arrived].
  final DateTime? arrivedAt;

  String get title => request.media?.title ?? 'Unknown';

  /// The art Ready to watch draws: the wide artwork, else the poster.
  ImageSource get art {
    final media = request.media;
    final backdrop = ImageUtils.buildTmdbPosterUrl(
      media?.backdropPath,
      size: 'w1280',
    );
    return (
      url: backdrop.isNotEmpty
          ? backdrop
          : ImageUtils.buildTmdbPosterUrl(media?.posterPath, size: 'w780'),
      headers: null,
    );
  }

  /// `Standard` or `4K`: the copy she asked for, as her request sheet says.
  String get quality => request.is4k ? '4K' : 'Standard';

  /// Seerr's link to the title in the player, while it is on the server.
  Uri? get watchAt {
    if (!stage.arrived) return null;
    final link = Uri.tryParse(request.watchUrl ?? '');
    return link != null && link.hasScheme ? link : null;
  }

  /// TMDB's score, when enough people gave one.
  double? get score => ratingWorthShowing(
    request.media?.voteAverage,
    votes: request.media?.voteCount,
  );

  /// `62%` while downloading: the figure the Home's row puts at its end.
  String? get figure => switch (progress) {
    final progress? when stage == MyRequestStage.downloading => formatPercent(
      progress * 100,
    ),
    _ => null,
  };

  /// The state in her words: `Downloading 62%`, `Waiting for approval`,
  /// `Ready to watch`.
  String get state => switch (stage) {
    MyRequestStage.waiting => StateWord.waitingForApproval.label,
    MyRequestStage.downloading => 'Downloading $figure',
    MyRequestStage.finishing => Lexicon.finishingOnTheServer,
    MyRequestStage.onItsWay => Lexicon.onItsWayState,
    MyRequestStage.readyToWatch => Lexicon.readyToWatch,
    MyRequestStage.onTheServer => Lexicon.onTheServer,
    MyRequestStage.declined => Lexicon.declined,
    MyRequestStage.didNotGoThrough => Lexicon.requestDidNotGoThrough,
    MyRequestStage.removed => Lexicon.removedFromServer,
    MyRequestStage.blocked => Lexicon.blocked,
  };

  /// [state] where a figure stands at the row's end: `62%` while
  /// downloading.
  String get stateShort => figure ?? state;

  /// The line under the title: `Ready around 21:10`, `Asked 2 h ago ·
  /// Standard`, `Since 18:40`, `Declined by the server's owner`.
  String detail(DateTime now) => switch (stage) {
    MyRequestStage.waiting => [
      if (askedAt case final at?) 'Asked ${askedWords(at, now: now)}',
      quality,
    ].join(' · '),
    MyRequestStage.downloading => switch (readyAround) {
      final at? => 'Ready around ${aroundWords(at, now: now)}',
      null => Lexicon.beingFetched,
    },
    MyRequestStage.finishing || MyRequestStage.onItsWay => Lexicon.beingFetched,
    MyRequestStage.readyToWatch ||
    MyRequestStage.onTheServer => switch (arrivedAt) {
      final at? => 'Since ${sinceWords(at, now: now)}',
      null => Lexicon.onTheServer,
    },
    MyRequestStage.declined => Lexicon.declinedByOwner,
    MyRequestStage.didNotGoThrough =>
      'Whoever runs the server can send it again.',
    MyRequestStage.removed => Lexicon.askAgain,
    MyRequestStage.blocked => Lexicon.blockedByOwner,
  };

  /// The line under the title of the Home's Ready to watch: `You asked for
  /// it on Sunday · TMDB 7.1`.
  String askedLine(DateTime now) => [
    if (askedAt case final at?) 'You asked for it ${dayWords(at, now: now)}',
    if (score case final score?) 'TMDB ${score.toStringAsFixed(1)}',
  ].join(' · ');

  /// The row as a screen reader says it, in one sentence.
  String spoken(DateTime now) => '$title, $state, ${detail(now)}';
}

/// [request] as she reads it at [now]. [stale] while the list on screen is
/// the last one read and the server did not answer since: a percentage and
/// a time that no longer move would claim a download that may have ended,
/// so the request is simply on its way.
MyRequest myRequestOf(
  SeerrRequest request, {
  required DateTime now,
  bool stale = false,
}) {
  final askedAt = DateTime.tryParse(request.createdAt)?.toLocal();
  final answeredAt = DateTime.tryParse(request.updatedAt ?? '')?.toLocal();
  MyRequest read(
    MyRequestStage stage, {
    double? progress,
    DateTime? readyAround,
    DateTime? arrivedAt,
  }) => MyRequest(
    request: request,
    stage: stage,
    progress: progress,
    readyAround: readyAround,
    askedAt: askedAt,
    answeredAt: answeredAt,
    arrivedAt: arrivedAt,
  );

  switch (request.status) {
    case RequestStatus.pendingApproval:
      return read(MyRequestStage.waiting);
    case RequestStatus.declined:
      return read(MyRequestStage.declined);
    case RequestStatus.failed:
      return read(MyRequestStage.didNotGoThrough);
    case RequestStatus.approved:
    case RequestStatus.completed:
    case RequestStatus.unknown:
      break;
  }

  final availability = request.mediaAvailability;
  final arrived =
      availability == SeerrMediaAvailability.available ||
      (request.status == RequestStatus.completed &&
          availability == SeerrMediaAvailability.partiallyAvailable);
  if (arrived) {
    final at = request.media?.addedAt ?? answeredAt;
    final fresh = at != null && now.difference(at) < myRequestFreshFor;
    return read(
      fresh ? MyRequestStage.readyToWatch : MyRequestStage.onTheServer,
      arrivedAt: at,
    );
  }
  switch (availability) {
    case SeerrMediaAvailability.deleted:
      return read(MyRequestStage.removed);
    case SeerrMediaAvailability.blocklisted:
      return read(MyRequestStage.blocked);
    default:
      break;
  }

  final downloads = request.downloads;
  if (!stale && downloads.moving) {
    return read(
      MyRequestStage.downloading,
      progress: downloads.progress,
      readyAround: downloads.finishesAt,
    );
  }
  if (!stale &&
      downloads.isNotEmpty &&
      downloads.every(
        (download) => download.state == SeerrDownloadState.done,
      )) {
    return read(MyRequestStage.finishing);
  }
  return read(MyRequestStage.onItsWay);
}

/// Her requests, read together: what each module and her page draw.
@immutable
class MyRequests {
  const MyRequests(this.all);

  /// Every request, in the order [myRequestsOf] puts them.
  final List<MyRequest> all;

  /// What arrived in the last seven days, newest first: Ready to watch.
  List<MyRequest> get ready => [
    for (final mine in all)
      if (mine.stage == MyRequestStage.readyToWatch) mine,
  ];

  /// Still coming, the ones that move first: the Home's rows, `2 on the way`.
  List<MyRequest> get onTheWay => [
    for (final mine in all)
      if (mine.stage.onTheWay) mine,
  ];

  /// Waiting for an answer, newest first: her page's cards.
  List<MyRequest> get waiting => [
    for (final mine in all)
      if (mine.stage == MyRequestStage.waiting) mine,
  ];

  /// Everything but [waiting], in her page's order.
  List<MyRequest> get rest => [
    for (final mine in all)
      if (mine.stage != MyRequestStage.waiting) mine,
  ];

  /// What the Home's Your requests lists: still coming, then an answer of
  /// the last seven days, so a no is read once and then leaves.
  List<MyRequest> homeRows(DateTime now) => [
    ...onTheWay,
    for (final mine in all)
      if ((mine.stage == MyRequestStage.declined ||
              mine.stage == MyRequestStage.didNotGoThrough) &&
          mine.answeredAt != null &&
          now.difference(mine.answeredAt!) < myRequestFreshFor)
        mine,
  ];
}

/// Her [requests] at [now], ordered: what moves first (downloading,
/// finishing, on its way), then what waits, what arrived lately, the
/// answers, and what has long been on the server; newest first inside each.
MyRequests myRequestsOf(
  Iterable<SeerrRequest> requests, {
  required DateTime now,
  bool stale = false,
}) {
  final read = [
    for (final request in requests)
      myRequestOf(request, now: now, stale: stale),
  ];
  int rank(MyRequestStage stage) => switch (stage) {
    MyRequestStage.downloading => 0,
    MyRequestStage.finishing => 1,
    MyRequestStage.onItsWay => 2,
    MyRequestStage.waiting => 3,
    MyRequestStage.readyToWatch => 4,
    MyRequestStage.declined => 5,
    MyRequestStage.didNotGoThrough => 6,
    MyRequestStage.onTheServer => 7,
    MyRequestStage.removed => 8,
    MyRequestStage.blocked => 9,
  };
  DateTime? when(MyRequest mine) => switch (mine.stage) {
    MyRequestStage.readyToWatch ||
    MyRequestStage.onTheServer => mine.arrivedAt ?? mine.askedAt,
    MyRequestStage.declined ||
    MyRequestStage.didNotGoThrough => mine.answeredAt ?? mine.askedAt,
    _ => mine.askedAt,
  };
  read.sort((a, b) {
    final byStage = rank(a.stage).compareTo(rank(b.stage));
    if (byStage != 0) return byStage;
    final at = when(a);
    final bt = when(b);
    if (at == null || bt == null) return 0;
    return bt.compareTo(at);
  });
  return MyRequests(List.unmodifiable(read));
}

/// The day [at] fell on, as a sentence says it: `today`, `yesterday`, `on
/// Sunday` within the week, then `on Sat 12 Sep` ([formatPastDayOn]).
String dayWords(DateTime at, {required DateTime now}) =>
    formatPastDayOn(at, now: now) ?? 'today';

/// When she asked, after `Asked`: `2 h ago` within the half day, then
/// [dayWords].
String askedWords(DateTime at, {required DateTime now}) =>
    now.difference(at) < const Duration(hours: 12)
    ? formatSampleAge(at, now: now)
    : dayWords(at, now: now);

/// Since when it is on the server, after `Since`: `18:40` today, then
/// `yesterday`, `Sunday`, `Sat 12 Sep` ([formatPastDay]).
String sinceWords(DateTime at, {required DateTime now}) =>
    formatPastDay(at, now: now) ?? formatClockTime(at);

/// When a download should end, after `Ready around`: `21:10` today,
/// `tomorrow 09:10`, then the weekday.
String aroundWords(DateTime at, {required DateTime now}) {
  final days = calendarDaysBetween(now, at);
  if (days <= 0) return formatClockTime(at);
  if (days == 1) return 'tomorrow ${formatClockTime(at)}';
  return weekdayName(at);
}
