/// What the Nginx Proxy Manager Overview reads, and the pure functions that
/// shape it.
///
/// Nothing here fetches anything new. Every region is folded from the three
/// documents `npm_provider.dart` already holds — `/api/nginx/proxy-hosts`,
/// `/api/nginx/certificates` and the client-side upstream probe that rides the
/// first of them — so opening Overview costs no round trip the service home was
/// not already paying for.
///
/// Every windowing rule is a top-level pure function taking an explicit `now`,
/// so a certificate that expires at midnight is a unit test rather than a
/// screenshot taken at the right moment.
///
/// ## The one figure on this page that can lie, and how it is stopped
///
/// **The upstream probe is partial by design.** `NpmUpstreamProbe.defaultBudget`
/// is eight, a real box fronts twenty or thirty hostnames, and the unchecked
/// ones are *unmeasured* — not healthy. So `NpmUpstreamReport.downCount` is
/// "down among the eight we looked at", and stating it as "2 upstreams down"
/// with nothing else would turn fifteen unknowns into fifteen green ticks.
///
/// Three rules follow, and they are the reason this file exists rather than the
/// fold living in the widget:
///
///  * every subtitle that reports anything derived from the probe carries
///    [NpmUpstreamReport.coverage] beside it — see [npmAttentionSubtitle] and
///    [npmProxyHostsSubtitle];
///  * a host with no verdict contributes **no clause at all** to its row, never
///    a reassuring one ([npmUpstreamClause] answers null for
///    [NpmUpstream.unchecked]);
///  * the fault census is the length of the full list, and the cap is applied
///    at draw time by the widget. A count taken after the cap is the defect
///    this batch keeps finding: four rows reported as four faults when there
///    were nine.
///
/// ## Tone, in this service's vocabulary
///
/// Amber is a **fault**: nginx refused a host's configuration, nothing is
/// listening where a host forwards, a certificate is inside its renewal window
/// and has not renewed, a certificate has lapsed. Neutral is the **backlog**: a
/// host the user switched off is doing exactly what they asked, and painting it
/// amber is the single commonest way the five-arm rule breaks. Red appears
/// nowhere in this file — red is an NPM that did not answer, which the page's
/// unreachable band says once for the whole screen. An *expired* certificate is
/// emphatically not red: the server answered, it answered with bad news.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Fault rows the Needs attention region draws before its header's census is
/// the only place the rest are reported.
const int npmAttentionPreviewLimit = 4;

/// Rows in the Proxy hosts preview.
const int npmProxyHostPreviewLimit = 5;

/// Rows in the Certificates preview.
const int npmCertificatePreviewLimit = 4;

// ─── Vocabulary ─────────────────────────────────────────────────────────────

/// `Let's Encrypt` or `custom`, spelled the way NPM's own UI spells them.
///
/// The distinction is not cosmetic: only a Let's Encrypt certificate renews by
/// itself, so only one of the two can be *failing* to renew. An uploaded
/// certificate short-dated inside thirty days is a job for a human and says
/// nothing about certbot.
String npmCertificateProviderLabel(NpmCertificate certificate) =>
    certificate.isLetsEncrypt ? "Let's Encrypt" : 'custom';

/// `9 days left`, `expired 3 days ago`, `expired today`, or `—`.
///
/// The em dash is for a certificate NPM handed over **without a parseable
/// `expires_on`**. It is not "0 days", which would read as "expires today" —
/// the one reading a user would act on, over a question that was never
/// answered.
///
/// Which side of the line a certificate is on is asked of
/// [NpmCertificate.hasExpired] and never of the day count, because the count
/// truncates: a certificate that lapsed six hours ago answers 0, and `0` on the
/// future branch prints `expires today` about something every browser is
/// already refusing. The window is a full day wide.
String npmCertificateExpiryLabel(NpmCertificate certificate, DateTime now) {
  final days = certificate.daysUntilExpiry(now);
  if (days == null) return '—';
  if (certificate.hasExpired(now)) {
    final ago = -days;
    // Under twenty-four hours on the wrong side of the date: still expired,
    // and saying "0 days ago" would spend the sentence denying it.
    if (ago <= 0) return 'expired today';
    return ago == 1 ? 'expired 1 day ago' : 'expired $ago days ago';
  }
  if (days == 0) return 'expires today';
  return days == 1 ? '1 day left' : '$days days left';
}

