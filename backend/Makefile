PYTHON ?= python3
PIP ?= pip3
PYTEST ?= pytest

install:
	$(PIP) install -r requirements.txt

install-dev:
	$(PIP) install -r requirements-dev.txt

run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

test:
	$(PYTEST)

lint-ci:
	ruff check app app/tests --select=E9,F63,F7,F82

migrate:
	alembic upgrade head

test-pr:
	$(PYTEST) -m "not e2e" -v --durations=20

test-all:
	$(PYTEST) -v --durations=30

ci-pr: lint-ci test-pr

ci-main: lint-ci test-all

.PHONY: install install-dev run test lint-ci migrate test-pr test-all ci-pr ci-main
