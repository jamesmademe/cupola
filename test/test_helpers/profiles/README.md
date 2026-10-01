# Configuration profiles (P1–P9)

Every household configures Cupola differently. Some services are missing.
Some are known only through another service. Some do not answer. Some
accounts are read-only, and some households run two instances of one
service. Some household members sign in to Seerr with an account of their
own. This folder holds the profiles of the config inventory, so that a fix
can be tested against the same small set of configurations.

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
- `withSeerrPermissions(mask)` gives every Seerr account of the profile
  another permission mask: 4K, auto-approval, REQUEST_ADVANCED. Build the
  mask from `SeerrPermission` values.
- `withSeerrRelease(SeerrRelease.overseerr)` puts another release behind
  Seerr, at one connection with `instanceId:` or at all of them.
- `withDownloads([download])` adds downloads to the world: a torrent in
  error, say. Each is drawn by its client's fake and, when it names an arr,
  by that arr's queue.
- `withFullDisk(id)` fills a download client's disk. SABnzbd answers its
  queue paused, as it pauses itself on a full disk, with 0.42 GB free in its
  download folder and every slot reporting its job's own status.

A test can answer ahead of the world with
`harness.network.on(id, 'GET', path, (request) => NetworkReply.json(…))`,
or `onRpc` for TrueNAS. Anything no route answers is served `404` and
recorded in `network.unanswered`.

## Behaviours

Each behaviour is sent in the service's own wire shape, so the app's own
classifiers turn it into a verdict.

`ConnectionBehaviour` is a sealed type, not an enum, because some behaviours
carry a value. The plain ones are `PlainBehaviour` values, still reached as
`ConnectionBehaviour.refusesKey` and the like, so a call site reads the same
either way. A `switch` over a behaviour matches `PlainBehaviour.x` for the
plain ones and the class for the others; `behaviour.label` names it in a
test's description. Seerr's own states are `SeerrBehaviour`s
(`PlainSeerrBehaviour` and `SeerrSignInDisabled`), reached the same way
(`ConnectionBehaviour.csrfProtected`); every other service answers as
`answers` under one of them.

