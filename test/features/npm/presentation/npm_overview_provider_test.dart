import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_overview_provider.dart';

/// Every rule on the NPM Overview is a pure function taking an explicit `now`,
/// so a certificate that lapses at midnight is a test rather than a screenshot
/// taken at the right moment.
void main() {
  // A fixed instant, so "nine days out" means the same thing in June and in
  // the week the clocks change.
  final now = DateTime(2026, 9, 17, 12);

  group('npmCertificateExpiryLabel', () {
    test('a certificate NPM dated reads its days, singular at one', () {
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(days: 9)),
          now,
        ),
        '9 days left',
      );
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(days: 1, hours: 2)),
          now,
        ),
        '1 day left',
      );
    });

    test('a lapsed certificate says how long ago, not a negative number', () {
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(days: -3)),
          now,
        ),
        'expired 3 days ago',
      );
    });

    test('a certificate NPM dated but did not date reads an em dash, not 0', () {
      // `0 days` would render as "expires today" — the one reading a user would
      // act on, over a question the server never answered.
      expect(npmCertificateExpiryLabel(_cert(expiresOn: null), now), '—');
    });

    test('a certificate that lapsed hours ago is expired, not due today', () {
      // `daysUntilExpiry` truncates toward zero, so six hours past the date it
      // answers 0 — and 0 on the future branch reads "expires today", a
      // deadline, about a certificate every browser is already refusing. The
      // window is a full day wide and it is exactly the day someone opens the
      // app.
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(hours: -6)),
          now,
        ),
        'expired today',
      );
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(hours: -30)),
          now,
        ),
        'expired 1 day ago',
      );
    });

    test('the boundary between today and tomorrow is whole days', () {
      // `daysUntilExpiry` truncates, so anything under 24 h is day zero.
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(hours: 23)),
          now,
        ),
        'expires today',
      );
      expect(
        npmCertificateExpiryLabel(
          _cert(expiresIn: const Duration(hours: 25)),
          now,
        ),
        '1 day left',
      );
    });
  });

  group('npmUpstreamClause', () {
    test('a host nobody probed contributes no clause at all', () {
      // Null, never "unknown" and never nothing-that-reads-as-fine: the section
      // header carries the coverage, and silence in the row means unmeasured.
      expect(npmUpstreamClause(NpmUpstream.unchecked), isNull);
      // What was seen, and from where: never that the upstream is down.
      expect(
        npmUpstreamClause(NpmUpstream.down),
        'not reachable from this device',
      );
      expect(npmUpstreamClause(NpmUpstream.answering), 'upstream answering');
    });
  });

  group('npmAttentionItems', () {
    test('a refused configuration is a fault and quotes nginx verbatim', () {
      final items = npmAttentionItems(
        hosts: [
          _host(
            id: 1,
            domain: 'photos.example.net',
            configLoaded: false,
            errorText: 'nginx: [emerg] invalid port in "listen" directive',
          ),
        ],
        certificates: const [],
        now: now,
      );

      expect(items, hasLength(1));
      expect(items.single.kind, NpmAttentionKind.nginxRefused);
      expect(items.single.tone, StatusTone.warning);
      expect(items.single.headline, 'nginx refused · photos.example.net');
      expect(
        items.single.detail,
        'nginx: [emerg] invalid port in "listen" directive',
      );
    });

    test('a host the user switched off is backlog and never appears', () {
      // `hasConfigError` is `enabled && !configLoaded`. A disabled host has no
      // configuration loaded *because that is what disabled means*, and
      // painting it amber is the commonest way the five-arm rule breaks.
      final items = npmAttentionItems(
        hosts: [
          _host(
            id: 1,
            domain: 'old.example.net',
            enabled: false,
            configLoaded: false,
          ),
        ],
        certificates: const [],
        now: now,
      );

      expect(items, isEmpty);
    });

    test('a forward target this device could not reach is no fault, and '
        'says where it was looked at from', () {
      // The probe runs from this device, and from a phone away from home every
      // LAN host fails it. It used to head Needs attention with "Upstream
      // down", in amber, for hosts that were fine.
      final host = _host(
        id: 7,
        domain: 'photos.example.net',
        forwardHost: 'immich.lan',
        forwardPort: 2283,
      );
      final items = npmAttentionItems(
        hosts: [host],
        certificates: const [],
        now: now,
      );
      final row = npmProxyHostRows([
        host,
      ], _report({7: NpmUpstream.down}, checked: 8, total: 23)).single;

      expect(items, isEmpty);
      expect(
        row.detail,
        'http://immich.lan:2283 · serving · not reachable from this device',
      );
      expect(row.tone, StatusTone.success);
    });

    test('an expired certificate is amber, never red', () {
      // Red is reserved for an NPM that did not answer. This one answered — it
      // answered with bad news.
      final items = npmAttentionItems(
        hosts: const [],
        certificates: [
          _cert(name: 'seerr.example.net', expiresIn: const Duration(days: -4)),
        ],
        now: now,
      );

      expect(items.single.kind, NpmAttentionKind.certificateExpired);
      expect(items.single.tone, StatusTone.warning);
      expect(items.single.detail, "Let's Encrypt · expired 4 days ago");
    });

    test(
      'a certificate that lapsed hours ago is an expired fault, not a deadline',
      () {
        // The truncated day count says 0 here. Ranked on that it would fall
        // into the expiring arm — the enum's lowest priority, documented as "a
        // deadline, not yet an outage" — where a preview of four can push it
        // off the screen behind lesser faults.
        final items = npmAttentionItems(
          hosts: const [],
          certificates: [
            _cert(
              name: 'photos.example.net',
              expiresIn: const Duration(hours: -6),
            ),
          ],
          now: now,
        );

        expect(items.single.kind, NpmAttentionKind.certificateExpired);
        expect(
          items.single.headline,
          'Certificate expired · photos.example.net',
        );
        expect(items.single.detail, "Let's Encrypt · expired today");
        // And it is counted once, not once as expired and again as expiring.
        expect(items, hasLength(1));
      },
    );

    test('expiring certificates fold into one row that names the soonest', () {
      final items = npmAttentionItems(
        hosts: const [],
        certificates: [
          _cert(
            name: 'photos.example.net',
            expiresIn: const Duration(days: 12),
          ),
          _cert(name: 'seerr.example.net', expiresIn: const Duration(days: 9)),
          // Well outside the window: not an errand yet.
          _cert(name: 'git.example.net', expiresIn: const Duration(days: 150)),
        ],
        now: now,
      );

      expect(items.single.kind, NpmAttentionKind.certificateExpiring);
      expect(items.single.headline, '2 certificates expiring');
      // Soonest first, and the renewal inference — certbot renews from thirty
      // days out, so a Let's Encrypt certificate still short-dated inside that
      // window is one whose renewal has not completed.
      expect(
        items.single.detail,
        '9 days left · seerr.example.net · photos.example.net · '
        'renewal has not completed',
      );
    });

    test(
      'an uploaded certificate inside thirty days is not a failed renewal',
      () {
        // Nothing renews it, so nothing is failing to.
        final items = npmAttentionItems(
          hosts: const [],
          certificates: [
            _cert(
              name: 'git.example.net',
              provider: 'other',
              expiresIn: const Duration(days: 10),
            ),
          ],
          now: now,
        );

        expect(items.single.detail, isNot(contains('renewal')));
      },
    );

    test(
      'a certificate with no expiry date produces no claim in either direction',
      () {
        expect(
          npmAttentionItems(
            hosts: const [],
            certificates: [_cert(expiresOn: null)],
            now: now,
          ),
          isEmpty,
        );
      },
    );

    test(
      'faults are ordered worst first, and the whole census is returned',
      () {
        final items = npmAttentionItems(
          hosts: [
            _host(id: 1, domain: 'a.example.net'),
            _host(id: 2, domain: 'b.example.net', configLoaded: false),
          ],
          certificates: [
            _cert(name: 'soon', expiresIn: const Duration(days: 5)),
            _cert(name: 'gone', expiresIn: const Duration(days: -1)),
          ],
          now: now,
        );

        expect(items.map((i) => i.kind), [
          NpmAttentionKind.nginxRefused,
          NpmAttentionKind.certificateExpired,
          NpmAttentionKind.certificateExpiring,
        ]);
      },
    );

    test('a row speaks one sentence with the dots read as pauses', () {
      final items = npmAttentionItems(
        hosts: [
          _host(
            id: 7,
            domain: 'photos.example.net',
            forwardHost: 'immich.lan',
            forwardPort: 2283,
            configLoaded: false,
          ),
        ],
        certificates: const [],
        now: now,
      );

      expect(
        items.single.spoken,
        'nginx refused, photos.example.net, http://immich.lan:2283',
      );
    });
  });

  group('npmAttentionSubtitle', () {
    test('a source that has not answered reads an em dash, never 0', () {
      // "0" would say "nothing is wrong" over a question nobody answered, which
      // is exactly the reading a user would act on.
      expect(npmAttentionSubtitle(null), '—');
    });

    test('the census is the count alone: none of it comes from the probe', () {
      expect(npmAttentionSubtitle(const []), '0');
    });
  });

  group('npmProxyHostRows', () {
    test('refused first, then serving, then disabled; a host this device '
        'could not reach is serving', () {
      final rows = npmProxyHostRows([
        _host(id: 1, domain: 'serving.example.net'),
        _host(id: 2, domain: 'off.example.net', enabled: false),
        _host(id: 3, domain: 'down.example.net'),
        _host(id: 4, domain: 'refused.example.net', configLoaded: false),
      ], _report({3: NpmUpstream.down}, checked: 3, total: 3));

      expect(rows.map((r) => r.host.primaryDomain), [
        'refused.example.net',
        'down.example.net',
        'serving.example.net',
        // Backlog sorts last: the user asked for it to be off.
        'off.example.net',
      ]);
      expect(rows.map((r) => r.tone), [
        StatusTone.warning,
        StatusTone.success,
        StatusTone.success,
        StatusTone.neutral,
      ]);
    });

    test('a serving host says serving, never Online', () {
      // `meta.nginx_online` is the verdict of the last configuration attempt
      // and nothing polls it, so "Online" would promise uptime monitoring this
      // app does not do.
      final rows = npmProxyHostRows([_host(id: 1)], null);
      expect(rows.single.stateLabel, 'serving');
      expect(rows.single.detail, isNot(contains('Online')));
    });

    test('an unprobed host adds no upstream clause to its line', () {
      final rows = npmProxyHostRows([
        _host(
          id: 1,
          domain: 'plex.example.net',
          forwardHost: 'plex.lan',
          forwardPort: 32400,
          certificateId: 4,
          accessListId: 2,
        ),
      ], null);

      expect(
        rows.single.detail,
        'http://plex.lan:32400 · serving · TLS · access list',
      );
    });

    test(
      'the whole list comes back, so a preview can never become the count',
      () {
        final rows = npmProxyHostRows([
          for (var i = 0; i < 23; i++) _host(id: i, domain: 'h$i.example.net'),
        ], null);
        expect(rows, hasLength(23));
      },
    );
  });

  group('npmProxyHostsSubtitle', () {
    test('the coverage is printed beside the count', () {
      expect(
        npmProxyHostsSubtitle([
          for (var i = 0; i < 23; i++) _host(id: i),
        ], _report(const {}, checked: 8, total: 23)),
        '23 · 8 of 23 enabled checked from this device',
      );
    });

    test('the coverage names the population it counted, and it is narrower', () {
      // 25 hosts, two of them switched off, so the probe had 23 to look at and
      // reached 8. `25 · 8 of 23 checked from this device` would read as two
      // hosts going missing between the two figures; the word `enabled` is what
      // stops the pair lying.
      expect(
        npmProxyHostsSubtitle([
          for (var i = 0; i < 23; i++) _host(id: i),
          _host(id: 23, enabled: false),
          _host(id: 24, enabled: false),
        ], _report(const {}, checked: 8, total: 23)),
        '25 · 8 of 23 enabled checked from this device',
      );
    });

    test('a host list that has not answered reads an em dash', () {
      expect(npmProxyHostsSubtitle(null, null), '—');
    });
  });

  group('npmCertificateRows', () {
    test('soonest first, and an undated certificate sorts last', () {
      final rows = npmCertificateRows([
        _cert(name: 'undated', expiresOn: null),
        _cert(name: 'far', expiresIn: const Duration(days: 150)),
        _cert(name: 'near', expiresIn: const Duration(days: 9)),
        _cert(name: 'gone', expiresIn: const Duration(days: -2)),
      ], now);

      expect(rows.map((r) => r.certificate.displayName), [
        'gone',
        'near',
        'far',
        // Not urgent — unknown. Heading a list ordered by urgency would assert
        // the one thing nobody knows about it.
        'undated',
      ]);
      expect(rows.map((r) => r.tone), [
        StatusTone.warning,
        StatusTone.warning,
        StatusTone.success,
        StatusTone.neutral,
      ]);
    });

    test('the twenty-one day boundary is inclusive', () {
      // Let's Encrypt renews from thirty days out, so a shorter window than
      // that only ever fires on one that is failing to renew.
      expect(
        npmCertificateRows([
          _cert(expiresIn: const Duration(days: 21, hours: 1)),
        ], now).single.tone,
        StatusTone.warning,
      );
      expect(
        npmCertificateRows([
          _cert(expiresIn: const Duration(days: 22, hours: 1)),
        ], now).single.tone,
        StatusTone.success,
      );
    });

    test('a certificate lapsed inside the day is amber and reads expired', () {
      final row = npmCertificateRows([
        _cert(name: 'photos', expiresIn: const Duration(hours: -6)),
      ], now).single;
      expect(row.tone, StatusTone.warning);
      expect(row.detail, "Let's Encrypt · expired today");
    });

    test('an undated certificate speaks the em dash rather than a number', () {
      final row = npmCertificateRows([
        _cert(name: 'wildcard', expiresOn: null),
      ], now).single;
      expect(row.detail, "Let's Encrypt · —");
      expect(row.spoken, "wildcard, Let's Encrypt, —");
    });
  });

  group('npmCertificatesSubtitle', () {
    test('counts the whole list and flags the ones that need renewing', () {
      expect(
        npmCertificatesSubtitle([
          _cert(expiresIn: const Duration(days: 9)),
          _cert(expiresIn: const Duration(days: 12)),
          _cert(expiresIn: const Duration(days: 150)),
        ], now),
        '3 · 2 expiring',
      );
    });

    test('lapsed and lapsing are counted apart, worst named first', () {
      // `isExpiringSoon` has no lower bound — an already-dead certificate
      // satisfies it — so folding both into one clause would have this header
      // say "2 expiring" while Needs attention, three inches above, says
      // "Certificate expired". One screen, one fact, two severities, and the
      // header stating the softer one.
      expect(
        npmCertificatesSubtitle([
          _cert(expiresIn: const Duration(days: -4)),
          _cert(expiresIn: const Duration(hours: -6)),
          _cert(expiresIn: const Duration(days: 9)),
          _cert(expiresIn: const Duration(days: 150)),
        ], now),
        '4 · 2 expired · 1 expiring',
      );
    });

    test('a certificate that lapsed hours ago is never called expiring', () {
      expect(
        npmCertificatesSubtitle([
          _cert(expiresIn: const Duration(hours: -6)),
        ], now),
        '1 · 1 expired',
      );
    });

    test('no flag when nothing is due', () {
      expect(
        npmCertificatesSubtitle([
          _cert(expiresIn: const Duration(days: 150)),
        ], now),
        '1',
      );
    });

    test('a list that has not answered reads an em dash, never 0', () {
      expect(npmCertificatesSubtitle(null, now), '—');
    });
  });
}

