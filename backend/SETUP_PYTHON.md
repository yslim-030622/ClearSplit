# Python Setup Guide

## Issue: Python 3.13 Compatibility

The project uses `asyncpg==0.29.0` which doesn't support Python 3.13 yet.

## Solution: Use Python 3.11

### Option 1: Use pyenv (Recommended)

```bash
# Install pyenv if you don't have it
brew install pyenv

# Install Python 3.11
pyenv install 3.11.9

# Set local Python version
cd backend
pyenv local 3.11.9

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### Option 2: Use Homebrew Python 3.11

```bash
# Install Python 3.11
brew install python@3.11

# Create virtual environment with Python 3.11
/opt/homebrew/opt/python@3.11/bin/python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### Option 3: Update asyncpg (Alternative)

If you must use Python 3.13, update asyncpg to latest:

```bash
# Update requirements.txt
# Change: asyncpg==0.29.0
# To: asyncpg>=0.29.0

pip install asyncpg --upgrade
```

**Note:** Latest asyncpg may have breaking changes. Test thoroughly.

---

## Verify Python Version

```bash
python3 --version  # Should show 3.11.x
which python3      # Should point to your venv
```

---

## Quick Start After Setup

```bash
cd backend
source venv/bin/activate  # Activate venv
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Run tools
ruff check app/
mypy app/ --ignore-missing-imports
pytest --cov=app
```
