# Security Guide

This document describes the security controls, operational expectations, and incident response procedures for ClearSplit.

## Identity and Authentication

- Access tokens are JWTs (HS256) with explicit token type claims (`access` vs `refresh`) and 15-minute expiry
- Refresh tokens include unique JTIs and are persisted server-side in the `refresh_tokens` table
- Refresh rotation: old token is revoked (`revoked_at` set, `replaced_by_jti` recorded), new token issued with fresh JTI
- Replaying a revoked refresh token returns 401
- Passwords are hashed with bcrypt via `bcrypt.gensalt()`
- Login is timing-attack resistant: always runs password verification (dummy hash for unknown users)
- Case-insensitive identity normalization: emails and usernames lowercased before storage and lookup
- Case-insensitive unique database indices prevent duplicate accounts

## Authorization Model

Membership roles drive permissions:

- `owner`: full group administration, member management, and override permissions
- `member`: standard group participation with endpoint-specific mutation rights
- `viewer`: read-only for financial and shopping mutations

Service-layer authorization checks enforce endpoint restrictions beyond route-level auth. Key rules:

| Action | Allowed By |
|--------|-----------|
| Group deletion | Owner only |
| Member management | Owner only |
| Expense creation | Non-viewer (payer must be caller) |
| Shopping session control | Payer only |
| Item edit/delete | Creator, payer, or owner |
| Receipt OCR trigger | Uploader only |
| Settlement payment confirm | Receiver or owner |

## Request Abuse Controls

- Process-local sliding window rate limiter protects:
  - Signup: 5 attempts per 5 minutes per IP
  - Login: 10 attempts per 60 seconds per IP
  - Member preview: 30 requests per 60 seconds per group/user/IP
- Trusted proxy header use (`X-Forwarded-For`, `X-Real-IP`) is disabled by default (`TRUST_PROXY_HEADERS=false`)
- When enabled, proxy headers are validated against an explicit IP allowlist (`TRUSTED_PROXY_IPS`)
- Rate limiting is disabled in test environment

**Process-local limiter caveat**: Current rate-limit counters live in app process memory only. When running multiple API replicas, each replica enforces limits independently. For strict global limits across replicas, use a shared backend (e.g., Redis).

## Idempotency and Replay Safety

- `Idempotency-Key` header support for key mutation endpoints (expense creation, settlement compute)
- Same key + same payload returns cached response; same key + different payload returns 409
- Refresh token replay is blocked through persisted JTI rotation logic
- Keys scoped to endpoint + user ID + key value (max 255 characters)

## Transport and Header Security

- Non-local CORS origins must be explicit HTTPS origins (validated at app startup)
- Database TLS is enforced by default in non-local environments when URL does not specify SSL behavior
- Invalid or ambiguous SSL URL query combinations are rejected

Security headers added via middleware:

| Header | Value | Scope |
|--------|-------|-------|
| `X-Content-Type-Options` | `nosniff` | All environments |
| `X-Frame-Options` | `DENY` | All environments |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | All environments |
| `X-Permitted-Cross-Domain-Policies` | `none` | All environments |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` | Non-local only |

Additional protections:
- API documentation endpoints (`/docs`, `/redoc`, `/openapi.json`) disabled in non-local environments
- Validation error responses are sanitized: raw input values stripped to prevent password/secret leakage in error messages

## Receipt Upload and OCR Safety

Receipt processing includes multiple validation layers:

- Content type enforcement (`image/*` only)
- Accepted formats: JPEG, PNG, WEBP, GIF
- Maximum file size: 10 MB (configurable via `MAX_RECEIPT_BYTES`)
- Maximum pixel count: 25M (configurable via `MAX_RECEIPT_PIXELS`)
- Pillow decompression-bomb protection active
- OCR concurrency capped at 2 concurrent requests (configurable via `MAX_OCR_CONCURRENCY`)
- S3 storage with private bucket policy and time-limited presigned download URLs (15-min default)

## Secret Management

### Code-Level Controls

- All secrets loaded via environment variables using Pydantic `SecretStr` type
- Secrets accessed via `.get_secret_value()` method (never exposed in string representations or logs)
- `.env` and `.env.local` files are gitignored; `.env.example` provided as template
- JWT secret requires minimum 32 characters

### Repository Scanning

Local pre-commit hook runs custom secret scanner on every commit:

```bash
./scripts/secret-scan.sh
```

Scans for:
- Hardcoded JWT secrets and passwords
- Database URLs with embedded credentials
- API keys and AWS access keys (AKIA* pattern)
- Private key headers (RSA, DSA, EC, OpenSSH)
- Generic token patterns
- Tracked `.env` files (fails if found)
- Dummy/test secrets in non-test code (warns)

Security baseline verification:

```bash
./scripts/verify-security.sh
```

Validates:
- `.gitignore` excludes `.env` and `.env.*`
- No `.env` files tracked (except `.env.example`)
- `scripts/secret-scan.sh` exists and is executable
- `SECURITY.md` exists
- `config.py` uses `SecretStr` type
- Code uses getter methods for secret access

### CI/CD Scanning

| Tool | Scope | Trigger |
|------|-------|---------|
| TruffleHog | Verified secrets in git history | PRs, push, weekly |
| pip-audit | CVE detection in Python dependencies | PRs, push, weekly |
| Bandit | Python code security patterns | PRs, push, weekly |
| Trivy | Container image vulnerabilities (HIGH/CRITICAL) | Docker builds, staging deploy |

## Incident Response Baseline

If a credential leak is suspected:

1. **Rotate** affected credentials immediately (JWT secret, database password, AWS keys)
2. **Invalidate** active refresh-token chains when appropriate (truncate `refresh_tokens` table)
3. **Review** recent commits, CI logs, and S3/object-storage access logs
4. **Scan** repository with `./scripts/secret-scan.sh` and CI security workflows
5. **Patch** root cause and verify fix before redeployment
6. **Audit** `activity_logs` table for suspicious group/financial activity

## Deployment Checklist

Before promotion to staging or production:

- [ ] Set non-local `CORS_ORIGINS` to trusted HTTPS origins only
- [ ] Generate strong `JWT_SECRET` (64+ characters recommended, cryptographically random)
- [ ] Verify database SSL configuration (`sslmode=require` in connection URL)
- [ ] Verify S3 bucket permissions are least-privilege (no public access)
- [ ] Run backend tests with staging coverage threshold (80%)
- [ ] Run security scan workflow (TruffleHog + pip-audit + Bandit)
- [ ] Verify Trivy container scan passes (no HIGH/CRITICAL vulnerabilities)
- [ ] Confirm Azure OIDC credentials are configured (no static secrets)
- [ ] Verify health check endpoints respond (`/health/live`, `/health/ready`)
