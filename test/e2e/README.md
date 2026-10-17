# E2E tiers

The e2e tag drives the real Cupola service clients over HTTP, JSON-RPC,
Socket.IO and WebSocket. It is intentionally outside the offline flutter test
gate; dart_test.yaml skips it unless the caller opts in.

## Small Docker tier

This is the fast contract tier for the SABnzbd, NZBGet and Readarr tests:

~~~bash
docker compose -f docker-compose.e2e.yml up -d --wait
flutter test --tags e2e --run-skipped
docker compose -f docker-compose.e2e.yml down -v --remove-orphans
~~~

The small compose keeps its historical port layout, including SABnzbd on host
port 8080. Its seed files must not be mounted as writable long-lived state.

## Full macOS laboratory

docker-compose.maclab.yml and test/e2e/maclab/bootstrap.sh implement the
disposable lab for a native Flutter process on macOS. Containers run in
OrbStack; Cupola connects to their loopback-published ports like ordinary
self-hosted instances.

Preflight:

~~~bash
docker context show
docker version
docker compose version
~~~

The first command must print orbstack. Bootstrap or reset the disposable
project with:

~~~bash
test/e2e/maclab/bootstrap.sh --reset
~~~

A normal rerun is idempotent:

~~~bash
test/e2e/maclab/bootstrap.sh
~~~

The script pins vendor images by digest, copies tracked seeds into
.ai/scratch/zz_maclab/state, waits for all healthchecks, bootstraps Jellyfin,
Seerr and the first Dockge account, and writes generated credentials to a
chmod-600 file. `--reset` includes every Compose profile, so it really stops
and recreates this disposable project rather than silently leaving profiled
containers running. Run the full Dart transport harness without putting
credentials in the command line:

~~~bash
export CUPOLA_MACLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_maclab/state/credentials.env"
flutter test test/e2e/maclab_transport_e2e_test.dart \
  --tags e2e --run-skipped
~~~

The harness covers all seventeen registry services and asserts a successful
typed read, not merely that a container is running. Empty lists are valid
data; a failed health, authentication or payload probe fails the test.
It also probes wrong credentials against every transport: sixteen services
must reject them. The separate Plex negative probe is reported as skipped when
the container was never claimed: an unclaimed Plex runs with local
authentication disabled and accepts any `X-Plex-Token`. Once the server is
claimed, the bootstrap writes the server's own token (from its
`Preferences.xml`) to the credentials file and the probe runs.

The TrueNAS checks go over TLS with the fingerprint the bootstrap recorded in
`CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT`, at the address a person saves,
`https://127.0.0.1:8460`. The wrong key is refused as a key (classified
`unauthorized`, so a failure of the certificate can never pass for it). A pin
one digit off, and no pin at all, are each refused as an untrusted certificate
(`tls`), never as a dead host: the same test reads a port nothing listens on as
`unreachable`. The certificate probe the trust prompt uses must read the
recorded fingerprint, which is what ties the bootstrap's text to the app's.

## Published endpoint map

| Service | Native endpoint | Auth in the lab | Transport |
|---|---|---|---|
| Seerr | http://127.0.0.1:5055 | generated API key; a local requester account with a generated password | REST + session cookie |
| Radarr | http://127.0.0.1:7878 | test-key | REST v3 |
| Sonarr | http://127.0.0.1:8989 | test-key | REST v3 |
| Lidarr | http://127.0.0.1:8686 | test-key | REST v1 |
| Readarr | http://127.0.0.1:8787 | test-key | REST v1 |
| Prowlarr | http://127.0.0.1:9696 | test-key | REST v1 |
| Bazarr | http://127.0.0.1:6767 | test-key | REST |
| qBittorrent | http://127.0.0.1:8080 | admin / disposable password | form + cookie |
| Transmission | http://127.0.0.1:9091 | transmission / transmission | RPC + CSRF |
| SABnzbd | http://127.0.0.1:8082 | test-key | query API |
| NZBGet | http://127.0.0.1:6789 | nzbget / tegbzn6789 | JSON-RPC + Basic |
| Jellyfin | http://127.0.0.1:8096 | generated token + user id; a requester user with a generated password | REST |
| Plex | http://127.0.0.1:32400 | unclaimed: any token; claimed: the server's own token, read by the bootstrap | REST/XML-or-JSON |
| Dockge | http://127.0.0.1:5001 | disposable account provisioned by bootstrap | Socket.IO |
| Nginx Proxy Manager | http://127.0.0.1:8181 | admin@example.com / changeme | REST + JWT |
| TrueNAS fixture | wss://127.0.0.1:8460 (self-signed; the app saves https://127.0.0.1:8460) | test-key | WebSocket JSON-RPC over TLS |
| Unraid fixture | http://127.0.0.1:8480/graphql | test-key | GraphQL |