| Behaviour | On the wire |
|---|---|
| `answers` | Canned world data. |
| `servesHtmlPage` | Every HTTP request, public routes included, gets `200` with a web server's default page (`text/html`). An address missing its base path, a proxy with nothing routed. WebSocket upgrades are untouched. |
| `behindCloudflareAccess(mode:, team:, serviceToken:, tokenHasPolicy:)` | Cloudflare Access in front of every HTTP request, public routes included (`gatewayReply` in `profile_network.dart`, before any service fake). `redirect` (the default) answers `302` to `https://<team>.cloudflareaccess.com/cdn-cgi/access/login/<host>`; `unauthorized` answers `401` with Cloudflare's page, `Server: cloudflare` and a `CF-Ray`. A request carrying `serviceToken` as `CF-Access-Client-Id`/`-Secret` reaches the service when `tokenHasPolicy` (the default); a token without a policy is turned away like none. Nothing in lib sends one yet. |
| `behindSignInPage(mode:)` | `redirect` (the default) answers `302` to `https://auth.example.net/login?rd=…`; `sameHostForm` answers `200` with a page holding a password field. Nothing gets through. |
| `behindPasswordPrompt(credentials:)` | `401` with `WWW-Authenticate: Basic realm="Restricted"` and nginx's page. A request whose `Authorization: Basic` carries `credentials` gets through. |
| `answersAsOtherService(service)` | The other service's fake answers every request at this address, upgrades included: a wrong port. `answersAsOtherService(ServiceKey.sonarr)` on Radarr's connection answers `/api/v3/system/status` with `appName: Sonarr`. |
| `didNotAnswer` | `SocketException('Connection refused')` at dial time. The attempt is logged with `dialRefused`. |
| `timesOut` | `SocketException('Connection timed out')`, which Dio reports as `connectionTimeout`. It is raised at once, and the app reads it as did not answer: the connection never completed. |
| `refusesKey` | The arrs answer 401. Seerr answers 403 `{status: 403, error: 'You do not have permission to access this endpoint'}`, and a sign-in or a session still works. qBittorrent answers `200 Fails.` on login. SABnzbd answers `status: false`. TrueNAS answers `false` to the key login. Dockge answers `ok: false` to login. Public probes keep answering: Jellyfin `/System/Info/Public`, Plex `/identity`, NPM `/api/`, Seerr `/status` and SABnzbd `mode=version`. |
| `readOnly` | Capability probes answer read-only: TrueNAS `auth.me`, NPM `users/me` and Unraid `me` all come from fixtures. Jellyfin behaves as a non-admin token and Plex as a non-owner token, so admin reads are refused. For every other service, writes get 403. |
| `homeOnly` (flag) | The connection answers at home. Away, it refuses the connection. The flag combines with the behaviour: P7's TrueNAS is read-only and home-only. |
| `latency` | Every answer waits this long in fake time. The app's own timeouts fire as they would live. |
| `sessionExpired` (Seerr) | The session the account connection starts with is over on the server: every route it reaches answers `403 {status, error}`, `/auth/me` included. The key still works, and a new sign-in starts a session that does. |
| `csrfProtected` (Seerr) | Every POST, PUT, PATCH and DELETE, sign-ins and the key included, needs the `_csrf` cookie and its token in `X-XSRF-TOKEN` (or `csrf-token`, `xsrf-token`, `x-csrf-token`), else `403 {message: 'invalid csrf token'}`. Every answer that gets past the guard sets `XSRF-TOKEN`; an answer to a request without the secret sets `_csrf` (HttpOnly, Secure, SameSite=Strict). A refused write gets `_csrf` and no `XSRF-TOKEN`, as csurf sends it. The session cookie turns `SameSite=Strict`. |
| `signInDisabled(method)` (Seerr) | `local`: `localLogin: false` and `500 {error: 'Password sign-in is disabled.'}`. `plex`, `jellyfin`, `emby`: `mediaServerLogin: false` and `500 {error: 'Plex login is disabled'}` or `{error: 'Jellyfin login is disabled'}`. `jellyfinQuickConnect`: Jellyfin's own Quick Connect is off, `/settings/public` does not say so, and `initiate` answers `500 {message: 'Failed to initiate quick connect.'}`. |
| `notInitialized` (Seerr) | `/settings/public` answers `initialized: false` and `mediaServerType: 4`. Nobody exists, so the key reaches nobody. A Plex sign-in, or a Jellyfin one with a `hostname`, creates the admin: the trap the app's guard is for. Quick Connect answers `403 Quick Connect is not available during initial setup.` |
| `quotaReached` (Seerr) | Every account without MANAGE_USERS is at its limit: `/user/{id}/quota` answers `restricted: true` for both kinds and `POST /request` answers `403 Movie Quota exceeded.` or `Series Quota exceeded.` |

## The profiles

