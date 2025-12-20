# Docker Deployment Guide

## Published Images

ClearSplit backend images are automatically published to GitHub Container Registry (GHCR) on every push to `main` and on version tags.

**Registry**: `ghcr.io/yslim-030622/clearsplit/api`

### Available Tags

| Tag Format | When Published | Example |
|------------|----------------|---------|
| `latest` | Every push to main | `latest` |
| `main-<sha>` | Every push to main | `main-abc1234` |
| `v<version>` | Version tags | `v1.0.0` |
| `<major>.<minor>` | Version tags | `1.0` |
| `<major>` | Version tags | `1` |

### Tag Examples

**Push to main branch**:
- `ghcr.io/yslim-030622/clearsplit/api:latest`
- `ghcr.io/yslim-030622/clearsplit/api:main-abc1234`

**Push tag `v1.2.3`**:
- `ghcr.io/yslim-030622/clearsplit/api:v1.2.3`
- `ghcr.io/yslim-030622/clearsplit/api:1.2`
- `ghcr.io/yslim-030622/clearsplit/api:1`
- `ghcr.io/yslim-030622/clearsplit/api:latest`

## Pulling the Image

### Public Access

Images are published as public packages. Pull without authentication:

```bash
docker pull ghcr.io/yslim-030622/clearsplit/api:latest
```

### With Authentication (if private)

```bash
# Login with GitHub token
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Pull image
docker pull ghcr.io/yslim-030622/clearsplit/api:latest
```

## Running Locally

### Quick Start

```bash
# Pull latest image
docker pull ghcr.io/yslim-030622/clearsplit/api:latest

# Run with environment variables
docker run -d \
  --name clearsplit-api \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql+asyncpg://user:pass@host:5432/dbname" \
  -e JWT_SECRET="your-secret-key" \
  -e JWT_ALGORITHM="HS256" \
  -e ACCESS_TOKEN_EXPIRE_MINUTES="15" \
  -e REFRESH_TOKEN_EXPIRE_DAYS="30" \
  ghcr.io/yslim-030622/clearsplit/api:latest
```

### With Docker Compose

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_USER: clearsplit
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: clearsplit
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U clearsplit"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    image: ghcr.io/yslim-030622/clearsplit/api:latest
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://clearsplit:${POSTGRES_PASSWORD}@postgres:5432/clearsplit
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGORITHM: HS256
      ACCESS_TOKEN_EXPIRE_MINUTES: 15
      REFRESH_TOKEN_EXPIRE_DAYS: 30
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  postgres_data:
```

Run with:
```bash
# Create .env file with secrets
cat > .env << EOF
POSTGRES_PASSWORD=your-db-password
JWT_SECRET=your-jwt-secret
EOF

# Start services
docker-compose -f docker-compose.prod.yml up -d
```

### Running Migrations

Before starting the API, run migrations:

```bash
# Using the image
docker run --rm \
  -e DATABASE_URL="postgresql+asyncpg://user:pass@host:5432/dbname" \
  ghcr.io/yslim-030622/clearsplit/api:latest \
  alembic upgrade head
```

Or exec into running container:

```bash
docker exec clearsplit-api alembic upgrade head
```

## Required Environment Variables

### Database
- `DATABASE_URL` - PostgreSQL connection string (asyncpg driver)
  - Format: `postgresql+asyncpg://user:password@host:port/database`
  - Example: `postgresql+asyncpg://clearsplit:pass@localhost:5432/clearsplit`

### JWT Authentication
- `JWT_SECRET` - Secret key for JWT tokens (**REQUIRED**)
  - Generate with: `openssl rand -hex 32`
  - Keep secure, never commit to git
- `JWT_ALGORITHM` - Algorithm (default: `HS256`)
- `ACCESS_TOKEN_EXPIRE_MINUTES` - Access token lifetime (default: `15`)
- `REFRESH_TOKEN_EXPIRE_DAYS` - Refresh token lifetime (default: `30`)

### Optional
- `ENV` - Environment name (`production`, `staging`, `local`)
- `UVICORN_WORKERS` - Number of worker processes (default: `1`)
- `UVICORN_HOST` - Bind host (default: `0.0.0.0`)
- `UVICORN_PORT` - Bind port (default: `8000`)

## Building Locally

### Build the Image

```bash
cd backend

# Build with tag
docker build -t clearsplit-api:local .

# Build with specific platform
docker build --platform linux/amd64 -t clearsplit-api:local .
```

### Test the Build