qBittorrent 5.1 validates the Host/Origin port, so the full lab uses host
port 8080 for qBittorrent and 8082 for SABnzbd. Transmission's LinuxServer
image consumes USER/PASS; the Compose file uses those names and the harness
asserts both the 409 CSRF challenge and the 401 wrong-password path.
Unclaimed, Plex is a transport/shape fixture: claiming it ties the lab to a
Plex account, which is the owner's choice and never the bootstrap's. Claimed,
its token stays in the chmod-600 credentials file like every other secret.

Dockge deliberately has no Docker socket mounted. Login, Socket.IO session and
read-only stack discovery are safe to test. Terminal and stack-mutating
capabilities require a separately approved disposable Docker socket/proxy and
are not silently granted by this compose file.

The TrueNAS fixture speaks TLS and nothing else, because Cupola refuses to dial
a TrueNAS address that is not https:// (TrueNAS 25.04 and later revoke an API key
that arrives in cleartext). Its certificate is self-signed, made once by
test/e2e/maclab/truenas_cert.sh (bootstrap.sh runs it before it starts the
containers) with `localhost` and `127.0.0.1` as names, and kept with the rest of
the lab's disposable state in `state/truenas/`; it is never committed. Cupola
trusts it the way a person does, by its fingerprint: the SHA-256 of the
certificate's DER encoding as 64 lowercase hex digits, without colons, the form
`certFingerprint` compares and `SettingsModel.trustedCertificates` stores under
the origin `https://127.0.0.1:8460`. The bootstrap writes it to the credentials
file as `CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT`. Added by hand in the app at
`https://127.0.0.1:8460`, "Test connection" reads the certificate and offers to
trust it; the fingerprint it shows is that one, written in colon-separated
uppercase pairs. A lab started before this
existed gets the certificate, the credentials entry and a mock that serves it
without a reset (the other credentials are left as they are):

~~~bash
export CUPOLA_MACLAB_STATE_DIR="$PWD/.ai/scratch/zz_maclab/state"
test/e2e/maclab/truenas_cert.sh credentials
docker compose -p cupola-maclab -f docker-compose.maclab.yml \
  --profile core up -d --build --wait truenas-mock
~~~

The mock reads the certificate for every connection: a certificate made again
(delete the two files in `state/truenas/`, not the directory, which a running
container keeps hold of, and run the script with `credentials`) is served at
once, and every fingerprint saved before it is then refused as an untrusted
certificate, which is how a rotated certificate reads in the app.

TrueNAS and Unraid are deterministic transport fixtures, not vendor-certified
servers. They reproduce the JSON shapes, authentication and framing used by
Cupola. Certification against a real TrueNAS/Unraid host remains a separate
environmental test.

The seed is deliberately small and offline: Radarr, Sonarr and Lidarr receive
one resolved media record each; Jellyfin and Plex receive a `Films` library;
qBittorrent and Transmission receive paused zero-data magnets; SABnzbd and
NZBGet receive a disposable NZB; and NPM receives `cupola.test`. Readarr gets
its Books root but no author because metadata lookup would depend on the
public internet. Prowlarr remains an empty indexer registry. Bazarr is
configured for the two arr services but has no subtitle records without a
real media/subtitle provider. These are capability limits of the lab, not
claims that the corresponding Cupola screens are unreachable.

## A household member's own Seerr account

