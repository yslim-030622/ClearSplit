# CI/CD Improvement Plan for ClearSplit

## Current State Analysis

### Existing Workflows
- `backend-ci.yml` - Basic backend tests (Python 3.11, PostgreSQL 16)
- `ios-ci.yml` - Basic iOS build/test (macOS 14)
- `ci.yml` - Duplicate backend tests (Python 3.12, PostgreSQL 14) - **INCONSISTENT**

### Issues Identified
1. ❌ **Duplicate workflows** - Three separate files with overlapping functionality
2. ❌ **No linting/type checking** - Code quality not enforced
3. ❌ **No security scanning** - Vulnerabilities not detected
4. ❌ **No Docker build/push** - Container images not published
5. ❌ **No deployment** - No staging/production deployment
6. ❌ **No code coverage** - Test coverage not tracked
7. ❌ **Inconsistent Python versions** - 3.11 vs 3.12
8. ❌ **No dependency updates** - Dependencies not kept current
9. ❌ **No caching optimization** - Slow builds
10. ❌ **No matrix testing** - Only single Python version tested
11. ❌ **No status checks** - PRs don't require checks to pass
12. ❌ **No secret scanning** - Secrets not validated before commit

---

## Proposed CI/CD Architecture

### Workflow Structure

```
.github/workflows/
├── ci.yml                    # Main CI (lint, type-check, test)
├── docker.yml                # Docker build & push
├── deploy-staging.yml        # Staging deployment
├── deploy-production.yml     # Production deployment (manual)
├── dependency-updates.yml    # Dependabot alternative
└── security-scan.yml        # Security scanning
```

### Workflow Triggers

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push/PR to `main`, `develop` | Quality gates |
| `docker.yml` | Push to `main` | Build & push images |
| `deploy-staging.yml` | Push to `main` | Auto-deploy staging |
| `deploy-production.yml` | Manual | Production deployment |
| `dependency-updates.yml` | Weekly schedule | Dependency updates |
| `security-scan.yml` | Push/PR, weekly | Security scanning |

---

## Improvement Details

### 1. Unified CI Workflow (`ci.yml`)

**Features:**
- ✅ Linting (ruff)
- ✅ Type checking (mypy)
- ✅ Testing (pytest with coverage)
- ✅ Matrix testing (Python 3.11, 3.12)
- ✅ Database migrations check
- ✅ iOS build & test
- ✅ Parallel jobs for speed
- ✅ Caching for dependencies

**Jobs:**
1. `backend-lint` - Code formatting & linting
2. `backend-type-check` - Type checking
3. `backend-test` - Unit & integration tests
4. `backend-migrations` - Migration validation
5. `ios-build` - iOS compilation
6. `ios-test` - iOS unit tests

### 2. Docker Workflow (`docker.yml`)

**Features:**
- ✅ Build Docker image
- ✅ Push to GitHub Container Registry (ghcr.io)
- ✅ Multi-platform builds (linux/amd64)
- ✅ Image tagging (latest, commit SHA, branch name)
- ✅ Security scanning of image

### 3. Deployment Workflows

**Staging:**
- ✅ Auto-deploy on merge to `main`
- ✅ Health check after deployment
- ✅ Rollback on failure

**Production:**
- ✅ Manual trigger only
- ✅ Requires approval
- ✅ Pre-deployment checks
- ✅ Blue-green deployment (future)

### 4. Security Scanning (`security-scan.yml`)

**Features:**
- ✅ Secret scanning (truffleHog, git-secrets)
- ✅ Dependency vulnerability scanning (safety, pip-audit)
- ✅ Container scanning (Trivy)
- ✅ Code security (Bandit)

### 5. Dependency Updates (`dependency-updates.yml`)

**Features:**
- ✅ Weekly dependency check
- ✅ Create PR for updates
- ✅ Test updates before merging

---

## Implementation Plan

### Phase 1: Foundation (Week 1)
1. ✅ Add linting tools (ruff)
2. ✅ Add type checking (mypy)
3. ✅ Create unified `ci.yml`
4. ✅ Add code coverage
5. ✅ Optimize caching

### Phase 2: Quality (Week 2)
1. ✅ Add security scanning
2. ✅ Add Docker build workflow
3. ✅ Add migration validation
4. ✅ Add status checks

### Phase 3: Deployment (Week 3)
1. ✅ Create staging deployment
2. ✅ Set up GitHub Container Registry
3. ✅ Add health checks
4. ✅ Document deployment process

### Phase 4: Automation (Week 4)
1. ✅ Dependency update automation
2. ✅ Release automation
3. ✅ Monitoring integration
4. ✅ Performance testing

---

## Required GitHub Secrets

### For CI/CD
- `DATABASE_URL` - Test database (already in workflow)
- `JWT_SECRET` - Test secret (already in workflow)

### For Docker
- `GITHUB_TOKEN` - Auto-generated (for ghcr.io push)

### For Deployment (Future)
- `STAGING_HOST` - Staging server host
- `STAGING_SSH_KEY` - SSH key for deployment
- `PRODUCTION_HOST` - Production server host
- `PRODUCTION_SSH_KEY` - SSH key for production

---

## Tools to Add

### Backend
```bash
# Add to requirements-dev.txt
ruff==0.1.0          # Fast Python linter
mypy==1.7.0           # Type checker
pytest-cov==4.1.0     # Coverage plugin
safety==2.3.5         # Dependency vulnerability scanner
bandit==1.7.5         # Security linter
```

### CI/CD
- GitHub Actions (already using)
- GitHub Container Registry (ghcr.io)
- Codecov (for coverage reports)

---

## Success Metrics

### Quality
- ✅ 100% of PRs pass linting
- ✅ 100% of PRs pass type checking
- ✅ 80%+ code coverage
- ✅ 0 critical security vulnerabilities

### Speed
- ✅ CI completes in < 10 minutes
- ✅ Docker build in < 5 minutes
- ✅ Deployment in < 5 minutes

### Reliability
- ✅ 99%+ CI success rate
- ✅ Zero failed deployments
- ✅ Automated rollback on failure

---

## Migration Steps

1. **Backup current workflows**
   ```bash
   cp .github/workflows/*.yml .github/workflows/backup/
   ```

2. **Add new tools to requirements**
   ```bash
   # Create requirements-dev.txt
   ```

3. **Create new workflows**
   - Start with `ci.yml`
   - Test on feature branch
   - Merge when stable

4. **Update branch protection**
   - Require `ci.yml` to pass
   - Require `security-scan.yml` to pass

5. **Document changes**
   - Update README
   - Update developer docs

---

## Next Steps

1. Review this plan
2. Approve tool choices
3. Implement Phase 1
4. Test on feature branch
5. Merge to main

---

*Last updated: January 2025*
