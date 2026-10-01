import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The six ways one household's configuration differs from another's, as the
/// config inventory's legend names them (a–f).
///
/// Declared on each profile so a test can ask "which profiles exercise the b
/// case" rather than hard-coding a list that drifts from the table.
enum ConfigCase {
  /// a — not set up in Cupola, and unknown to anything else.
  notSetUp('a'),

  /// b — not set up in Cupola, but known through another service (Seerr's
  /// settings know a Radarr that Cupola has no connection to).
  knownThroughAnother('b'),

  /// c — set up, and did not answer.
  didNotAnswer('c'),

  /// d — answered, but not allowed: a refused or read-only credential, or the
  /// Seerr requester.
  notAllowed('d'),

  /// e — more than one connection of one service.
  severalInstances('e'),

  /// f — the media server has an item, but its match is not verified.
  matchNotVerified('f');

  const ConfigCase(this.mark);

  /// The letter the inventory uses.
  final String mark;
}

/// How one connection behaves on the fake network.
///
/// Each value is mapped onto what the real client would see on the wire —
/// a refused socket, a 401, qBittorrent's `Fails.`, a proxy's web page — so
/// the app's own classification code (`classifyConnectionFailure`, the qB
/// login reader, the capability probes) is what turns it into a verdict.
/// Nothing here hands the app a pre-classified error.
///
/// A sealed type rather than an enum because some behaviours carry a value
/// (which service answers instead, which gateway mode). The plain ones are
/// [PlainBehaviour] values, reachable under the names they always had
/// (`ConnectionBehaviour.refusesKey`), so a call site reads the same whether
/// the behaviour it names takes a value or not.
sealed class ConnectionBehaviour {
  const ConnectionBehaviour();

  /// Every request answers from the world's canned data.
  static const answers = PlainBehaviour.answers;

  /// The host refuses the connection. See [PlainBehaviour.didNotAnswer].
  static const didNotAnswer = PlainBehaviour.didNotAnswer;

  /// The host never completes the handshake. See [PlainBehaviour.timesOut].
  static const timesOut = PlainBehaviour.timesOut;

  /// The server refuses the credential. See [PlainBehaviour.refusesKey].
  static const refusesKey = PlainBehaviour.refusesKey;

  /// The credential may read and not write. See [PlainBehaviour.readOnly].
  static const readOnly = PlainBehaviour.readOnly;

  /// A web page answers every request. See [PlainBehaviour.servesHtmlPage].
  static const servesHtmlPage = PlainBehaviour.servesHtmlPage;

  /// [service] answers at this connection's address. See
  /// [AnswersAsOtherService].
  const factory ConnectionBehaviour.answersAsOtherService(ServiceKey service) =
      AnswersAsOtherService;

  /// A short name for a test's description.
  String get label;
}

/// Another service of the stack answers at this connection's address, from
/// its own canned data: a Sonarr reached on Radarr's port. Every request,
/// WebSocket upgrades included, is answered by [service]'s fake.
final class AnswersAsOtherService extends ConnectionBehaviour {
  const AnswersAsOtherService(this.service);

  /// Who answers instead.
  final ServiceKey service;

  @override
  String get label => 'answers as ${service.title}';
}

/// The behaviours that take no value.
enum PlainBehaviour implements ConnectionBehaviour {
  /// Every request answers from the world's canned data.
  answers,

  /// The host refuses the connection: `SocketException('Connection refused')`
  /// at dial time, which Dio reports as `connectionError` — a dead host.
  didNotAnswer,

  /// The host never completes the handshake: `SocketException('Connection
  /// timed out')`, which Dio reports as `connectionTimeout`. Raised at once,
  /// so a test never waits out a real deadline. The app classifies it as did
  /// not answer, like [didNotAnswer]: the connection never completed. A
  /// server reached and then slow is `withLatency` past the app's deadline.
  timesOut,

