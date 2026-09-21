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
the disposable container is running with local authentication disabled, since
that mode accepts an arbitrary `X-Plex-Token`; use a claimed/authenticated Plex
server for the token-rejection check.

## Published endpoint map

| Service | Native endpoint | Auth in the lab | Transport |
|---|---|---|---|
| Seerr | http://127.0.0.1:5055 | generated API key | REST |
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
| Jellyfin | http://127.0.0.1:8096 | generated token + user id | REST |
| Plex | http://127.0.0.1:32400 | local auth disabled in the disposable image | REST/XML-or-JSON |
| Dockge | http://127.0.0.1:5001 | disposable account provisioned by bootstrap | Socket.IO |
| Nginx Proxy Manager | http://127.0.0.1:8181 | admin@example.com / changeme | REST + JWT |
| TrueNAS fixture | ws://127.0.0.1:8460 | test-key | WebSocket JSON-RPC |
| Unraid fixture | http://127.0.0.1:8480/graphql | test-key | GraphQL |

qBittorrent 5.1 validates the Host/Origin port, so the full lab uses host
port 8080 for qBittorrent and 8082 for SABnzbd. Transmission's LinuxServer
image consumes USER/PASS; the Compose file uses those names and the harness
asserts both the 409 CSRF challenge and the 401 wrong-password path.
Plex is intentionally a transport/shape fixture here, not an
authenticated-token fixture: obtaining a real claim token would make the lab
depend on an external Plex account.

Dockge deliberately has no Docker socket mounted. Login, Socket.IO session and
read-only stack discovery are safe to test. Terminal and stack-mutating
capabilities require a separately approved disposable Docker socket/proxy and
are not silently granted by this compose file.

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
4. Route/tab pass: from /dashboard visit every route produced by serviceTabs
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