| Profile | Connections | Cases | Use it for |
|---|---|---|---|
| `p1` Full household | 12, including Radarr + Radarr 4K. Plex, Readarr, Transmission, NZBGet, Unraid and NPM are not set up. | e, a, f (Jellyfin files Elephants Dream under another TMDB id) | Every surface, and the design default. |
| `p2` Requester (Anna) | Seerr only, signed in with Anna's local account (REQUEST, 32) | d, c | Requester surfaces. See *Seerr accounts* for what the app holds today. |
| `p2ViaJellyfin` (P2-J) | P2 on Seerr 3.5.0 with Jellyfin; Anna is the Jellyfin user Seerr imported | d, c | The Jellyfin sign-in and Quick Connect. |
| `p2ViaPlex` (P2-P) | P2 on a Seerr set up with Plex (`mediaServerType` 1); Anna is a Plex user. No Plex connection | d, c | The plex.tv PIN and the Plex sign-in. |
| `p2WithJellyfin` | P2 plus Anna's own non-admin Jellyfin | d | Jellyfin as a non-admin. |
| `p3` First day | Radarr, Sonarr, Seerr | a (no client, no media server, no Bazarr, no Prowlarr) | Home, Activity and Media without the rest of the stack. |
| `p4` No Seerr | Radarr, Sonarr, Lidarr, Prowlarr, qBittorrent, Transmission | a (Seerr), two clients | Discover and Search without Seerr, and joining two clients. |
| `p5` Arrs via Seerr | Seerr, Jellyfin. Seerr's settings list a Radarr and a Sonarr. | b | Approve and Media rows that are known only from Seerr, and setup from Seerr. The Seerr-known servers answer at their addresses. |
| `p6` Two of a kind | Radarr ×2, Sonarr ×2, Seerr with default and 4K servers, Bazarr following Radarr only, Plex with a non-owner token, qBittorrent, SABnzbd | e, f, d | Actions that must name their instance. |
| `p7` Degraded and away | P1, away from home. Jellyfin and Bazarr do not answer. Lidarr, Prowlarr, SABnzbd, TrueNAS and Dockge are home-only. qBittorrent refuses the sign-in. TrueNAS is read-only. | c, d | Red versus amber, and totals over the sources that answered. |
| `p9` Operator with a friend's Seerr | P1 plus Sara's Seerr (`seerrFriend`, `https://seerr.example.net`, labelled `Sara`), where the operator has his own account with REQUEST only (user 4) | e, d, a, f | The operator's app with one Seerr he runs and one he only requests from. |

`WorldConnections` also holds connections no profile configures, for a
test that adds one with `withConnection`: World B's Readarr, NZBGet, Unraid
and NPM, a second Jellyfin and a second Seerr at the cabin
(`jellyfinCabin`, `seerrCabin`, both labelled `Cabin`) beside the unnamed
ones at home, and a second Lidarr (`lidarrVinyl`, labelled `Vinyl`).

Names, hosts (`nas.home.arpa`) and titles come from the design brief's
world (`world.dart`). Rows are built in Dart because they join across
services by download id and their times are relative to `network.now`.
Shapes that carry no title come from `test/fixtures/`.

## Seerr accounts

The fake Seerr answers whoever calls it as Seerr v3.5.0 does
(`fakes/seerr_sessions.dart`, beside the world data in `fakes/media_fakes.dart`):

- **Who is calling.** `X-Api-Key` equal to `worldKey(<connection id>)` is
  user 1, the admin. Otherwise a `connect.sid` this server signed and still
  keeps is that session's user. Otherwise nobody. Every route but the ones
  `SeerrFake.isPublic` lists (`/status`, `/status/appdata`,
  `/settings/public`, the sign-ins) wants somebody; `/settings/*` wants ADMIN;
  approve, decline, retry and the `/media` writes want MANAGE_REQUESTS; the
  admin's `/user` writes and a user's `settings/permissions` MANAGE_USERS; the
  issue list one of the issue permissions. Refused, they answer `403 {status:
  403, error: 'You do not have permission to access this endpoint'}`.
- **A user's own settings.** `/user/{id}/settings/*` and the push
  subscriptions want user `{id}` or MANAGE_USERS, and linking a Plex or
  Jellyfin account user `{id}` only (`isOwnProfileOrAdmin`, `isOwnProfile`);
  otherwise `403 {message: "You do not have permission to view this user's
  settings."}`, for a write too. Past that, `main` and `notifications` keep
  user 1's settings user 1's (`You do not have permission to modify this
  user's settings.`), `password` wants the current password unless
  MANAGE_USERS sets another's, and `permissions` refuses user 1 and oneself.
