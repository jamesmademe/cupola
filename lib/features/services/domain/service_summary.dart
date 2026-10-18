import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What the probe found, in the three states a failure can mean.
///
/// Two used to be one: every error the probe caught was `offline`, so a Radarr
/// that answered 401 was painted exactly like one that was switched off: red,
/// "unreachable", named in the band that says what did not answer. A refusal
/// is an answer. It is the service speaking, and the fix is in the form.
enum ServiceSummaryStatus {
  /// Answered the probe, with the credential accepted.
  online,

  /// Answered, and the answer was a refusal or a fault: a refused key, a 5xx,
  /// a reply nobody can read, a timeout after connecting. Amber, with a remedy.
  /// [ServiceSummary.failure] says which.
  fault,

  /// Nothing answered. Red, and the only red.
  offline,

  /// Not asked: the app is away from home and the connection has no address
  /// away ([ServiceFailureReason.onlyAtHome]). Neutral: not answering, not
  /// silent, not a fault, and counted apart (`7 of 7 answering · 6 only at
  /// home`).
  onlyAtHome,

  /// Not asked: the connection is saved without what it needs to be asked
  /// (its key, or its password). Neutral, like [onlyAtHome]: nothing answered
  /// and nothing was silent, so it is neither answering nor dark, and the
  /// service is read off its other connections.
  notSetUp,
}

/// Whether a configured service is answering, and what it says it is.
///
/// ## What this deliberately no longer carries
///
/// It used to hold an `itemCount` and an `itemLabel`, which composed into a
/// `countLabel`: the "76 movies" line on the old status card. Producing that one
/// string cost a **full library fetch per service**: `getMovies()`,
/// `getSeries()`, `getArtists()`, `getTorrents()`, `getAuthors()`, `getPools()`,
/// `fetchStacks()`, `getIndexers()`, one after another, none of them shared with
/// the providers the rest of the screen already used.
///
/// Two things made that indefensible. The figure was the *least* live thing on a
/// control-room screen: a library total does not change from one week to the
/// next, and the stack matrix that replaced the card shows a genuinely live
/// metric instead, resolved from `serviceKpiProvider`, which reads providers the
/// screen was loading anyway. So the counts became invisible while still being
/// paid for, thirteen times, on every open and every pull-to-refresh.
///
/// This object is now what its name says: reachability plus identity.
class ServiceSummary {
  final ServiceKey service;
  final ServiceSummaryStatus status;
  final String host;

  /// Reported version, when the service gave one.
  ///
  /// A by-product rather than a fetch of its own: the version endpoint *is* the
  /// reachability probe, so this value is already in hand by the time [status] is
  /// known.
  final String? version;

  /// Why the probe failed, classified, when it did. Null while online, for a
  /// connection not set up ([ServiceSummaryStatus.notSetUp]), and on a
  /// summary built for a connection removed mid-flight, which reads as
  /// offline.
  final ClassifiedFailure? failure;

  const ServiceSummary({
    required this.service,
    required this.status,
    required this.host,
    required this.version,
    this.failure,
  });

  /// The summary of a probe that threw [error], in the state its
  /// classification means: [ServiceSummaryStatus.offline] when nothing
  /// answered, [ServiceSummaryStatus.fault] for everything that did.
  factory ServiceSummary.failed(
    ServiceKey service, {
    required String host,
    required Object error,
  }) {
    final failure = ClassifiedFailure.of(error);
    return ServiceSummary(
      service: service,
      status: failureDidNotAnswer(failure.reason)
          ? ServiceSummaryStatus.offline
          : ServiceSummaryStatus.fault,
      host: host,
      version: null,
      failure: failure,
    );
  }

  /// Answered, and nothing is wrong.
  bool get isOnline => status == ServiceSummaryStatus.online;

  /// Nothing answered: the red state.
  bool get didNotAnswer => status == ServiceSummaryStatus.offline;

  /// Not asked, away from home: the neutral state.
  bool get isOnlyAtHome => status == ServiceSummaryStatus.onlyAtHome;

  /// Saved without what it needs to be asked: never asked, neutral.
  bool get isNotSetUp => status == ServiceSummaryStatus.notSetUp;

  /// Answered with a refusal or a fault: amber.
  bool get isFault => status == ServiceSummaryStatus.fault;

  /// Reached, and never replied in time: amber like a fault, and no more an
  /// answer than silence is. The header does not count it as answering.
  bool get isStuck =>
      isFault && failure?.reason == ServiceFailureReason.timeout;

  /// The reason the probe failed, as the words and the tone read it. An
  /// offline summary with no classified failure did not answer.
  ServiceFailureReason? get failureReason => switch (status) {
    ServiceSummaryStatus.online => null,
    ServiceSummaryStatus.offline =>
      failure?.reason ?? ServiceFailureReason.unreachable,
    ServiceSummaryStatus.fault =>
      failure?.reason ?? ServiceFailureReason.unknown,
    ServiceSummaryStatus.onlyAtHome => ServiceFailureReason.onlyAtHome,
    ServiceSummaryStatus.notSetUp => null,
  };

  String get versionLabel {
    final serviceVersion = version?.trim();
    if (serviceVersion != null && serviceVersion.isNotEmpty) {
      return serviceVersion.startsWith('v')
          ? serviceVersion
          : 'v$serviceVersion';
    }

    return '${service.apiVersion} API';
  }
}