test/e2e/maclab_requester_e2e_test.dart signs in to the lab's Seerr (3.4.1,
set up on the lab's Jellyfin 12.1) the way a household member does, through
Cupola's own code: `SeerrAuthService` for the sign-in, `seerrClientFor` for
the session cookie and the CSRF token, `SeerrAccounts` and the providers for
the account the connection keeps. The offline suite proves the same paths
against the fake Seerr in test/test_helpers/profiles/fakes/seerr_sessions.dart;
this run proves the fake answers the way Seerr does. Where the two disagree,
Seerr wins, and the fake and the app change together.

The bootstrap seeds two accounts, each with REQUEST alone (no manage
permission, no auto-approve): a local Seerr account and a Jellyfin user that
Seerr has imported. Both get new generated passwords on every run, kept only
in the chmod-600 credentials file next to the other lab secrets. The bootstrap
starts the lab and seeds them; a rerun only sets the new passwords:

~~~bash
test/e2e/maclab/bootstrap.sh
flutter test --tags e2e --run-skipped test/e2e/maclab_requester_e2e_test.dart
~~~

The test reads `CUPOLA_MACLAB_CREDENTIALS_FILE` like the other lab tests, and
falls back to .ai/scratch/zz_maclab/state/credentials.env under the working
directory. Asking for a movie needs the lab's Seerr to reach TMDB, so that
step needs the internet. What it proves:

- the sign-in methods `SeerrServerFacts` reads from `/settings/public`;
- an email and a wrong password refused as a wrong password, the right one
  signed in, `/auth/me` read into `SeerrGrant`, the account's own requests
  and quota, and the connection test passing as the account;
- a request made as the account, a 4K one refused as not allowed, and the
  operator's writes (approve, decline) refused as a permission the account
  lacks, never as a refused key or an ended session; the account cancels its
  own pending request; a permission the operator grants reaches the grant;
- a way in the operator turned off after the methods were read, refused in
  the route's words, and a Jellyfin user the server does not take (new
  sign-ins off, never imported) refused as not allowed; the test puts both
  settings back;
- a Jellyfin username and password, and a Quick Connect code approved from
  Jellyfin;
- signing out, after which the server no longer knows the session, and a
  session ended on the server side, read as ended on every request after;
- a connection behind an access gateway (a local proxy started by the test)
  whose custom header reaches Seerr, and the same address without it turned
  away by the gateway;
- with Seerr's CSRF protection on, writes as the key and as an account, a
  sign-in, a Quick Connect code and a sign-out all pass the guard. The test
  turns the setting on, restarts the Seerr container (`docker restart
  cupola-maclab-seerr-1`, or `$CUPOLA_MACLAB_PROJECT-seerr-1`), and puts it
  back the same way when it ends, failed or not.

Never read Seerr's database while its container runs: it writes in SQLite's
WAL mode, and a second reader over the bind mount can lose its recent writes.
Stop the container first, then open state/seerr/db/db.sqlite3. That is how
the session store's expiry was checked: 30 days after the session's last
use, not after its sign-in.

### Signing in with Plex

The Plex group is reported as skipped: it needs a Seerr set up on Plex with a
real plex.tv account, and a person to approve the PIN on app.plex.tv. Run it
by hand on a macOS build of Cupola:

1. Claim the lab's Plex for your own plex.tv account: recreate the container
   with a claim token from https://plex.tv/claim in `PLEX_CLAIM`, or sign in
   at http://127.0.0.1:32400/web.
2. Start a second Seerr on its own port and state directory, from the image
   the Compose file pins:
   `docker run -d --name cupola-maclab-seerr-plex -p 127.0.0.1:5056:5055
   -v "$PWD/.ai/scratch/zz_maclab/state/seerr-plex:/app/config" <image>`.
3. Open http://127.0.0.1:5056 in a browser, sign in with Plex, choose the
   lab's Plex server and finish the setup. To sign in as a household member
   rather than the owner, share the server with a second plex.tv account.
4. In Cupola, add a Seerr connection at http://127.0.0.1:5056, choose to sign
   in with an account, then Plex. Approve Cupola on the Plex page, and check
   that the connection reads signed in with the right name, that a request
   goes through, and that signing out ends the session.
5. Remove the container and its state directory, and revoke Cupola under
   Authorized Devices on plex.tv.

## Native macOS test plan

