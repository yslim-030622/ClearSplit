# CI/CD Workflows

This directory contains GitHub Actions workflows for ClearSplit.

## Workflows

### `ci.yml` - Main CI Pipeline
**Triggers:** Push/PR to `main`, `develop`

**Jobs:**
- `backend-lint` - Code linting with ruff
- `backend-type-check` - Type checking with mypy
- `backend-test` - Tests with pytest (Python 3.11, 3.12)
- `backend-migrations` - Database migration validation
- `ios-build` - iOS app compilation
- `ios-test` - iOS unit tests

**Status:** ✅ Required for PRs

---

### `docker.yml` - Docker Build & Push
**Triggers:** Push to `main`, tags `v*`, manual

**Jobs:**
- Builds Docker image for backend API
- Pushes to GitHub Container Registry (ghcr.io)
- Scans image with Trivy for vulnerabilities

**Image Tags:**
- `latest` - Latest main branch
- `main-<sha>` - Commit SHA
- `v1.0.0` - Semantic version tags

---

### `security-scan.yml` - Security Scanning
**Triggers:** Push/PR to `main`, `develop`, weekly schedule

**Jobs:**
- `secret-scan` - Scans for hardcoded secrets
- `dependency-scan` - Checks for vulnerable dependencies
- `code-security` - Bandit security linting

**Status:** ⚠️ Non-blocking (reports only)

---

### `deploy-staging.yml` - Staging Deployment
**Triggers:** Push to `main`, manual

**Jobs:**
- Deploys to staging environment
- Health check after deployment
- Rollback on failure

**Status:** 🔧 Template - needs deployment method configuration

---

## Workflow Status

| Workflow | Status | Required for PR |
|----------|--------|----------------|
| `ci.yml` | ✅ Active | Yes |
| `docker.yml` | ✅ Active | No |
| `security-scan.yml` | ✅ Active | No |
| `deploy-staging.yml` | 🔧 Template | No |

---

## Local Testing

### Backend
```bash
cd backend

# Linting
ruff check app/
ruff format app/

# Type checking
mypy app/ --ignore-missing-imports

# Tests
pytest --cov=app
```

### iOS
```bash
cd ios/ClearSplit

# Build
xcodebuild -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15' build

# Tests
xcodebuild test -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Adding New Workflows

1. Create `.yml` file in `.github/workflows/`
2. Follow existing patterns
3. Test on feature branch first
4. Document in this README

---

## Troubleshooting

### CI Failing
1. Check workflow logs in GitHub Actions
2. Run commands locally to reproduce
3. Check for dependency updates
4. Verify environment variables

### Docker Build Failing
1. Test Dockerfile locally: `docker build -t test ./backend`
2. Check registry permissions
3. Verify image tags

### Security Scan False Positives
1. Review scan results
2. Add exceptions if needed (`.bandit`, `safety.toml`)
3. Update workflow to ignore specific checks

---

*Last updated: January 2025*
