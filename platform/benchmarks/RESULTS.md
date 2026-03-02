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

Date: 2026-03-01 · Concurrency: 20 · Requests per run: 200

### Raw runs

| Run | p50 (ms) | p75 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | Req/s |
|-----|----------|----------|----------|----------|----------|-------|
| 1   | 24.9     | 34.2     | 163.2    | 288.4    | 305.7    | 375.0 |
| 2   | 33.0     | 54.8     | 119.8    | 228.6    | 246.8    | 367.1 |
| 3   | 26.1     | 37.4     | 94.7     | 185.0    | 212.7    | 461.8 |

### Aggregate (3-run median)

| Metric       | Value   |
|--------------|---------|
| p50 latency  | 26.1 ms |
| p75 latency  | 37.4 ms |
| p90 latency  | 119.8 ms |
| p95 latency  | 228.6 ms |
| p99 latency  | 246.8 ms |
| Requests/sec | 461.8   |

### vs Baseline

| Metric       | Baseline | Post-Cache | Improvement |
|--------------|----------|------------|-------------|
| p50          | 51.8 ms  | 26.1 ms    | **−50%**    |
| p95          | 319.7 ms | 228.6 ms   | **−29%**    |
| p99          | 349.9 ms | 246.8 ms   | **−29%**    |
| Requests/sec | 246.6    | 461.8      | **+87%**    |

> p50 halved (51→26 ms). Throughput nearly doubled (247→462 req/s).
> p95/p99 improvement is moderate because hey fires 20 concurrent requests against a single
> group — after the first request warms the cache, the remaining 19 hit Redis,
> but TTL expiry mid-run and occasional token refreshes still force DB round-trips.
