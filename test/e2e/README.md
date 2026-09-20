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
