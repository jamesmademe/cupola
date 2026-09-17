import 'dart:io';

import 'package:cupola/features/npm/domain/models/npm_models.dart';

/// Opens a connection to [host]:[port] and reports whether anything accepted
/// it. Injected so tests never touch a socket.
typedef NpmUpstreamConnector =
    Future<bool> Function(String host, int port, Duration timeout);

/// What one pass of the probe found, plus how much of the table it covered.
///
/// The coverage is part of the result rather than a detail of the run, because
/// the screen has to print it: the board heads the table "23 · reachability
/// checked for 8 of 23". A column that silently showed a verdict for eight rows
/// and nothing for fifteen would read as fifteen healthy hosts.
class NpmUpstreamReport {
  const NpmUpstreamReport({
    required this.byHostId,
    required this.checked,
    required this.total,
    required this.takenAt,
  });

  /// Nothing probed yet — the state every screen starts in.
  static final empty = NpmUpstreamReport(
    byHostId: const {},
    checked: 0,
    total: 0,
    takenAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final Map<int, NpmUpstream> byHostId;

  /// How many hosts this pass actually reached a verdict on.
  final int checked;

  /// How many hosts there were to reach a verdict on.
  ///
  /// **Enabled hosts only**, which is a narrower population than the host
  /// table a section header counts: a disabled host is not being served, so
  /// its backend is not a fact about this screen and the probe never opens a
  /// socket for it. [coverage] names that narrowing out loud — see its doc.
  final int total;

  final DateTime takenAt;

  /// Absent means unchecked, never "down". A host outside the budget has not
  /// been measured, and the difference is the whole point of the enum.
  NpmUpstream forHost(int hostId) => byHostId[hostId] ?? NpmUpstream.unchecked;

  int get downCount =>
      byHostId.values.where((u) => u == NpmUpstream.down).length;

  /// `reachability checked for 8 of 23 enabled`, or null when nothing was
  /// checked — a coverage line reading "0 of 23" is noise on a screen that has
  /// not probed anything yet.
  ///
  /// The word `enabled` is load-bearing and not padding. This line is printed
  /// beside a header count of the **whole** host table, and [total] counts only
  /// the hosts the probe is willing to look at. On a box with 25 hosts of which
  /// two are switched off, `25 · reachability checked for 8 of 23` invites
  /// exactly one reading — that two hosts went missing between the two figures
  /// — and the sentence has no way to say otherwise. Naming the population is
  /// what makes the pair honest.
  String? get coverage => checked == 0
      ? null
      : 'reachability checked for $checked of $total enabled';
}

/// Asks, from **this device**, whether anything is listening where each proxy
/// host forwards.
///
/// NPM cannot answer this. `meta.nginx_online` is the verdict of the last
/// configuration attempt and nothing polls it, so a host whose backend died an
/// hour ago still reads healthy — see [NpmProxyHost.configLoaded]. The only way
/// to know what is actually answering is to go and look, and the only place
/// that can look is the client. That is why the design calls this a
/// **client-side** probe and says so on screen: the answer is about this
/// device's view of the network, not the server's.
///
/// It connects and hangs up. No HTTP request, no TLS negotiation, no
/// credentials — the question is "is anything accepting connections here", and
/// a GET would additionally need a bad-certificate decision for every
/// self-signed backend in a homelab, which is a security posture nobody asked
/// for in order to colour one column. The cost is honest and stated: a TCP
/// accept proves a listener, not a healthy application.
///
/// Two consequences worth keeping in the copy:
///
///  * A forward host is frequently a name that resolves **only on the server's
///    network** (`immich.lan`, a Docker service name). Failing to reach it from
///    a phone on cellular is expected and is not evidence the site is down.
///  * Disabled hosts are not probed. NPM is not serving them, so their
///    backend's state is not a fact about this screen.
class NpmUpstreamProbe {
  const NpmUpstreamProbe({
    this.connector = _connect,
    this.budget = defaultBudget,
    this.timeout = const Duration(seconds: 2),
    this.concurrency = 4,
  });

  /// How many hosts one pass will look at.
  ///
  /// Budgeted rather than exhaustive, and partial **by design**: 23 hosts means
  /// 23 sockets, most of them to names that do not resolve off the server's
  /// network, each costing the full timeout. The design draws the partial
  /// result — "checked for 8 of 23" — rather than making the user wait for a
  /// complete one.
  static const int defaultBudget = 8;

  final NpmUpstreamConnector connector;
  final int budget;
  final Duration timeout;

  /// Sockets in flight at once. Four keeps a slow pass under three timeouts
  /// end to end without opening the whole budget on a phone radio at once.
  final int concurrency;

  Future<NpmUpstreamReport> run(List<NpmProxyHost> hosts) async {
    // The rows a person is looking at get the budget: a host nginx refused is
    // the one they opened the screen for, and it is also the one where "is the
    // backend even up" changes what they do next.
    final candidates = hosts.where((h) => h.enabled).toList()
      ..sort((a, b) {
        final byRank = (a.hasConfigError ? 0 : 1).compareTo(
          b.hasConfigError ? 0 : 1,
        );
        return byRank != 0
            ? byRank
            : a.primaryDomain.compareTo(b.primaryDomain);
      });

    final targets = candidates.take(budget).toList(growable: false);
    final results = <int, NpmUpstream>{};

    for (var i = 0; i < targets.length; i += concurrency) {
      final slice = targets.skip(i).take(concurrency);
      await Future.wait(
        slice.map((host) async {
          final reachable = await _probeOne(host);
          results[host.id] = reachable
              ? NpmUpstream.answering
              : NpmUpstream.down;
        }),
      );
    }

    return NpmUpstreamReport(
      byHostId: results,
      checked: results.length,
      total: candidates.length,
      takenAt: DateTime.now(),
    );
  }

  Future<bool> _probeOne(NpmProxyHost host) async {
    final target = host.forwardHost.trim();
    if (target.isEmpty || host.forwardPort < 1 || host.forwardPort > 65535) {
      return false;
    }
    try {
      return await connector(target, host.forwardPort, timeout);
    } catch (_) {
      // Every failure is the same answer here — refused, no route, no such
      // host, timed out. Which one it was would be a different screen.
      return false;
    }
  }

  static Future<bool> _connect(String host, int port, Duration timeout) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    // Destroyed immediately: the handshake is the whole measurement, and a
    // socket left open to someone's media server is a resource this app has no
    // business holding.
    socket.destroy();
    return true;
  }
}
