import 'package:flutter/foundation.dart' show TargetPlatform;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How far a search on this instance can travel once the sheet is left.
///
/// Four values rather than a bool, because "does it survive backgrounding"
/// has three different *reasons* to say no, and only one of them is a platform
/// fact the user can do nothing about.
enum ReleaseSearchReach {
  /// The native `URLSession`/WorkManager path (iOS, Android). Runs on even
  /// if the app is suspended or killed (Android's own ceiling aside), which
  /// is the promise the handoff offer has always made on these platforms.
  beyondTheApp,

  /// The foreground path, for a reason that is simply true of the platform:
  /// desktop does not suspend apps, so there is nothing here to survive.
  whileOpen,

  /// The foreground path, because the user has switched Background search off.
  ///
  /// The only one of these four the user can lift from inside the app, and the
  /// only one that is a *choice* rather than a fact: which is why it names the
  /// setting wherever it is explained. Off is the default: handing a search to
  /// the OS means handing it the arr admin key in writing (see
  /// [ReleaseSearchSettings.backgroundEnabled]), so the capability is offered
  /// rather than assumed.
  whileOpenSwitchedOff,

  /// The foreground path, for a reason that is true of *this instance*: its
  /// origin has a self-signed certificate trusted only inside Cupola
  /// (ADR-6), and the native background task validates TLS against the
  /// platform trust store with no hook for an in-app pin: it cannot see
  /// that trust at all. The only way back to [beyondTheApp] is installing
  /// the certificate on the device itself, not anything Cupola can do.
  whileOpenTrustedCert,

  /// The foreground path, for a different fact about *this instance*: it is
  /// reached over cleartext `http://`, and the background task would carry a
  /// full-privilege arr API key into a stack that cannot be told to refuse a
  /// redirect.
  ///
  /// The threat model is the whole reason this value exists, so it is written
  /// down rather than left implied. Every HTTP stack in play (`dart:io`,
  /// Android's `HttpURLConnection`, iOS's `URLSession`) strips `Authorization`
  /// and `Cookie` when a redirect crosses origins, but `X-Api-Key` is a custom
  /// header and is replayed verbatim to whatever the redirect names. The
  /// in-app path answers that with `SameOriginRedirectInterceptor`; the native
  /// path has no equivalent and no setting that would turn redirects off, so
  /// on that path a redirect is a credential handover.
  ///
  /// What that is *not* is a reason to distrust the user's own instance: an
  /// instance that wanted the key already has it, so a redirect it sends
  /// teaches an attacker nothing new. The genuinely new exposure is someone
  /// **on the path** injecting the redirect, and that requires cleartext:
  /// over TLS the response cannot be forged. So the line is drawn exactly
  /// there: `https` keeps the background reach, `http://` falls back to the
  /// transport that can refuse the redirect. Switching the instance to https
  /// is what restores it.
  whileOpenCleartext,
}

/// Resolves the reach for a search against [service], given its saved
/// [baseUrl], whether that origin is pinned in-app, and whether the user has
/// switched background search on.
///
/// **The order of the four answers is the design.** The platform comes first,
/// because on desktop there is no background path to switch on and naming the
/// setting there would invent a missing capability. [backgroundEnabled] comes
/// next, because when the answer is "you turned it off" that is both the true
/// cause and the only one the user can act on in a tap: a certificate or a
/// scheme only starts mattering once the capability is wanted. The two
/// per-instance facts come last, in the order that puts the permanent one
/// before the fixable one.
///
/// [platform] is injectable for the same reason [backgroundSearchSupported]
/// takes one: `flutter_test` reports [TargetPlatform.android] for
/// `defaultTargetPlatform`, so a check on that would send every widget test
/// down a native path with no plugin behind it. Omit it in production and
/// the real host answers, exactly as [backgroundSearchSupported] does by
/// default.
///
/// [backgroundEnabled] is required rather than defaulted: a default would let a
/// new call site quietly opt a user into handing their API key to the OS, which
/// is exactly the decision this parameter exists to keep explicit.
ReleaseSearchReach reachFor(
  ServiceKey service, {
  required String baseUrl,
  required bool certTrustedInApp,
  required bool backgroundEnabled,
  TargetPlatform? platform,
}) {
  if (!backgroundSearchSupported(platform: platform)) {
    return ReleaseSearchReach.whileOpen;
  }
  if (!backgroundEnabled) return ReleaseSearchReach.whileOpenSwitchedOff;
  if (certTrustedInApp) return ReleaseSearchReach.whileOpenTrustedCert;
  // `isSecureScheme` rather than a bare `== 'https'`, so this reads the URL the
  // same way every client does: only an explicit `http://` is cleartext, and a
  // scheme-less host is the https `UrlUtils.normalizeBaseUrl` will actually
  // dial. One definition of "this instance is cleartext" across the app.
  if (!UrlUtils.isSecureScheme(baseUrl)) {
    return ReleaseSearchReach.whileOpenCleartext;
  }
  return ReleaseSearchReach.beyondTheApp;
}