// ─── Builders ───────────────────────────────────────────────────────────────

NpmProxyHost _host({
  required int id,
  String domain = 'host.example.net',
  String forwardHost = 'backend.lan',
  int forwardPort = 8080,
  bool enabled = true,
  bool configLoaded = true,
  String errorText = '',
  int certificateId = 0,
  int accessListId = 0,
}) {
  return NpmProxyHost(
    id: id,
    domainNames: [domain],
    forwardScheme: 'http',
    forwardHost: forwardHost,
    forwardPort: forwardPort,
    enabled: enabled,
    sslForced: false,
    certificateId: certificateId,
    accessListId: accessListId,
    cachingEnabled: false,
    blockExploits: false,
    allowWebsocketUpgrade: false,
    configLoaded: configLoaded,
    errorText: errorText,
    advancedConfig: '',
  );
}

/// [expiresIn] is relative to the fixed `now` the group uses, so a test reads
/// "nine days out" rather than a date somebody has to subtract in their head.
NpmCertificate _cert({
  int id = 1,
  String name = 'cert.example.net',
  String provider = 'letsencrypt',
  Duration? expiresIn,
  Object? expiresOn = _unset,
}) {
  return NpmCertificate(
    id: id,
    provider: provider,
    niceName: name,
    domainNames: [name],
    expiresOn: identical(expiresOn, _unset)
        ? DateTime(2026, 9, 17, 12).add(expiresIn ?? const Duration(days: 90))
        : expiresOn as DateTime?,
  );
}

/// Distinguishes "no date given" from "the default date", so a test can pass an
/// explicit null without the builder helpfully filling it in.
const Object _unset = Object();

NpmUpstreamReport _report(
  Map<int, NpmUpstream> byHostId, {
  required int checked,
  required int total,
}) {
  return NpmUpstreamReport(
    byHostId: byHostId,
    checked: checked,
    total: total,
    takenAt: DateTime(2026, 9, 17, 12),
  );
}
