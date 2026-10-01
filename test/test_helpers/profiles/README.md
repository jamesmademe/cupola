# Configuration profiles (P1–P7)

Every household configures Cupola differently. Some services are missing.
Some are known only through another service. Some do not answer. Some
accounts are read-only, and some households run two instances of one
service. This folder holds the profiles P1–P7 from the config inventory, so
that a fix can be tested against the same small set of configurations.

A profile is a value (`ConfigProfile`). It describes which connections
exist, how each one behaves, where the instance lens rests and what Seerr
knows beyond them. `ProfileHarness` turns a profile into a live test. It
installs a fake network as `HttpOverrides.global` and overrides only the
startup settings.

**No service provider is overridden.** Every client is the app's own and is
built by the app's own providers. This includes the throwaway clients the
Dashboard probe builds, and the TrueNAS and Dockge WebSockets. So the app's
classification and counting code is what runs.

## Usage

```dart
import '../../test_helpers/profiles/profiles.dart';

testWidgets('…', (tester) async {
  final harness = await pumpWithProfile(tester, Profiles.p6,
      child: const DashboardScreen());
  // …assert on the screen, or on what the app asked:
  expect(harness.network.requestsTo(WorldIds.radarr4k), isNotEmpty);
  await harness.unmount(tester); // always, see below
});

test('…', () async {
  final harness = await ProfileHarness.start(
    Profiles.p1.withBehaviour(WorldIds.qbittorrent, ConnectionBehaviour.refusesKey),
  );
  final qb = harness.container().read(qbittorrentServiceProvider);
});
```

Profiles can be varied:

- `withBehaviour(id, behaviour)` changes how one connection behaves.
- `withLens(service, id)` moves the lens.
- `at(NetworkPlace.home)` changes where the device is.
- `without(service)` removes a service.
- `withConnection(WorldConnections.npm)` adds a connection.
- `withLatency(id, duration)` makes one connection slow.

A test can answer ahead of the world with
`harness.network.on(id, 'GET', path, (request) => NetworkReply.json(…))`,
or `onRpc` for TrueNAS. Anything no route answers is served `404` and
recorded in `network.unanswered`.

## Behaviours

Each behaviour is sent in the service's own wire shape, so the app's own
classifiers turn it into a verdict.

| Behaviour | On the wire |
|---|---|
| `answers` | Canned world data. |
| `didNotAnswer` | `SocketException('Connection refused')` at dial time. The attempt is logged with `dialRefused`. |
| `timesOut` | `SocketException('Connection timed out')`, which Dio reports as `connectionTimeout`. It is raised at once, and the app reads it as did not answer: the connection never completed. |
| `refusesKey` | The arrs answer 401. Seerr answers 403. qBittorrent answers `200 Fails.` on login. SABnzbd answers `status: false`. TrueNAS answers `false` to the key login. Dockge answers `ok: false` to login. Public probes keep answering: Jellyfin `/System/Info/Public`, Plex `/identity`, NPM `/api/`, Seerr `/status` and SABnzbd `mode=version`. |
| `readOnly` | Capability probes answer read-only: TrueNAS `auth.me`, NPM `users/me` and Unraid `me` all come from fixtures. Jellyfin behaves as a non-admin token and Plex as a non-owner token, so admin reads are refused. For every other service, writes get 403. |
| `homeOnly` (flag) | The connection answers at home. Away, it refuses the connection. The flag combines with the behaviour: P7's TrueNAS is read-only and home-only. |
| `latency` | Every answer waits this long in fake time. The app's own timeouts fire as they would live. |

## The profiles