/// The clause a proxy host's row adds about what the probe found, or **null**
/// when nobody looked.
///
/// Null is load-bearing. A host outside the budget has not been measured, and a
/// row that quietly said nothing where a verdict would have gone reads as a
/// verdict of "fine" to anyone scanning a column.
String? npmUpstreamClause(NpmUpstream upstream) => switch (upstream) {
  NpmUpstream.answering => 'upstream answering',
  NpmUpstream.down => 'upstream down',
  NpmUpstream.unchecked => null,
};

// ─── Needs attention ────────────────────────────────────────────────────────

/// The four conditions this page can derive today, **worst first**.
///
/// The declaration order is load-bearing: [npmAttentionItems] sorts on it, and
/// the preview cap means the tail is reported only as a number. What is at the
/// top has to be what a person opened the screen for.
///
///  * a configuration nginx refused means the hostname is not being served at
///    all — the site is simply gone;
///  * an expired certificate means every browser refuses it, which is the same
///    outage with a different error page;
///  * a dead upstream means nginx is serving the hostname and answering 502,
///    so the domain at least exists;
///  * a certificate inside its window is a deadline, not yet an outage.
///
/// All four are [StatusTone.warning]. None is [StatusTone.error]: red on this
/// screen belongs to an NPM that did not answer, and every one of these facts
/// arrived *because* it answered.
enum NpmAttentionKind {
  /// `meta.nginx_online` is false on an enabled host — nginx would not load the
  /// configuration the last time it was asked to.
  nginxRefused(Icons.error_outline_rounded),

  /// The certificate's `expires_on` is in the past.
  certificateExpired(Icons.gpp_bad_rounded),

  /// The client-side probe opened a socket at the forward target and nothing
  /// accepted it.
  upstreamDown(Icons.cloud_off_rounded),

  /// Inside twenty-one days, and still here.
  certificateExpiring(Icons.lock_clock_rounded);

  const NpmAttentionKind(this.icon);

  final IconData icon;

  /// Amber for all four. See the enum's own doc for why there is no red arm.
  StatusTone get tone => StatusTone.warning;
}

/// One row of Needs attention: what is wrong, to what, and the evidence.
@immutable
class NpmAttentionItem {
  const NpmAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
  });

  final NpmAttentionKind kind;

  /// The fault and its subject: `nginx refused · photos.example.net`.
  final String headline;

  /// The evidence: nginx's own message, the forward target, how long is left.
  /// Empty when the record carried none.
  final String detail;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as one sentence, with the layout's `·` turned back into commas —
  /// `·` is decoration, and a screen reader either names it or drops it
  /// depending on the user's punctuation setting.
  String get spoken =>
      joinSpokenParts([spokenFromDotted(headline), spokenFromDotted(detail)]);
}

