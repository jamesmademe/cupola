# E2E tier (tag: `e2e`)

Tier-6 headless tests (plan §7.6) that drive the **real** service clients over
real HTTP against Docker instances. They are **not** part of the offline
`flutter test` gate — `dart_test.yaml` auto-skips the `e2e` tag.

## Run

```bash
docker compose -f docker-compose.e2e.yml up -d --wait   # from repo root
flutter test --tags e2e --run-skipped
docker compose -f docker-compose.e2e.yml down -v
```

Readarr is considered ready only when its authenticated
`/api/v1/system/status` endpoint answers successfully. The tagged Dart suite
repeats that probe before exercising the client, so a missing container,
transport failure, HTTP error, or invalid API key cannot be mistaken for an
empty library. The Compose healthcheck uses `curl` already present in the
LinuxServer image and is a readiness aid; the Dart probe remains the test
assertion.

## Coverage

| Service  | Covered here | Notes |
|----------|--------------|-------|
| SABnzbd  | ✅ | via `127.0.0.1` + `host_whitelist` in the seed .ini; pinned multi-arch image |
| NZBGet   | ✅ | Basic auth + positional JSON-RPC + Hi/Lo; pinned multi-arch image |
| Readarr  | ✅ | `X-Api-Key`, *arr v1 contract (pinned multi-arch develop image) |
| Unraid   | ❌ | no OS container — stays schema-only (tiers 2-3). See §7.6 |

Seed configs live under `test/e2e/seed/`; credentials are deterministic
(`api_key=test-key`, `nzbget:tegbzn6789`). Capturing a live response here is the
moment to refresh the committed fixtures/contract (plan §7.4).

Nota di isolamento: il compose minimo attuale monta le directory seed di SABnzbd e Readarr come
`/config`, quindi i servizi possono materializzare database, log e backup accanto alla fixture. Il
run va sempre chiuso con `down -v` e il tree va controllato prima del commit; il laboratorio macOS
completo deve copiare i seed in una directory per-run o inizializzare volumi nominati disposable,
mai scrivere direttamente nelle fixture tracciate.

## Piano laboratorio completo su macOS

Il tier sopra resta il gate Docker piccolo e riproducibile. Il laboratorio completo macOS è un
secondo tier pianificato: l'app gira nativa con `flutter run -d macos` o con
`integration_test -d macos`, mentre i servizi girano in un progetto Docker Compose dedicato. Non
va trattato come già verde finché il compose e i seed non saranno aggiunti e il run non sarà
registrato nel completion ledger.

### Perimetro

Il lab deve coprire i quindici servizi che hanno un'immagine container affidabile, più due mock
deterministici per i trasporti che non sono riproducibili in un container generico:

| Gruppo | Servizi | Contratto principale |
|---------|---------|----------------------|
| *arr / discovery | Seerr, Radarr, Sonarr, Lidarr, Readarr, Prowlarr, Bazarr | REST + API key |
| download | qBittorrent, Transmission, SABnzbd, NZBGet | WebUI/API, RPC, form/cookie |
| media / ops | Jellyfin, Plex, Dockge, Nginx Proxy Manager | REST, Socket.IO, Docker control |
| protocol mocks | Unraid, TrueNAS | GraphQL, WebSocket JSON-RPC |

Unraid e TrueNAS non sono “servizi Docker equivalenti”: il primo espone GraphQL su un sistema
Unraid reale, il secondo JSON-RPC 2.0 su WebSocket. I mock devono quindi riprodurre framing,
autenticazione, errori e payload del contratto usato da Cupola; la certificazione vendor richiede
una VM o un host reale separato.

### Isolamento e riproducibilità

- usare un project name univoco, ad esempio `cupola-maclab-$RUN_ID`, e dati sotto una directory
  disposable; mai riusare il volume di un'installazione personale;
- pubblicare ogni porta solo su `127.0.0.1`, con una tabella di port mapping stabile verso
  `ServiceKey`; dall'interno dei container usare la rete Compose e dall'app nativa usare
  `localhost`;
