# CI/CD Workflows

Place GitHub Actions here:
- Backend: lint (ruff/black), type-check (mypy), tests (pytest) against Postgres.
- Docker: build/publish API image on main.
- iOS: build and unit/snapshot tests, upload artifacts.
- Staging deploy on PR merge; optional preview for PRs.