/// Everything wrong that this client can prove, worst first.
///
/// Returns the **whole** census rather than a page of it. The cap belongs to
/// the widget, so the header can print a number that is the truth and the rows
/// below it can be a sample — the other way round is the defect where nine
/// broken hosts are reported as four.
///
/// [upstreams] defaults to a report that checked nothing, which is exactly the
/// state the screen is in for the first second or two: hosts and certificates
/// have landed and the probe has not. Every fault the server itself declared is
/// already drawn by then; the upstream rows join when the sockets come back.
List<NpmAttentionItem> npmAttentionItems({
  required List<NpmProxyHost> hosts,
  required List<NpmCertificate> certificates,
  required DateTime now,
  NpmUpstreamReport? upstreams,
}) {
  final report = upstreams ?? NpmUpstreamReport.empty;
  final items = <NpmAttentionItem>[];

  for (final host in hosts) {
    // `hasConfigError` is already `enabled && !configLoaded`: a host the user
    // switched off is *meant* not to be served, and nginx not holding a
    // configuration for it is the consequence of that choice rather than a
    // fault. Backlog, and backlog does not appear here at all.
    if (host.hasConfigError) {
      items.add(
        NpmAttentionItem(
          kind: NpmAttentionKind.nginxRefused,
          headline: 'nginx refused · ${host.primaryDomain}',
          // NPM's own `nginx: [emerg] …` line when it kept one, verbatim: it
          // names the directive and the line number, which is the whole
          // difference between "your config is broken" and a fix. The forward
          // target is the fallback, because a row with no second line reads as
          // a fault with no evidence.
          detail: host.errorText.trim().isNotEmpty
              ? host.errorText.trim()
              : host.target,
        ),
      );
    }
  }

  for (final certificate in certificates) {
    // No date, no claim. A certificate NPM described without an expiry is not
    // an expiring one, and guessing either way here would put a fault on the
    // screen that nothing can confirm or clear.
    if (certificate.daysUntilExpiry(now) == null) continue;
    // `hasExpired`, never `days < 0`: the day count truncates, so for the
    // twenty-four hours after a certificate lapses it reads 0 and this arm
    // would never fire — the lapse would instead fall through to the expiring
    // branch below and be ranked as a deadline, the lowest arm of the enum,
    // where a preview of four can push it off the screen entirely.
    if (certificate.hasExpired(now)) {
      items.add(
        NpmAttentionItem(
          kind: NpmAttentionKind.certificateExpired,
          headline: 'Certificate expired · ${certificate.displayName}',
          detail: joinDisplayParts([
            npmCertificateProviderLabel(certificate),
            npmCertificateExpiryLabel(certificate, now),
          ]),
        ),
      );
    }
  }

  for (final host in hosts) {
    if (report.forHost(host.id) != NpmUpstream.down) continue;
    items.add(
      NpmAttentionItem(
        kind: NpmAttentionKind.upstreamDown,
        headline: 'Upstream down · ${host.primaryDomain}',
        // The probe runs from **this device**, and the commonest reason it
        // fails is a forward host that only resolves on the server's own
        // network (`immich.lan`, a Docker service name). Saying where the
        // measurement was taken is not a hedge — without it the row asserts an
        // outage that may not exist.
        detail: joinDisplayParts([
          host.target,
          'not reachable from this device',
        ]),
      ),
    );
  }

  // One row for the set rather than one per certificate. Two certificates
  // expiring the same week is one errand — renewal is not working — and four
  // rows of it would push the hostname that is actually down off a preview of
  // four.
  final expiring =
      certificates
          .where(
            (certificate) =>
                !certificate.hasExpired(now) && certificate.isExpiringSoon(now),
          )
          .toList(growable: false)
        ..sort(
          (a, b) => (a.daysUntilExpiry(now) ?? 0).compareTo(
            b.daysUntilExpiry(now) ?? 0,
          ),
        );

  if (expiring.isNotEmpty) {
    final soonest = expiring.first;
    // `renewalNotCompleting` is a derived fact with its reasoning in
    // `npm_models.dart`: certbot renews from thirty days out, so a Let's
    // Encrypt certificate still short-dated inside that window is one whose
    // renewal is not completing. The copy stays on the safe side of the
    // inference — "renewal has not completed", never "renewal failed" — because
    // the window is the only evidence there is. NPM keeps the actual error in
    // `/api/audit-log`, which this client does not call.
    final stalled = expiring.any((c) => c.renewalNotCompleting(now));
    items.add(
      NpmAttentionItem(
        kind: NpmAttentionKind.certificateExpiring,
        headline: expiring.length == 1
            ? '1 certificate expiring · ${soonest.displayName}'
            : '${expiring.length} certificates expiring',
        detail: joinDisplayParts([
          npmCertificateExpiryLabel(soonest, now),
          if (expiring.length > 1)
            expiring.map((c) => c.displayName).take(3).join(' · '),
          if (stalled) 'renewal has not completed',
        ]),
      ),
    );
  }

  items.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return List.unmodifiable(items);
}

/// The Needs attention header: the census, then how much of the set was
/// actually looked at.
///
/// `—` while the documents are in flight or after they failed, never `0`: a
/// zero here says "nothing is wrong", which is precisely the reading a user
/// would act on and precisely the one nobody has established.
///
/// The coverage rides along **even when the count is zero**, and especially
/// then: `0 · reachability checked for 8 of 23 enabled` is an honest all-clear,
/// while a
/// bare `0` over a probe that looked at a third of the table is not.
String npmAttentionSubtitle(
  List<NpmAttentionItem>? items,
  NpmUpstreamReport? upstreams,
) {
  if (items == null) return '—';
  return joinDisplayParts(['${items.length}', upstreams?.coverage]);
}