- dividere il compose in profili `core`, `downloads`, `media`, `infra` e `protocol-mocks`, così
  il loop quotidiano può avviare un sottoinsieme ma il gate completo li abilita tutti;
- fissare immagini e versioni (mai `latest`), verificare l'architettura su Apple Silicon e usare
  `platform: linux/amd64` solo per immagini realmente x86-only;
- seedare utenti, API key, librerie, job, queue, errori e dati paginati da fixture locali. Nessun
  test deve dipendere da indexer pubblici, download esterni o credenziali reali;
- aggiungere healthcheck autenticati sulle API rilevanti: un container “running” non è un servizio
  pronto. Il test Dart deve ripetere la probe e fallire se riceve 401, 403, timeout o payload
  invalido;
- Dockge richiede accesso al Docker socket per le prove terminale/stack: montare solo il socket di
  un Docker Desktop/VM disposable e non quello usato per workload personali. Per il normale CI
  offline usare invece un mock Socket.IO.

### Run contract previsto

Quando `docker-compose.maclab.yml` sarà implementato, il run canonico sarà:

```bash
docker context show
docker version
docker compose version

export CUPOLA_MACLAB_PROJECT="cupola-maclab-$(date +%Y%m%d%H%M%S)"
docker compose -p "$CUPOLA_MACLAB_PROJECT" -f docker-compose.maclab.yml \
  --profile core --profile downloads --profile media --profile infra --profile protocol-mocks \
  up -d --wait

flutter test --tags e2e --run-skipped
flutter test integration_test/cupola_native_smoke_test.dart -d macos

docker compose -p "$CUPOLA_MACLAB_PROJECT" -f docker-compose.maclab.yml \
  down -v --remove-orphans
```

Per un checkout nuovo il preflight nativo è separato dal lab: `flutter pub get`/`flutter build
macos --debug` genera Pods ed ephemeral file. Il build Flutter e l'avvio di
`integration_test -d macos` richiedono il provisioning profile per `com.matthwlabs.cupola`; senza
profilo si può comunque verificare la compilazione con:

```bash
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk macosx CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Questo è un compile gate, non una prova di esecuzione o di integrazione UI. Il gate completo deve
usare un Mac con signing funzionante, avviare l'app nativa e registrare gli screenshot insieme ai
risultati E2E Docker.

Il cleanup va eseguire anche dopo un fallimento, con il project name conservato nel log. Le porte
devono restare coerenti con il registry: Seerr 5055, gli *arr secondo le porte standard, download
8080/6789/9091, Jellyfin 8096, Plex 32400, Dockge 5001 e NPM 81. Il test può usare
`host.docker.internal` solo quando un container deve raggiungere un endpoint sul Mac; l'app Flutter
che gira nativa deve usare gli indirizzi pubblicati su localhost.

### Livelli di verifica

1. **Bootstrap:** tutti i 17 endpoint rispondono, autenticazione corretta e trust TLS verificabile.
2. **Contratto per tab:** per ogni `ServiceTab` si esercitano success, empty, degraded/error,
   unreachable/not-configured, dati parziali, refresh e multi-instance dove applicabile.
3. **Flussi integrati:** Seerr → *arr → download → libreria; Prowlarr → *arr; Bazarr; sessioni
   Jellyfin/Plex; Dockge stack/terminal; NPM access/audit; query Unraid e WebSocket TrueNAS.
4. **Resilienza e sicurezza:** credenziali errate, 401/403, timeout, certificato self-signed,
   paginazione, titoli/log molto lunghi, capability parziale e azioni mutative ripetute.
5. **Visual/native:** screenshot bounded su macOS a 1440/720/390 portrait, dark/light e stati
   principali; onboarding, deep link, tab, retry/refresh e accessibilità. Il risultato entra nel
   ledger insieme al commit e non sostituisce `flutter analyze`, format, suite offline e contract
   test.

Il primo passaggio utile è implementare il compose in un branch separato, partire da profili e
healthcheck, poi aggiungere un servizio alla volta alla matrice. Solo dopo che il run completo è
ripetibile si può promuovere il tier a gate di rilascio.