  /// The server answers and refuses the credential, each service in its own
  /// way (401, 403, qBittorrent's `200 Fails.`, SABnzbd's `status: false`,
  /// TrueNAS's `false` login). Its unauthenticated routes — the Jellyfin, Plex,
  /// NPM and Seerr status probes — still answer, as they do live.
  refusesKey,

  /// The credential may read and not write.
  ///
  /// Where the app probes scope (TrueNAS `auth.me`, NPM `users/me`, Unraid
  /// `me`) the probe answers read-only. Jellyfin and Plex answer as a
  /// non-admin / non-owner token: their admin reads are refused too. Every
  /// other service has one admin key, so read-only there means only "a write
  /// is refused with 403" — the generic failure path the legend describes.
  readOnly,

  /// Something other than the service answers every HTTP request with `200`
  /// and a web page: a reverse proxy's default page, an address missing its
  /// base path. The case behind "answering, and the library is empty".
  /// WebSocket upgrades are not affected.
  servesHtmlPage;

  @override
  String get label => name;
}

/// Where the device is, for [ProfileConnection.homeOnly].
enum NetworkPlace { home, away }

/// One configured connection and how it behaves.
class ProfileConnection {
  const ProfileConnection(
    this.instance, {
    this.behaviour = ConnectionBehaviour.answers,
    this.homeOnly = false,
    this.latency = Duration.zero,
  });

  final ServiceInstance instance;

  /// How it behaves wherever it is reachable.
  final ConnectionBehaviour behaviour;

  /// Reachable on the home network only: [behaviour] at
  /// [NetworkPlace.home], a refused connection at [NetworkPlace.away].
  ///
  /// A flag beside [behaviour] rather than a value of it, because the two
  /// compose: P7's TrueNAS is read-only *and* home-only, so it does not answer
  /// away and reads read-only at home. A connection carries one URL
  /// (`service_instance.dart` has no away address), so away is exactly
  /// [ConnectionBehaviour.didNotAnswer] in code today.
  final bool homeOnly;

  /// How long every answer takes, in fake time. Zero answers at once.
  ///
  /// For the slow source rather than the dead one: Dockge's ten-second
  /// deadline holding back every decision on Home, a probe's five-second
  /// timeout firing on a box that would have answered at six. The app's own
  /// deadlines (Dio's receive timeout, each probe's `.timeout`) run on fake
  /// timers too, so a latency past one of them fails exactly as it would live.
  final Duration latency;

  String get id => instance.id;
  ServiceKey get service => instance.service;

  ProfileConnection withBehaviour(ConnectionBehaviour behaviour) =>
      _copy(behaviour: behaviour);

  ProfileConnection withHomeOnly(bool homeOnly) => _copy(homeOnly: homeOnly);

  ProfileConnection withLatency(Duration latency) => _copy(latency: latency);

  ProfileConnection _copy({
    ConnectionBehaviour? behaviour,
    bool? homeOnly,
    Duration? latency,
  }) => ProfileConnection(
    instance,
    behaviour: behaviour ?? this.behaviour,
    homeOnly: homeOnly ?? this.homeOnly,
    latency: latency ?? this.latency,
  );

  /// How it behaves from [place].
  ConnectionBehaviour behaviourAt(NetworkPlace place) =>
      homeOnly && place == NetworkPlace.away
      ? ConnectionBehaviour.didNotAnswer
      : behaviour;
}

/// A Radarr or Sonarr that Seerr's own settings know, whether or not Cupola
/// has a connection to it — the raw material of the b case.
///
/// It is served twice by the fake Seerr, in the two shapes Seerr itself uses:
/// `GET /api/v1/settings/{radarr,sonarr}` (the admin view, address and key
/// included) and `GET /api/v1/service/{radarr,sonarr}` (the request-sheet
/// view the app reads today). The network also answers at [url], so a flow
/// that sets a connection up from Seerr's knowledge finds a live server there.
class SeerrKnownServer {
  const SeerrKnownServer({
    required this.seerrId,
    required this.service,
    required this.name,
    required this.url,
    required this.apiKey,
    this.is4k = false,
    this.isDefault = false,
    this.activeProfileId = 1,
    this.activeProfileName = 'HD-1080p',
    this.activeDirectory = '/mnt/tank/media/films',
  }) : assert(
         service == ServiceKey.radarr || service == ServiceKey.sonarr,
         'Seerr only knows Radarr and Sonarr servers.',
       );

