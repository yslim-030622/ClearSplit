# Workflows and Operations

## Local Development

### Backend setup

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
make run
```

### Backend with Docker Compose

From repo root:

```bash
docker compose up --build
```

This starts PostgreSQL and API using `.env` values.

### iOS setup

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```

Use `API_BASE_URL` override for physical devices.

## Daily Engineering Loops

### Add a backend endpoint

1. add/update schema in `backend/app/schemas/`
2. add route in `backend/app/api/`
3. implement business rule in `backend/app/services/`
4. add/adjust tests in `backend/app/tests/`

### Change persistence model

1. update model in `backend/app/models/`
2. generate migration in `backend/alembic/versions/`
3. run `alembic upgrade head`
4. run tests

### iOS feature addition

1. add/update model in `Models/`
2. add networking call in `Networking/`
3. wire orchestration in `State/AppState.swift` and/or `ViewModels/`
4. build UI in `Views/`
5. validate with `ios_test.sh`

## Testing and Quality

### Backend

```bash
cd backend
make lint-ci
make test
make test-pr
make test-all
```

### iOS

```bash
cd ios/ClearSplit
./scripts/ios_build.sh
./scripts/ios_test.sh all
./scripts/ios_lint.sh
```

## Migrations

Apply latest migrations:

```bash
cd backend
alembic upgrade head
```

In migration environments, duplicate identity precheck script is available at:

- `backend/app/scripts/migration_precheck.py`

It checks for case-insensitive duplicate emails/usernames before related constraints are enforced.

## Operational Scripts

### Security scans

```bash
./scripts/secret-scan.sh
./scripts/verify-security.sh
```

### S3 integration smoke test

```bash
python scripts/s3_smoke_test.py
```

Requires S3-related environment variables.

## Troubleshooting

### API is up but app cannot connect

- confirm backend is listening on `0.0.0.0` when testing from device
- set `API_BASE_URL` to host LAN IP for physical devices
- verify that `/health/live` responds from the same network path

### Receipt upload failures

- verify `S3_BUCKET_NAME` and AWS credentials/permissions
- verify file format is one of JPEG/PNG/WEBP/GIF
- verify image is below configured byte and pixel limits

### OCR timeout or no extracted items

- use a clearer receipt image with higher text contrast
- check backend logs for OCR timeout or image validation errors
- verify Tesseract is installed in runtime environment
