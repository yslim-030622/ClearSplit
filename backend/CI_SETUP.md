# CI/CD Documentation

## GitHub Actions CI

The project uses GitHub Actions to automatically run tests on every push and pull request.

### What CI Does

1. **Sets up environment**:
   - Python 3.12
   - PostgreSQL 14 service
   - All dependencies from `requirements.txt`

2. **Runs database migrations**:
   - `alembic upgrade head`

3. **Executes full test suite**:
   - `pytest -q` (quiet mode)
   - `pytest -v` (verbose on failure)

### CI Configuration

**File**: `.github/workflows/ci.yml`

**Triggers**:
- Push to: `main`, `develop`, or any `fix/*` branch
- Pull requests to: `main` or `develop`

**Environment Variables** (set automatically in CI):
```bash
ENV=test
DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit
JWT_SECRET=test-secret-key-for-ci-only-not-for-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
```

### Reproducing CI Locally

To run the same tests that CI runs:

```bash
# 1. Ensure PostgreSQL is running
docker-compose up -d

# 2. Ensure migrations are applied
cd backend
source .venv/bin/activate
alembic upgrade head

# 3. Run tests (same command as CI)
pytest -q --tb=short

# Expected output:
# 48 passed, 106 warnings in ~18s
```

### CI Service: PostgreSQL

**Image**: `postgres:14`
**Credentials**:
- User: `clearsplit`
- Password: `clearsplit`
- Database: `clearsplit`
- Port: `5432`

**Health Check**:
- Command: `pg_isready`
- Interval: 10s
- Timeout: 5s
- Retries: 5

This ensures PostgreSQL is fully ready before tests run.

### Troubleshooting CI Failures

#### Connection Issues
If you see `connection refused` errors:
- The PostgreSQL health check ensures DB is ready
- Check if migrations ran successfully
- Verify `DATABASE_URL` format matches async driver (`asyncpg`)

#### Migration Issues
If `alembic upgrade head` fails:
- Ensure all migration files are committed
- Check for syntax errors in migrations
- Verify `alembic.ini` is correctly configured

#### Test Failures
If tests fail in CI but pass locally:
- Check environment variables match
- Ensure same Python version (3.12)
- Verify same PostgreSQL version (14)
- Run locally with same commands as CI

### CI Success Criteria

✅ **All 48 tests must pass**
- No skipped tests
- No infrastructure errors
- No timing issues

### Adding New Tests

When adding new tests:
1. Ensure they pass locally: `pytest -q`
2. Push to your branch
3. CI will automatically run on push
4. Check GitHub Actions tab for results
5. Fix any failures before merging

### Performance

**Typical CI run time**: 1-2 minutes
- Setup: ~20s
- Dependencies: ~15s (cached after first run)
- Migrations: ~5s
- Tests: ~20s

### Cache

**pip cache** is enabled:
- Dependencies are cached between runs
- Faster subsequent builds
- Cache key: `requirements.txt` hash

### Maintenance

**When to update CI**:
- Python version changes → Update `python-version` in workflow
- PostgreSQL version changes → Update service `image` version
- New environment variables → Add to `.env` creation step
- New dependencies → They'll auto-install from `requirements.txt`

### Status Badge

Add to README.md:
```markdown
![CI](https://github.com/YOUR_USERNAME/ClearSplit/workflows/CI/badge.svg)
```

---

**Last Updated**: December 2024
**Status**: ✅ 48/48 tests passing