  /// Seerr's own id for the server (0, 1, …), which is what a request's
  /// `serverId` names.
  final int seerrId;
  final ServiceKey service;

  /// The name the Seerr admin gave it: "Radarr 4K".
  final String name;
  final String url;
  final String apiKey;
  final bool is4k;
  final bool isDefault;
  final int activeProfileId;
  final String activeProfileName;
  final String activeDirectory;

  Uri get uri => Uri.parse(url);
}

/// The Seerr user a profile is lived by.
class WorldSeerrUser {
  const WorldSeerrUser({
    required this.id,
    required this.displayName,
    required this.permissions,
  });

  final int id;
  final String displayName;

  /// Seerr's permission bitmask: `2` is ADMIN, `32` REQUEST.
  final int permissions;
}

/// One configuration of Cupola, as the config inventory's profile table
/// describes it: which connections exist, how each behaves, where the lens
/// rests, and what Seerr knows beyond them.
///
/// A value, never a harness: [settings] is plain data, and turning a profile
/// into overrides and a fake network is `ProfileHarness`'s job. That split is
/// what lets a test derive a variant — P7 with qBittorrent answering, P6 with
/// the lens on the 4K Radarr — without rebuilding either.
class ConfigProfile {
  const ConfigProfile({
    required this.id,
    required this.title,
    required this.summary,
    required this.cases,
    required this.connections,
    this.lens = const {},
    this.place = NetworkPlace.home,
    this.seerrKnows = const [],
    this.unverifiedMatches = const {},
    this.seerrRequester,
    this.trustedCertificates = const {},
    this.bazarrFollows = const {ServiceKey.radarr, ServiceKey.sonarr},
  });

  /// `P1` … `P7`, as the inventory numbers them.
  final String id;
  final String title;
  final String summary;
  final Set<ConfigCase> cases;

  /// Every connection, in the user's own order: the first of a service is its
  /// primary, which is what `settings.radarrUrl` and a bare `/dashboard/radarr`
  /// resolve to.
  final List<ProfileConnection> connections;

  /// Where the instance lens rests, per service. Absent means the first
  /// connection, which is also what the app does with an empty lens map.
  final Map<ServiceKey, String> lens;

  final NetworkPlace place;

  /// The Radarr and Sonarr servers Seerr's settings list. Empty when the
  /// profile has no Seerr.
  final List<SeerrKnownServer> seerrKnows;

  /// Titles (world title keys) the media server holds under an id that does
  /// not match the arr's — case f. The fake Jellyfin and Plex carry them with
  /// a different TMDB id, so `streamExternalMatchScore` rejects the item.
  final Set<String> unverifiedMatches;

  /// The Seerr user this profile is lived by, or null for the operator.
  ///
  /// TODO(requester-session): Cupola signs in to Seerr with the admin API key
  /// only (`seerr_service.dart`, `ApiClient` + `X-Api-Key`), and Seerr treats
  /// an API key as its admin, so nothing reads this yet and the fake Seerr
  /// answers P2 as it answers the operator. When a user-session path lands,
  /// this is where P2's Anna plugs in: the fake Seerr should then answer
  /// `/api/v1/auth/me` as her and refuse the admin routes (settings, approve,
  /// decline, other users' requests) with 403.
  final WorldSeerrUser? seerrRequester;

  /// Pinned certificates by TLS origin. The fake network presents no
  /// certificate at all, so a pin here only proves the app threads it through
  /// the pinned adapter without breaking the request.
  final Map<String, String> trustedCertificates;