```bash
# Run locally built image
docker run -d \
  --name clearsplit-test \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql+asyncpg://clearsplit:clearsplit@host.docker.internal:5432/clearsplit" \
  -e JWT_SECRET="test-secret" \
  clearsplit-api:local

# Check health
curl http://localhost:8000/health

# View logs
docker logs clearsplit-test

# Stop and remove
docker stop clearsplit-test
docker rm clearsplit-test
```

## Production Deployment

### Multi-Worker Setup

For production, run with multiple workers:

```bash
docker run -d \
  --name clearsplit-api \
  -p 8000:8000 \
  -e DATABASE_URL="..." \
  -e JWT_SECRET="..." \
  -e UVICORN_WORKERS="4" \
  ghcr.io/yslim-030622/clearsplit/api:latest
```

### Resource Limits

```bash
docker run -d \
  --name clearsplit-api \
  --memory="512m" \
  --cpus="1.0" \
  -p 8000:8000 \
  -e DATABASE_URL="..." \
  -e JWT_SECRET="..." \
  ghcr.io/yslim-030622/clearsplit/api:latest
```

### Health Checks

The image includes built-in health checks:
- **Endpoint**: `http://localhost:8000/health`
- **Interval**: Every 30 seconds
- **Timeout**: 10 seconds
- **Retries**: 3 before marking unhealthy

## Verifying Published Images

### GitHub Packages UI

1. Go to: https://github.com/yslim-030622/ClearSplit/pkgs/container/clearsplit%2Fapi
2. Check published tags and their digests
3. View build provenance and SBOM

### Command Line

```bash
# List all tags
curl -s https://ghcr.io/v2/yslim-030622/clearsplit/api/tags/list | jq

# Inspect image metadata
docker pull ghcr.io/yslim-030622/clearsplit/api:latest
docker inspect ghcr.io/yslim-030622/clearsplit/api:latest
```

## Security

### Image Features

✅ **Non-root user**: Runs as `appuser` (not root)  
✅ **Minimal base**: Python 3.12-slim (reduces attack surface)  
✅ **Multi-stage build**: No build tools in final image  
✅ **Health checks**: Automatic container health monitoring  
✅ **Build provenance**: Signed attestations for supply chain security  

### Best Practices

1. **Secrets Management**:
   - Never put secrets in Dockerfile
   - Use environment variables
   - Consider secrets management (Vault, AWS Secrets Manager)

2. **Network Security**:
   - Run behind reverse proxy (nginx, Caddy)
   - Use HTTPS in production
   - Implement rate limiting

3. **Updates**:
   - Rebuild regularly for security patches
   - Subscribe to security advisories
   - Use dependabot for dependency updates

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs clearsplit-api

# Common issues:
# - DATABASE_URL incorrect format
# - Database not reachable
# - Missing required env vars
```

### Database Connection Issues

```bash
# Test database connectivity from container
docker exec clearsplit-api python -c "
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine
async def test():
    engine = create_async_engine('$DATABASE_URL')
    async with engine.connect() as conn:
        print('✅ Database connection successful')
asyncio.run(test())
"
```

### Health Check Failing

```bash
# Check health endpoint directly
docker exec clearsplit-api curl -f http://localhost:8000/health

# Check uvicorn is listening
docker exec clearsplit-api netstat -tulpn | grep 8000
```

## CI/CD Pipeline

The Docker build and publish workflow:

1. **Triggers**:
   - Push to `main` branch
   - Push of version tags (`v*`)
   - Manual dispatch

2. **Process**:
   - Run full test suite (reuses CI workflow)
   - Build multi-platform image (amd64 + arm64)
   - Tag appropriately
   - Push to GHCR
   - Generate build attestation

3. **Caching**:
   - GitHub Actions cache used
   - Significantly faster rebuilds

4. **Platforms**:
   - `linux/amd64` (Intel/AMD x86_64)
   - `linux/arm64` (Apple Silicon, ARM servers)

## Next Steps

After pulling and running the image:

1. **Set up reverse proxy** (nginx, Caddy, Traefik)
2. **Configure SSL/TLS** certificates
3. **Set up monitoring** (Prometheus, Grafana)
4. **Configure logging** (centralized logs)
5. **Implement backups** (database, volumes)
6. **Set up alerts** (PagerDuty, Slack)

---

**Last Updated**: December 2024  
**Registry**: GitHub Container Registry (GHCR)  
**Base Image**: python:3.12-slim  
**Architecture**: amd64, arm64

