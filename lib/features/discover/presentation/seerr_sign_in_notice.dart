import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a step of signing in to Seerr with an account can say, beside the
/// form: why it stopped, and what to do next.
///
/// The words of the sign-in, in one place. Each comes from what answered
/// (the server's own refusal through `classifySeerrRefusal`, the transport's
/// classification) and never from the exception's text, and none carries the
/// password, the Plex token or the session.
enum SeerrSignInNoticeKind {
  /// Nothing replied at the address. Red.
  didNotAnswer,

  /// Something answered, and it is not Seerr.
  notSeerr,

  /// The server is still in its first setup: never signed in to.
  notSetUp,

  /// Every way of signing in is off.
  turnedOff,

  /// An `http://` address off the local network, before a password goes.
  notEncrypted,

  /// `/auth/local` refused the email and password.
  wrongEmailOrPassword,

  /// Jellyfin or Emby refused the username and password.
  wrongUsernameOrPassword,

  /// The account is real and may not sign in here.
  accountNotAllowed,

  /// Seerr could not reach its own Jellyfin or Emby.
  mediaServerUnreachable,

  /// Seerr could not check the Plex account with plex.tv.
  plexCheckFailed,

  /// The way chosen was turned off since the methods were read.
  methodTurnedOff,

  /// The saved account's session ended: sign in again.
  signedOut,

  /// plex.tv did not answer this device.
  plexDidNotAnswer,

  /// The Plex page was not approved in time, or the person cancelled.
  plexTimedOut,

  /// The Quick Connect code was not approved in time.
  codeExpired,

  /// Anything else, in the classification's own words.
  other,
}

@immutable
class SeerrSignInNotice {
  const SeerrSignInNotice._(
    this.kind, {
    required this.tone,
    required this.title,
    this.sentence,
    this.retryHelps = false,
  });

  /// Why reading the server's sign-in methods stopped, from [error], for the
  /// address [url].
  factory SeerrSignInNotice.ofServerRead(Object error, {required String url}) {
    final host = _hostOf(url);
    final reason = classifyConnectionFailure(error);
    if (failureDidNotAnswer(reason)) {
      return SeerrSignInNotice._(
        SeerrSignInNoticeKind.didNotAnswer,
        tone: StatusTone.error,
        title: 'Seerr did not answer',
        sentence: 'Nothing replied at $host from this device.',
        retryHelps: true,
      );
    }
    if (_answeredAsSomethingElse(error)) {
      return SeerrSignInNotice._(
        SeerrSignInNoticeKind.notSeerr,
        tone: StatusTone.warning,
        title: "Something answered at $host, but it isn't Seerr",
      );
    }
    return SeerrSignInNotice._other(error);
  }

  /// What a server whose methods were read says, when there is nothing to
  /// sign in with; null when there is.
  static SeerrSignInNotice? ofMethods(SeerrSignInMethods methods) =>
      switch (methods.state) {
        SeerrSignInState.notSetUp => notSetUp,
        SeerrSignInState.turnedOff => turnedOff,
        SeerrSignInState.open => null,
      };

  /// Why signing in with [method] stopped, from [error].
  factory SeerrSignInNotice.ofSignIn(
    Object error, {
    required SeerrSignInMethod method,
  }) {
    final mediaServer = method == SeerrSignInMethod.emby ? 'Emby' : 'Jellyfin';
    return switch (seerrRefusalOf(error)) {
      SeerrRefusal.wrongEmailOrPassword => const SeerrSignInNotice._(
        SeerrSignInNoticeKind.wrongEmailOrPassword,
        tone: StatusTone.warning,
        title: "That email and password didn't work",
        sentence: 'Check them and sign in again.',
      ),
      SeerrRefusal.wrongUsernameOrPassword => SeerrSignInNotice._(
        SeerrSignInNoticeKind.wrongUsernameOrPassword,
        tone: StatusTone.warning,
        title: "That username and password didn't work",
        sentence: 'Use the ones you watch $mediaServer with.',
      ),
      SeerrRefusal.accountNotAllowed => const SeerrSignInNotice._(
        SeerrSignInNoticeKind.accountNotAllowed,
        tone: StatusTone.warning,
        title: "This account can't sign in here yet",
        sentence: 'Ask whoever runs the server to add you.',
      ),
      SeerrRefusal.mediaServerUnreachable => SeerrSignInNotice._(
        SeerrSignInNoticeKind.mediaServerUnreachable,
        tone: StatusTone.warning,
        title: "The server could not reach $mediaServer",
        sentence: 'It may be back in a moment.',
        retryHelps: true,
      ),
      SeerrRefusal.plexCheckFailed => const SeerrSignInNotice._(
        SeerrSignInNoticeKind.plexCheckFailed,
        tone: StatusTone.warning,
        title: "The server could not check your Plex account",
        sentence: 'It may be back in a moment.',
        retryHelps: true,
      ),
      SeerrRefusal.signInTurnedOff => methodTurnedOff,
      SeerrRefusal.serverNotSetUp => notSetUp,
      _ => SeerrSignInNotice._other(error),
    };
  }

