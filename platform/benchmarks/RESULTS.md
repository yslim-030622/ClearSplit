# ClearSplit Scalability Benchmarks

Endpoint under test: `GET /groups/{group_id}/balances`
Tool: [hey](https://github.com/rakyll/hey) · `-n 200 -c 20`
Environment: local Docker Compose (db + api, no Redis caching active)

---

## Baseline (no cache)

Date: 2026-03-01 · Concurrency: 20 · Requests per run: 200

### Raw runs

| Run | p50 (ms) | p75 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | Req/s |
|-----|----------|----------|----------|----------|----------|-------|
| 1   | 55.6     | 85.5     | 323.5    | 365.1    | 409.0    | 212.5 |
| 2   | 51.8     | 71.1     | 199.0    | 319.7    | 349.9    | 246.6 |
| 3   | 48.5     | 60.1     | 152.1    | 243.6    | 272.5    | 295.0 |

### Aggregate (3-run median)

| Metric      | Value   |
|-------------|---------|
| p50 latency | 51.8 ms |
| p75 latency | 71.1 ms |
| p90 latency | 199.0 ms |
| p95 latency | 319.7 ms |
| p99 latency | 349.9 ms |
| Requests/sec | 246.6  |

> p90–p99 spread is wide (199–350 ms) — typical of synchronous DB queries with occasional lock contention under concurrency 20.
> This is the target to beat in Phase 2 (cache hit should collapse p95/p99 to sub-10 ms).

---

## Post-Cache (Phase 2)

_(to be filled after Phase 2 is complete)_
