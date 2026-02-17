# Security Guide

This document describes the current security controls and operational expectations for ClearSplit.

## Identity and Authentication

- Access tokens are JWTs with explicit token type claims.
- Refresh tokens include unique JTIs and are persisted server-side.
- Refresh flow revokes old token records and issues replacement JTIs.
- Passwords are hashed with bcrypt.

## Authorization Model

Membership roles drive permissions:

- `owner`: full group administration and override permissions
- `member`: standard group participation
- `viewer`: read-only for financial and shopping mutations

Service-layer authorization checks enforce endpoint restrictions beyond route-level auth.

## Request Abuse Controls

- process-local rate limits protect signup, login, and member-invite preview routes
- trusted proxy header use is disabled by default and requires explicit allowlist configuration

Process-local limiter caveat:
- current rate-limit counters live in app process memory only
- when running multiple API replicas, each replica enforces limits independently
- for strict global limits across replicas, use a shared backend (for example Redis)

## Idempotency and Replay Safety

- idempotency key support exists for key mutation endpoints (`expenses`, settlement compute)
- refresh token replay is blocked through persisted JTI rotation logic

## Data and Transport Safety

- non-local CORS origins must be explicit HTTPS origins
- database TLS is enforced by default in non-local environments when URL does not specify SSL behavior
- invalid/ambiguous SSL URL query combinations are rejected

## Receipt Upload and OCR Safety

Receipt processing includes:
- content type checks (`image/*`)
- safe image decode with decompression-bomb protections
- max file-size and max-pixel validation
- strict accepted image formats (JPEG, PNG, WEBP, GIF)
- OCR concurrency cap and request timeout

## Secret Handling Expectations

- keep secrets out of source control
- use environment variables for credentials and keys
- avoid hardcoded tokens/passwords in app code and scripts

Repo checks:

```bash
./scripts/secret-scan.sh
./scripts/verify-security.sh
```

## Incident Response Baseline

If a credential leak is suspected:

1. rotate affected credentials immediately
2. invalidate active refresh-token chains when appropriate
3. review recent commits, CI logs, and object-storage access
4. run secret scan and patch root cause before redeploy

## Deployment Checklist

Before promotion to staging/production:

- set non-local `CORS_ORIGINS` to trusted HTTPS origins only
- set strong `JWT_SECRET`
- verify database SSL configuration
- verify S3 permissions are least-privilege
- run backend tests and security checks