  /// The words the classification has for [error], naming Seerr.
  factory SeerrSignInNotice._other(Object error) {
    final reason = classifyConnectionFailure(error);
    return SeerrSignInNotice._(
      SeerrSignInNoticeKind.other,
      tone: failureTone(reason),
      title: failureHeadline(
        reason,
        subject: 'Seerr',
        gateway: accessGatewayOf(error),
      ),
      sentence: connectionFailureSentence(
        error,
        remedyBeside: true,
        subject: 'Seerr',
      ),
      retryHelps: failureRetryHelps(reason),
    );
  }

  /// The saved account of a server called [title] is signed out: the words
  /// the classification has for an ended session, blue.
  factory SeerrSignInNotice.signedOut(String title) => SeerrSignInNotice._(
    SeerrSignInNoticeKind.signedOut,
    tone: failureTone(ServiceFailureReason.sessionEnded),
    title: failureHeadline(ServiceFailureReason.sessionEnded, subject: title),
    sentence: connectionFailureSentence(
      const ClassifiedFailure(ServiceFailureReason.sessionEnded),
    ),
  );

  /// The same, as the requester reads it: no server's name, and what signing
  /// in again is for.
  static final youWereSignedOut = SeerrSignInNotice._(
    SeerrSignInNoticeKind.signedOut,
    tone: failureTone(ServiceFailureReason.sessionEnded),
    title: Lexicon.youWereSignedOut,
    sentence: Lexicon.signInToKeepAsking,
  );

  static const notSetUp = SeerrSignInNotice._(
    SeerrSignInNoticeKind.notSetUp,
    tone: StatusTone.info,
    title: "This Seerr isn't set up yet",
    sentence:
        'Whoever runs it needs to finish setting it up before anyone can '
        'sign in.',
  );

  static const turnedOff = SeerrSignInNotice._(
    SeerrSignInNoticeKind.turnedOff,
    tone: StatusTone.info,
    title: 'This Seerr has sign-in turned off',
    sentence:
        'Whoever runs it can turn on sign-in with Plex, Jellyfin or an email '
        "account. If it's your server, set it up with its API key.",
  );

  static const notEncrypted = SeerrSignInNotice._(
    SeerrSignInNoticeKind.notEncrypted,
    tone: StatusTone.warning,
    title: "This address isn't encrypted",
    sentence: 'Anyone between you and the server could read your password.',
  );

  static const methodTurnedOff = SeerrSignInNotice._(
    SeerrSignInNoticeKind.methodTurnedOff,
    tone: StatusTone.info,
    title: 'This way of signing in was just turned off',
  );

  static const plexDidNotAnswer = SeerrSignInNotice._(
    SeerrSignInNoticeKind.plexDidNotAnswer,
    tone: StatusTone.error,
    title: 'Plex did not answer',
    sentence: "Cupola could not reach plex.tv from this device.",
    retryHelps: true,
  );

  static const plexTimedOut = SeerrSignInNotice._(
    SeerrSignInNoticeKind.plexTimedOut,
    tone: StatusTone.info,
    title: 'The Plex sign-in timed out',
  );

  static const codeExpired = SeerrSignInNotice._(
    SeerrSignInNoticeKind.codeExpired,
    tone: StatusTone.info,
    title: 'The code expired',
  );

  final SeerrSignInNoticeKind kind;

  /// Red only when nothing answered; blue for a step that is the person's or
  /// the operator's, never a fault; amber for a fault.
  final StatusTone tone;

  final String title;
  final String? sentence;

  /// Whether sending the same request again can still change the answer.
  final bool retryHelps;

  /// The whole notice as one sentence, for a screen reader.
  String get spoken => sentence == null ? '$title.' : '$title. $sentence';

  @override
  bool operator ==(Object other) =>
      other is SeerrSignInNotice &&
      other.kind == kind &&
      other.tone == tone &&
      other.title == title &&
      other.sentence == sentence &&
      other.retryHelps == retryHelps;

  @override
  int get hashCode => Object.hash(kind, tone, title, sentence, retryHelps);

  @override
  String toString() => 'SeerrSignInNotice(${kind.name})';
}

/// Whether a password sent to [url] would cross a network in the clear: an
/// `http://` address off the local network, the same verdict the address
/// field warns on (`UrlUtils.cleartextWarning`).
///
/// Before a password goes there, [SeerrSignInNotice.notEncrypted] asks.
bool passwordTravelsInClear(String url) =>
    UrlUtils.cleartextWarning(UrlUtils.normalizeBaseUrl(url)) != null;

/// Whether [error] is something other than Seerr answering: another service
/// at the port, a web page, an address where Seerr's status route is not
/// (all of them [ServiceFailureReason.notFound]).
bool _answeredAsSomethingElse(Object error) =>
    classifyConnectionFailure(error) == ServiceFailureReason.notFound;

String _hostOf(String url) =>
    UrlUtils.hostInProse(ServiceKey.seerr.extractHost(url) ?? url);