- **What a session sees.** Its own requests only (without MANAGE_REQUESTS or
  REQUEST_VIEW), `403` for another member's request or `?requestedBy=`, the
  user list without emails, its own quota. `DELETE /request/{id}` answers
  `401` once the request is not its own or no longer waits. `POST /request`
  checks the kind and 4K permissions and the quota, and an auto-approve bit
  makes the new request approved. The key's answers are what they always
  were.
- **Signing in.** `POST /auth/local {email, password}`, `POST /auth/jellyfin
  {username, password}`, `POST /auth/plex {authToken}` and Quick Connect
  (`initiate` → `{code, secret}`, `check?secret=` → `{authenticated}`,
  `authenticate {secret}`, Seerr 3.4.0 and later, Jellyfin only). Each answers
  `Set-Cookie: connect.sid=s%3A<id>.<signature>; Path=/; Expires=…; HttpOnly;
  SameSite=Lax` (`Secure` over https) and the user without its email. The
  local sign-in's user carries `permissions: 0`, as the route's four-column
  select leaves it: read `/auth/me`. Every refusal is the route's literal
  text, in `{message}` or `{error}` as the route writes it. A world user
  (`WorldSeerrUsers`) can sign in every way; the secrets are fakes derived
  from the name (`world-anna-password`, `world-anna-plex-token`).
- **The saved session.** A connection with a `seerrAccount` starts with a
  live session: `network.seerrSessionOf(id)` is the cookie value the app would
  have saved. A session lives 30 days after its last use on the network clock;
  `POST /auth/logout` ends it.
- **Quick Connect.** `network.approveQuickConnect(id, code)` is the person
  approving the code from a Jellyfin app; a code times out after 10 minutes.
- **plex.tv.** `https://plex.tv` answers `POST /api/v2/pins?strong=true`
  (`201 {id, code, expiresAt, authToken: null}`), `GET /api/v2/pins/{id}` for
  the identifier that made it, and `GET /api/v2/user`. `network.claimPlexPin(id)`
  is the person signing in on app.plex.tv: the PIN then carries the account's
  plex.tv token. A strong PIN expires after 30 minutes. `requestsToHost('plex.tv')`
  lists what went there.
- **Fake time.** `network.currentTime` is what sessions, codes and PINs expire
  by. `network.elapse(duration)` moves it in a plain test;
  `pumpWithProfile` ties it to the widget test's clock, and a test that pumps
  its own tree calls `network.followFakeTime(tester.binding)`. Raw `Dio` calls
  inside a widget test go through `tester.runAsync`.
- **`/status` and `/settings/public`** follow the connection's `SeerrRelease`
  (Jellyseerr 2.7.3 unless a profile says otherwise), from the recorded
  `test/fixtures/seerr/public_settings_*.json`, with `initialized`,
  `mediaServerType`, the 4K flags (a default 4K server in `seerrKnows`),
  `localLogin` and `mediaServerLogin` laid over them.

**What the app holds today.** `ServiceInstance` has no account yet, and a
Seerr connection without a credential reads as not set up. So every account
connection (P2's, P2-J's, P2-P's, Sara's in P9) still carries the server's
key in its credential slot, and the app, which signs in with a key only,
reaches those servers as the admin. The account side is on the network for a
client that signs in or sends the saved session. When the app learns to sign
in, the account connections drop the key and the saved session goes where the
app keeps its sessions.

Not verified against a live server, and marked where they are written: the
answers Seerr only relays (Jellyfin's Quick Connect refusals and its 10-minute
timeout, plex.tv's create status, `expiresIn`, its 404, 400 and 401 bodies),
the `404` an older release answers for a route it does not have, and the
four-column user of the local sign-in.

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
- **Client faults in the world itself.** The world as written has none. A
  test adds one with `withDownloads`: `DownloadState.failed` is qBittorrent's
  `error` and a Transmission local error (`error: 3`, the daemon's own
  words), `missingFiles` is qBittorrent's `missingFiles`, and `heldByClient`
  is a SABnzbd slot `Paused` with an `ENCRYPTED` label (its arr says
  paused).
