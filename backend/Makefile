VENV_PYTHON := $(wildcard venv/bin/python)

PYTHON ?= $(if $(VENV_PYTHON),$(VENV_PYTHON),python3)
PIP ?= $(PYTHON) -m pip
PYTEST ?= $(PYTHON) -m pytest
RUFF ?= $(PYTHON) -m ruff

install:
	$(PIP) install -r requirements.txt

install-dev:
	$(PIP) install -r requirements-dev.txt

run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

test:
	$(PYTEST)

lint-ci:
	$(RUFF) check app app/tests

migrate:
	alembic upgrade head

test-pr:
	$(PYTEST) -m "not e2e" -v --durations=20 --cov=app --cov-report=term-missing --cov-fail-under=78

test-all:
	$(PYTEST) -v --durations=30 --cov=app --cov-report=term-missing --cov-fail-under=80

ci-pr: lint-ci test-pr

ci-main: lint-ci test-all

.PHONY: install install-dev run test lint-ci migrate test-pr test-all ci-pr ci-main