/// Hosts, certificates and whatever the probe has managed so far.
///
/// The probe is read as an [AsyncValue] rather than awaited, and that is the
/// difference between a region that draws in one frame and one that waits on up
/// to three socket timeouts. Everything the server itself declared — refused
/// configurations, expiry dates — is already in hand; watching the report means
/// this provider simply recomputes when the sockets answer, and the upstream
/// rows appear then.
///
/// No `retry: noProviderRetry`: neither source carries it. (If one ever does,
/// this derivation must carry it too, or the retry the source refused comes
/// back in through the back door.)
final npmOverviewAttentionProvider =
    FutureProvider.autoDispose<List<NpmAttentionItem>>((ref) async {
      final hosts = await ref.watch(npmProxyHostsProvider.future);
      final certificates = await ref.watch(npmCertificatesProvider.future);
      // `.asData` and not `.future`: a probe still out, or one that threw, is
      // not a reason to hold back four faults NPM already told us about.
      final upstreams = ref.watch(npmUpstreamReportProvider).asData?.value;
      return npmAttentionItems(
        hosts: hosts,
        certificates: certificates,
        now: DateTime.now(),
        upstreams: upstreams,
      );
    });

// ─── Proxy hosts ────────────────────────────────────────────────────────────

/// One proxy host resolved into the line the preview draws.
@immutable
class NpmProxyHostRow {
  const NpmProxyHostRow({required this.host, required this.upstream});

  final NpmProxyHost host;
  final NpmUpstream upstream;

  bool get _isDown => upstream == NpmUpstream.down;

  /// What nginx is doing with this hostname, in words rather than in colour.
  ///
  /// Deliberately **not** "Online". `meta.nginx_online` is the verdict of the
  /// last configuration attempt and nothing on the server polls it — see
  /// [NpmProxyHost.configLoaded] — so "Online" would promise uptime monitoring
  /// this app does not do. "serving" says what is actually known: nginx holds a
  /// configuration for this hostname and is answering on it.
  String get stateLabel {
    if (host.hasConfigError) return 'nginx refused this configuration';
    if (!host.enabled) return 'disabled';
    return 'serving';
  }

  /// Amber for a fault, neutral for a host the user switched off.
  ///
  /// A disabled host is **backlog**: it is doing what it was told. Amber there
  /// would put the alarm colour on the one thing working as intended and drown
  /// the row above it that is genuinely broken.
  StatusTone get tone {
    if (host.hasConfigError || _isDown) return StatusTone.warning;
    if (!host.enabled) return StatusTone.neutral;
    return StatusTone.success;
  }

  IconData get icon {
    if (host.hasConfigError) return Icons.error_outline_rounded;
    if (_isDown) return Icons.cloud_off_rounded;
    if (!host.enabled) return Icons.pause_circle_outline_rounded;
    return Icons.check_circle_outline_rounded;
  }

  /// `radarr.lan:7878 · serving · upstream answering · TLS · access list`.
  ///
  /// The upstream clause is absent — not "unknown", not a dash — for a host
  /// nobody probed. The section header carries the coverage, so silence here
  /// means "not measured" and the header is what says how much of the table
  /// that covers.
  String get detail => joinDisplayParts([
    host.target,
    stateLabel,
    npmUpstreamClause(upstream),
    if (host.hasCertificate) 'TLS',
    if (host.hasAccessList) 'access list',
  ]);

  String get spoken => joinSpokenParts([
    host.primaryDomain,
    spokenFromDotted(detail),
    if (_isDown) 'not reachable from this device',
  ]);
}

/// Every proxy host, worst first.
///
/// The order is the control-room order the rest of this service already uses:
/// what nginx refused, then what has no backend answering, then what is
/// serving, then what the user switched off. A preview of five that led with
/// the alphabet would routinely draw five healthy hosts on a box with a broken
/// one.
///
/// Returns the full list; the widget takes its preview off the front, so the
/// header's count and the rows can never disagree about which population they
/// describe.
List<NpmProxyHostRow> npmProxyHostRows(
  List<NpmProxyHost> hosts,
  NpmUpstreamReport? upstreams,
) {
  final report = upstreams ?? NpmUpstreamReport.empty;
  final rows = [
    for (final host in hosts)
      NpmProxyHostRow(host: host, upstream: report.forHost(host.id)),
  ];

  int rank(NpmProxyHostRow row) {
    if (row.host.hasConfigError) return 0;
    if (row._isDown) return 1;
    if (!row.host.enabled) return 3;
    return 2;
  }

  rows.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0
        ? byRank
        : a.host.primaryDomain.toLowerCase().compareTo(
            b.host.primaryDomain.toLowerCase(),
          );
  });
  return List.unmodifiable(rows);
}