| Profile | Connections | Cases | Use it for |
|---|---|---|---|
| `p1` Full household | 12, including Radarr + Radarr 4K. Plex, Readarr, Transmission, NZBGet, Unraid and NPM are not set up. | e, a, f (Jellyfin files Elephants Dream under another TMDB id) | Every surface, and the design default. |
| `p2` Requester (Anna) | Seerr only | d, c | Requester surfaces. This profile is only half modelled; see below. |
| `p2WithJellyfin` | P2 plus Anna's own non-admin Jellyfin | d | Jellyfin as a non-admin. |
| `p3` First day | Radarr, Sonarr, Seerr | a (no client, no media server, no Bazarr, no Prowlarr) | Home, Activity and Media without the rest of the stack. |
| `p4` No Seerr | Radarr, Sonarr, Lidarr, Prowlarr, qBittorrent, Transmission | a (Seerr), two clients | Discover and Search without Seerr, and joining two clients. |
| `p5` Arrs via Seerr | Seerr, Jellyfin. Seerr's settings list a Radarr and a Sonarr. | b | Approve and Media rows that are known only from Seerr, and setup from Seerr. The Seerr-known servers answer at their addresses. |
| `p6` Two of a kind | Radarr ×2, Sonarr ×2, Seerr with default and 4K servers, Bazarr following Radarr only, Plex with a non-owner token, qBittorrent, SABnzbd | e, f, d | Actions that must name their instance. |
| `p7` Degraded and away | P1, away from home. Jellyfin and Bazarr do not answer. Lidarr, Prowlarr, SABnzbd, TrueNAS and Dockge are home-only. qBittorrent refuses the sign-in. TrueNAS is read-only. | c, d | Red versus amber, and totals over the sources that answered. |

`WorldConnections` also holds connections no profile configures, for a
test that adds one with `withConnection`: World B's Readarr, NZBGet, Unraid
and NPM, and a second Jellyfin and a second Seerr at the cabin
(`jellyfinCabin`, `seerrCabin`, both labelled `Cabin`) beside the unnamed
ones at home.

Names, hosts (`nas.home.arpa`) and titles come from the design brief's
world (`world.dart`). Rows are built in Dart because they join across
services by download id and their times are relative to `network.now`.
Shapes that carry no title come from `test/fixtures/`.

## Traps

- **Always end a widget test with `harness.unmount(tester)`.** When a Dockge
  client is disposed, socket_io_client schedules a `Timer.run`. The teardown
  in `flutter_test` never pumps it, so the test fails with "A Timer is still
  pending".
- Prefer `harness.settle(tester)` to `pumpAndSettle`. Prowlarr parses its
  history in `Isolate.run` at every size, and `pumpAndSettle` never lets a
  real isolate answer.
- Keep canned lists under 200 rows. Above that, the arr, qBittorrent and
  Jellyfin parsers move into an isolate for the same reason.
- Carry no artwork. A `posterPath` sends `CachedNetworkImage` into real
  cache I/O, which never completes in fake time, and its shimmer never
  settles.
- Retries follow the app's own policy. `.future` fails on the first error,
  and the retries continue in the background. In a widget test they run on
  fake time, which is why a service that does not answer shimmers for about
  a minute before the screen settles. When a test counts requests, pass
  `container(retry: (_, _) => null)`.

## Not modelled

- **P2's requester session.** Cupola signs in to Seerr with an admin API
  key only, so Anna's Seerr answers as the operator's does. The hook is
  `ConfigProfile.seerrRequester`, marked `TODO(requester-session)`. When a
  user-session path lands, the fake Seerr should answer `/auth/me` as Anna
  and refuse admin routes with 403.
- **Away addresses.** A connection has one URL, so `homeOnly` away is
  `didNotAnswer`. The world's `*.example.net` away hosts need a field in lib
  before a profile can use them.
- **Last-known values with their time** (P7). This is app state, not network
  state.
- **TLS.** No certificate crosses the fake network. Pins are threaded
  through, but TOFU prompts and `probeServerCertificate` (a raw
  `SecureSocket`, which bypasses `HttpOverrides`) are out of reach.
- **Plex non-owner.** Only the refused `/status/sessions` is modelled. There
  is no documented owner probe to answer.
- **qBittorrent `error` torrents, SABnzbd/NZBGet faults, the World-B
  Transmission error.** The world as written has none. Script them with
  `network.on`.
