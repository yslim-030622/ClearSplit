PYTHON ?= python3
PIP ?= pip3

install:
	$(PIP) install -r requirements.txt

run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

test:
	pytest

.PHONY: install run test