The service harness is only one layer. A complete run is ordered so a broken
Docker endpoint cannot be mistaken for a UI placeholder:

1. Native preflight: run flutter pub get, flutter analyze --fatal-infos,
   dart format --output=none --set-exit-if-changed ., the offline flutter test
   suite, and flutter build macos (or the unsigned Xcode compile gate when
   signing is unavailable).
2. Lab bootstrap: run the script above, record the Compose project name, and
   run the full transport harness. Stop if a service is missing, returns 401 or
   403, times out, or returns an invalid shape.
3. Cupola configuration: launch with flutter run -d macos or the built app,
   complete onboarding, add every service using the endpoint map, and verify
   each connection row. Credentials remain in the macOS keychain.
4. Route/tab pass: from /stack visit every route produced by serviceTabs
   for each configured service, plus /activity, /search and /settings. Exercise
   cold load, refresh, deep link and back navigation. TrueNAS is the deliberate
   exception to the horizontal service-tab model.
5. State pass: for each service capture success/empty, partial or degraded
   data, rejected credentials, remote error, unreachable host and
   not-configured. The transport tier already verifies rejected credentials
   for sixteen services; Plex needs an authenticated server for that one
   state. Use fixture mutations or an isolated service stop/start, then restore
   the green baseline. An unavailable figure must be an em dash, and a failed
   grid must not be silently reported as a zero total.
6. Integrated flows: test Seerr request -> arr hand-off, arr queue and
   history, Prowlarr application/indexer reads, download queues, Bazarr
   wanted/history, Jellyfin/Plex library/session views, TrueNAS queries,
   Unraid GraphQL reads, and NPM account/proxy/audit reads. Dockge mutations
   are conditional on the separately isolated socket profile.
7. Write pass: run the safe mutations below. Every specimen is disposable;
   qBittorrent and Transmission are deleted, SABnzbd is restored paused,
   NZBGet is deleted from either queue or history, and the NPM flag is restored.
8. Visual matrix: repeat the route/state pass at 1440px desktop, 720px compact
   desktop and 390px portrait, each in dark and light theme. Record screenshots
   by route, state, width and theme. Phone landscape is out of contract.
   Include onboarding, deep links, retry/refresh, semantics and long text.
9. Cleanup and ledger: keep only aggregate results and screenshots under
   disposable .ai/scratch/zz_ paths, run Compose down -v --remove-orphans, and
   record branch, image digests, commands, failures and fixes in the ledger.

The existing integration_test/cupola_native_smoke_test.dart covers the real
bootstrap path from onboarding to dashboard. It is not a substitute for the
route/state/visual pass. Run it separately on a signed macOS target:

~~~bash
flutter test integration_test/cupola_native_smoke_test.dart -d macos
~~~

The reusable full matrix is
integration_test/maclab_ui_matrix_test.dart. It injects the disposable lab settings
inside a test-only ProviderScope, then visits 160 route roots: every ServiceTab
root, every TrueNAS section root, the global/settings roots, and deterministic
detail/editor specimens for Seerr, the arr clients, qBittorrent, Bazarr,
Prowlarr, Dockge, Jellyfin, Plex and TrueNAS. Each route is drawn at all three
sizes and both themes. The test also checks for a Flutter exception immediately
after every viewport resize, before the next route is opened; this keeps an
overflow attributed to the screen that caused it. It writes PNG evidence to
.ai/scratch/zz_maclab/screenshots:

The native runner is sandboxed away from the checkout. Use `flutter drive` with
the host-side driver below: the app process renders the PNG in memory and the
driver writes it back into the checkout, so no sandbox path or network sink is
needed. Before the command, export the disposable credentials into the test
process environment without putting them in the command line or source control:

~~~bash
set -a
. "$CUPOLA_MACLAB_CREDENTIALS_FILE"
set +a
export CUPOLA_MACLAB_DRIVER_SCREENSHOTS=true
export CUPOLA_MACLAB_SCREENSHOT_DIR="$PWD/.ai/scratch/zz_maclab/screenshots"
flutter drive -d macos \
  --target=integration_test/maclab_ui_matrix_test.dart \
  --driver=test_driver/maclab_ui_matrix_driver.dart \
  --dart-define=CUPOLA_MACLAB_SCREENSHOTS=true \
  --dart-define=CUPOLA_MACLAB_DRIVER_SCREENSHOTS=true
