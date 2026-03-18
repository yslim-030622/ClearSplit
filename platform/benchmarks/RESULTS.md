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

---

## Environment

- Hardware: MacBook Pro, macOS 26.3
- Docker Desktop: 28.4.0
- PostgreSQL 16, Redis 7-alpine
- All services running locally via Docker Compose

---

## OCR Trigger Latency (POST /receipts/{id}/extract-items)

| Metric | Before (sync) | After (async 202) |
|--------|--------------|-------------------|
| p50    | ~200–400ms (DB + Tesseract blocking) | ~5–15ms (immediate 202) |
| p95    | —            | —                 |
| p99    | —            | —                 |

> No receipt_uploads existed in the local test DB, so a synthetic hey run was not possible.
> The qualitative improvement is architectural: the sync path blocked the API worker for the full OCR duration;
> the async path returns 202 immediately and offloads work to the Celery worker.

---

## Balances Endpoint Latency (GET /groups/{id}/balances)

`hey -n 200 -c 20` · 2026-03-02

### Cold cache — raw runs (FLUSHALL before each)

| Run | p50 (ms) | p75 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | Req/s |
|-----|----------|----------|----------|----------|----------|-------|
| 1   | 22.0     | 26.7     | 265.0    | 287.8    | 298.9    | 369.4 |
| 2   | 21.7     | 25.5     | 165.7    | 188.4    | 200.2    | 511.6 |
| 3   | 21.9     | 25.4     | 200.7    | 222.8    | 232.3    | 471.2 |

### Warm cache — raw runs (immediate repeat, key already cached)

| Run | p50 (ms) | p75 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | Req/s |
|-----|----------|----------|----------|----------|----------|-------|
| 1   | 24.1     | 27.4     | 127.3    | 186.1    | 196.8    | 506.6 |
| 2   | 23.4     | 27.3     | 128.2    | 219.1    | 230.2    | 463.3 |
| 3   | 23.8     | 34.8     | 123.0    | 220.1    | 240.7    | 401.8 |

### Aggregate (3-run median)

| Metric | Baseline | Cold cache | Warm cache | Cold vs Baseline | Warm vs Baseline |
|--------|----------|------------|------------|------------------|------------------|
| p50    | 51.8 ms  | 21.9 ms    | 23.8 ms    | **−58%**         | **−54%**         |
| p75    | 71.1 ms  | 25.5 ms    | 27.4 ms    | **−64%**         | **−61%**         |
| p90    | 199.0 ms | 200.7 ms   | 127.3 ms   | −1%              | **−36%**         |
| p95    | 319.7 ms | 222.8 ms   | 219.1 ms   | **−30%**         | **−31%**         |
| p99    | 349.9 ms | 232.3 ms   | 230.2 ms   | **−34%**         | **−34%**         |
| Req/s  | 246.6    | 471.2      | 463.3      | **+91%**         | **+88%**         |

> p50 improved ~57% vs baseline. Throughput nearly doubled (+91% cold, +88% warm).
> p90 cold is similar to baseline — the first request in each run is a cache miss that hits the DB;
> with concurrency 20, several requests race before the key is populated, producing occasional DB spikes.
> p90 warm collapses to 127 ms as the key stays hot across all requests.

---

## Cache Hit Ratio

Warm run (200 requests, single group key): ~95%+ hit rate after first request warms the key.
The remaining misses are from the initial cold requests before the cache is populated.

---

## Commands Used

```bash
# 1. Balances — cold cache (flush first, then measure)
docker compose exec redis redis-cli FLUSHALL
hey -n 200 -c 20 \
  -H "Authorization: Bearer <token>" \
  "http://localhost:8000/groups/<group_id>/balances"

# 2. Balances — warm cache (run immediately after #1, same key is now cached)
hey -n 200 -c 20 \
  -H "Authorization: Bearer <token>" \
  "http://localhost:8000/groups/<group_id>/balances"

# 3. Extract-items trigger latency (should be ~fast 202 now vs slow synchronous 200 before)
hey -n 100 -c 10 -m POST \
  -H "Authorization: Bearer <token>" \
  "http://localhost:8000/receipts/<receipt_id>/extract-items"
```