  /// Which arrs Bazarr's own settings point it at. P6's Bazarr follows Radarr
  /// only, so its episode side answers empty. Bazarr knows no Cupola
  /// connection: it follows one server of each, whichever that is.
  final Set<ServiceKey> bazarrFollows;

  /// The settings model the app starts from.
  SettingsModel get settings => SettingsModel(
    instances: [for (final c in connections) c.instance],
    trustedCertificates: trustedCertificates,
    region: 'IT',
  );

  ProfileConnection connection(String instanceId) => connections.firstWhere(
    (c) => c.id == instanceId,
    orElse: () => throw ArgumentError.value(
      instanceId,
      'instanceId',
      '$id has no such connection',
    ),
  );

  List<ProfileConnection> connectionsOf(ServiceKey service) =>
      connections.where((c) => c.service == service).toList(growable: false);

  bool has(ServiceKey service) => connections.any((c) => c.service == service);

  /// The connection the lens rests on for [service], or null when the
  /// profile has none — resolved the way `activeInstanceProvider` resolves it.
  ServiceInstance? lensOn(ServiceKey service) {
    final all = connectionsOf(service);
    if (all.isEmpty) return null;
    final named = lens[service];
    return all.where((c) => c.id == named).firstOrNull?.instance ??
        all.first.instance;
  }

  /// How [instanceId] behaves *here*, with [ProfileConnection.homeOnly]
  /// resolved against [place].
  ConnectionBehaviour behaviourOf(String instanceId) =>
      connection(instanceId).behaviourAt(place);

  /// A copy with [instanceId] behaving as [behaviour].
  ConfigProfile withBehaviour(
    String instanceId,
    ConnectionBehaviour behaviour,
  ) {
    connection(instanceId); // throws for an id the profile does not have
    return _copy(
      connections: [
        for (final c in connections)
          c.id == instanceId ? c.withBehaviour(behaviour) : c,
      ],
    );
  }

  /// A copy where every answer from [instanceId] takes [latency].
  ConfigProfile withLatency(String instanceId, Duration latency) {
    connection(instanceId);
    return _copy(
      connections: [
        for (final c in connections)
          c.id == instanceId ? c.withLatency(latency) : c,
      ],
    );
  }

  /// A copy with [connection] added after the others — a World-B service
  /// for the read-only cases only Unraid and NPM can show, say. Replaces a
  /// connection with the same id.
  ConfigProfile withConnection(ProfileConnection connection) => _copy(
    connections: [
      for (final c in connections)
        if (c.id != connection.id) c,
      connection,
    ],
  );

  /// A copy with the lens on [instanceId].
  ConfigProfile withLens(ServiceKey service, String instanceId) {
    if (connection(instanceId).service != service) {
      throw ArgumentError.value(instanceId, 'instanceId', 'not a $service');
    }
    return _copy(lens: {...lens, service: instanceId});
  }

  /// A copy with the device at [place].
  ConfigProfile at(NetworkPlace place) => _copy(place: place);

  /// A copy without any connection of [service] — its a case.
  ConfigProfile without(ServiceKey service) => _copy(
    connections: [
      for (final c in connections)
        if (c.service != service) c,
    ],
    lens: {...lens}..remove(service),
  );

  ConfigProfile _copy({
    List<ProfileConnection>? connections,
    Map<ServiceKey, String>? lens,
    NetworkPlace? place,
  }) => ConfigProfile(
    id: id,
    title: title,
    summary: summary,
    cases: cases,
    connections: connections ?? this.connections,
    lens: lens ?? this.lens,
    place: place ?? this.place,
    seerrKnows: seerrKnows,
    unverifiedMatches: unverifiedMatches,
    seerrRequester: seerrRequester,
    trustedCertificates: trustedCertificates,
    bazarrFollows: bazarrFollows,
  );

  @override
  String toString() => '$id · $title';
}