~~~

The matrix saves TrueNAS as `https://127.0.0.1:8460` with the recorded
fingerprint as the trusted certificate of that origin, as a person's settings
hold it after they trust the lab's certificate; the credentials it exports
carry `CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT` with the rest. A run without it
stops before the first route and names the missing entry (every `unreachable`
run needs none: nothing is dialled).

This matrix is intentionally separate from onboarding: the native smoke test
proves the real first-run path, while the matrix makes the 17-service visual
coverage repeatable without typing credentials into every run. Detail routes
use deterministic ids and therefore prove route construction, loading and
empty/error rendering even when the disposable vendor databases contain no
media. They do not claim that a populated detail card or a mutating workflow
has been certified; those require seeded records and an explicitly isolated
write pass.

The native driver report becomes unwieldy if all 160 routes are captured in one
process. Use route slices while retaining the same complete 160 x 3 x 2
coverage, for example:

~~~bash
export CUPOLA_MACLAB_ROUTE_OFFSET=108
export CUPOLA_MACLAB_ROUTE_LIMIT=8
export CUPOLA_MACLAB_SCREENSHOT_DIR="$PWD/.ai/scratch/zz_maclab/screenshots"
flutter drive -d macos \
  --target=integration_test/maclab_ui_matrix_test.dart \
  --driver=test_driver/maclab_ui_matrix_driver.dart \
  --dart-define=CUPOLA_MACLAB_SCREENSHOTS=true \
  --dart-define=CUPOLA_MACLAB_DRIVER_SCREENSHOTS=true
~~~

Set `CUPOLA_MACLAB_ROUTE_OFFSET`/`CUPOLA_MACLAB_ROUTE_LIMIT` to successive
slices (or omit them for a no-screenshot smoke pass). Set
`CUPOLA_MACLAB_SIZE=390x844`, `720x450` or `1440x900` to isolate one viewport.
The 17-service transport harness must pass before starting the visual matrix.

The matrix has five explicit scenarios selected with
`CUPOLA_MACLAB_SCENARIO`: `healthy` (the default seeded lab),
`not-configured`, `degraded` (Radarr/Sonarr fail), `unreachable` (all endpoints
fail) and `invalid-auth` (valid URLs with rejected credentials). The latter is
bounded by the disposable qBittorrent seed's high failed-login threshold so a
negative-auth sweep cannot lock the lab out. `CUPOLA_MACLAB_SETTLE_MS` controls
the provider settle window; keep the default 2000ms for evidence and use a
smaller value only for focused diagnostics.

### Verified macOS run

On 2026-09-21 the native macOS runner completed all 160 routes at 1440x900,
720x450 and 390x844 in both themes for `healthy`, `not-configured`, `degraded`,
`unreachable` and `invalid-auth`. The healthy run has 960 PNGs of evidence
(160 routes x 3 sizes x 2 themes). The transport pass reported 18 passing
checks and one explicit Plex skip because the disposable Plex image has local
authentication disabled. The write-safe pass reported five passing mutations;
all specimens were removed or restored.

The write-safe mutation tier is separate from the read-only transport and UI
passes:

~~~bash
export CUPOLA_MACLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_maclab/state/credentials.env"
flutter test test/e2e/maclab_mutation_e2e_test.dart \
  --tags e2e --run-skipped
~~~

It intentionally does not mount the Docker socket into Dockge. Login,
Socket.IO and read-only stack discovery are tested; terminal and stack
deployment require an explicitly isolated socket/proxy profile.

## Cleanup

Keep the project name used by the run, then clean only that disposable project:

~~~bash
docker compose -p "$CUPOLA_MACLAB_PROJECT" \
  -f docker-compose.maclab.yml \
  --profile core --profile downloads --profile media --profile infra \
  --profile protocol-mocks down -v --remove-orphans
~~~

The bootstrap's --reset performs the same project cleanup and removes only the
validated .ai/scratch/zz_maclab/state directory. Never use the personal Docker
socket or a broad recursive cleanup for this lab.