/// `25 · reachability checked for 8 of 23 enabled`.
///
/// The second half is the whole reason this is a function and not an
/// interpolation at the call site. The Upstream column answers for eight rows
/// and stays silent for the rest; without the coverage line those read as
/// healthy hosts, which is the opposite of what is known about them.
///
/// **The two figures count different populations, and the sentence says so.**
/// The first is every proxy host, switched off ones included, because that is
/// what the rows below it are. The probe's total is enabled hosts only — a
/// disabled host is not being served, so its backend is not a fact about this
/// screen and no socket is opened for it. Printed as `25 · … 8 of 23` the pair
/// invites one reading, that two hosts went missing in between;
/// [NpmUpstreamReport.coverage] carries the word `enabled` so it cannot.
String npmProxyHostsSubtitle(
  List<NpmProxyHost>? hosts,
  NpmUpstreamReport? upstreams,
) {
  if (hosts == null) return '—';
  return joinDisplayParts(['${hosts.length}', upstreams?.coverage]);
}

// ─── Certificates ───────────────────────────────────────────────────────────

/// One certificate resolved into the line the preview draws.
@immutable
class NpmCertificateRow {
  const NpmCertificateRow({
    required this.certificate,
    required this.expiryLabel,
    required this.tone,
  });

  final NpmCertificate certificate;

  /// Already resolved against the `now` the fold was built with, so the row is
  /// a value and not a thing that reads the clock while it paints.
  final String expiryLabel;

  final StatusTone tone;

  IconData get icon => switch (tone) {
    StatusTone.warning => Icons.lock_clock_rounded,
    StatusTone.success => Icons.lock_outline_rounded,
    _ => Icons.help_outline_rounded,
  };

  String get detail =>
      joinDisplayParts([npmCertificateProviderLabel(certificate), expiryLabel]);

  String get spoken =>
      joinSpokenParts([certificate.displayName, spokenFromDotted(detail)]);
}

/// Every certificate, soonest to expire first.
///
/// A certificate with no parseable date sorts **last** rather than first: it is
/// not urgent, it is unknown, and putting it at the head of a list ordered by
/// urgency would assert the one thing about it that nobody knows.
List<NpmCertificateRow> npmCertificateRows(
  List<NpmCertificate> certificates,
  DateTime now,
) {
  final rows = [
    for (final certificate in certificates)
      NpmCertificateRow(
        certificate: certificate,
        expiryLabel: npmCertificateExpiryLabel(certificate, now),
        tone: _certificateTone(certificate, now),
      ),
  ];

  rows.sort((a, b) {
    final left = a.certificate.daysUntilExpiry(now);
    final right = b.certificate.daysUntilExpiry(now);
    if (left == null && right == null) {
      return a.certificate.displayName.toLowerCase().compareTo(
        b.certificate.displayName.toLowerCase(),
      );
    }
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });
  return List.unmodifiable(rows);
}

/// Amber for lapsed or lapsing, green for valid, neutral for undated.
///
/// Expired is amber and **not** red, deliberately: red is reserved for a server
/// that did not answer, and this one answered — it told us the date. Neutral
/// for a certificate with no date is the honest third arm; green there would
/// claim a validity nothing established.
StatusTone _certificateTone(NpmCertificate certificate, DateTime now) {
  if (certificate.daysUntilExpiry(now) == null) return StatusTone.neutral;
  if (certificate.hasExpired(now) || certificate.isExpiringSoon(now)) {
    return StatusTone.warning;
  }
  return StatusTone.success;
}

/// `12 · 2 expired · 1 expiring`, or `12` when nothing is due.
///
/// Every half counts the **whole** list NPM returned —
/// `/api/nginx/certificates` is not paged and takes no limit — so these are
/// totals and may be stated as such. `—` while the list is in flight or after
/// it failed.
///
/// **Lapsed and lapsing are counted apart, and worst is named first.**
/// [NpmCertificate.isExpiringSoon] has no lower bound on purpose (see its doc),
/// so folding both into one `N expiring` would let this header say `2 expiring`
/// about two certificates that are already dead — while the Needs attention
/// region three inches above it says `Certificate expired`. One screen stating
/// one fact at two severities, with the header stating the softer one, is the
/// figure that lies.
String npmCertificatesSubtitle(
  List<NpmCertificate>? certificates,
  DateTime now,
) {
  if (certificates == null) return '—';
  final expired = certificates.where((c) => c.hasExpired(now)).length;
  final expiring = certificates
      .where((c) => !c.hasExpired(now) && c.isExpiringSoon(now))
      .length;
  return joinDisplayParts([
    '${certificates.length}',
    if (expired > 0) '$expired expired',
    if (expiring > 0) '$expiring expiring',
  ]);
}
