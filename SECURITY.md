# Security Policy

## Secret Management

### 🔐 Critical Rules

**NEVER commit secrets to git!**

- ❌ No hardcoded passwords, API keys, JWT secrets, or database credentials
- ❌ No `.env` files with real secrets (except `.env.example` with placeholders)
- ✅ Use `.env.local` for local development (gitignored)
- ✅ Use GitHub Secrets for CI/CD
- ✅ Use platform secret managers (AWS Secrets Manager, etc.) for production

### Required Secrets

All environments require these secrets:

1. **`DATABASE_URL`** - PostgreSQL connection string
   ```
   postgresql+asyncpg://user:password@host:port/database
   ```

2. **`JWT_SECRET`** - Secret key for JWT token signing
   ```bash
   # Generate a strong secret:
   openssl rand -hex 32
   ```

### Local Development Setup

```bash
# 1. Copy the example env file
cp .env.example .env.local

# 2. Generate a JWT secret
openssl rand -hex 32

# 3. Edit .env.local with your real values
# Never commit .env.local!

# 4. Run the application
cd backend
source .venv/bin/activate
alembic upgrade head
uvicorn app.main:app --reload
```

### CI/CD Setup (GitHub Actions)

Secrets are injected via environment variables in workflow files:

```yaml
- name: Create .env file for tests
  run: |
    echo "ENV=test" > backend/.env
    echo "DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit" >> backend/.env
    echo "JWT_SECRET=test-secret-key-for-ci-only-not-for-production" >> backend/.env
```

For production deployments, use GitHub Secrets:

```yaml
env:
  JWT_SECRET: ${{ secrets.JWT_SECRET }}
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

### Production Deployment

1. **Never use default/example secrets in production**
2. Use your platform's secret management:
   - AWS: Secrets Manager or Parameter Store
   - Azure: Key Vault
   - GCP: Secret Manager
   - Kubernetes: Sealed Secrets or External Secrets Operator
3. Rotate secrets regularly (every 90 days recommended)
4. Use strong secrets:
   - JWT_SECRET: minimum 64 characters (32 bytes hex)
   - Database passwords: 20+ characters, alphanumeric + symbols

### Secret Rotation Procedure

If a secret is compromised or needs rotation:

1. **Generate new secret**
   ```bash
   openssl rand -hex 32
   ```

2. **Update in all environments**
   - Local: Update `.env.local`
   - CI: Update GitHub Secrets
   - Production: Update secret manager + restart services

3. **For JWT_SECRET rotation:**
   - Deploy new secret alongside old one temporarily
   - Set grace period for old tokens to expire
   - After grace period, remove old secret
   - All users will need to re-authenticate

4. **For DATABASE_URL rotation:**
   - Create new database credentials
   - Update connection strings
   - Revoke old credentials after verification

### What to Do If You Accidentally Commit a Secret

**ACT IMMEDIATELY:**

1. **Rotate the secret** - The committed secret is now compromised
2. **Remove from git history:**
   ```bash
   # Use git-filter-repo (recommended) or BFG Repo-Cleaner
   pip install git-filter-repo
   git filter-repo --path backend/.env --invert-paths --force
   ```
3. **Force push** (coordinate with team):
   ```bash
   git push --force --all
   git push --force --tags
   ```
4. **Update all environments** with the new rotated secret
5. **Review access logs** for any suspicious activity

### Pre-commit Secret Scanning

Before pushing code, run the secret scanner:

```bash
./scripts/secret-scan.sh
```

This will detect common secret patterns. If secrets are found, **DO NOT PUSH**.

### Reporting Security Vulnerabilities

If you discover a security vulnerability, please email: **security@clearsplit.dev**

Do NOT create public GitHub issues for security vulnerabilities.

### Security Checklist for Developers

- [ ] I have not hardcoded any secrets
- [ ] My `.env.local` is gitignored and not committed
- [ ] I ran `./scripts/secret-scan.sh` before pushing
- [ ] I used `SecretStr` in Pydantic models for sensitive fields
- [ ] Production secrets use 64+ character random values
- [ ] I verified: `git ls-files | grep -E "\.env"` only shows `.env.example`

### Additional Resources

- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [12-Factor App: Config](https://12factor.net/config)

