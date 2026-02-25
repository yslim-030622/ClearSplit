# Repository Map

## Top Level

```
.
├── backend/              # FastAPI Python backend (API, domain logic, migrations, tests)
├── ios/                  # SwiftUI iOS client and build automation
├── docs/                 # Project documentation
├── scripts/              # Repo-level helper scripts (security, S3 testing)
├── .github/workflows/    # 8 files (7 YAML workflows + this README)
├── docker-compose.yml    # Local dev: PostgreSQL 16 + API with live reload
├── .pre-commit-config.yaml  # Pre-commit hooks (ruff, secrets, formatting)
├── .env.example          # Environment variable template
├── SECURITY.md           # Security model, controls, incident response
└── README.md             # Project overview, setup, and API reference
```

## Backend Structure

```
backend/
├── app/
│   ├── main.py                     # FastAPI app wiring, middleware, health endpoints
│   ├── api/                        # HTTP route handlers by feature domain
│   │   ├── auth.py                 #   Authentication (signup, login, refresh, me)
│   │   ├── groups.py               #   Groups and membership management
│   │   ├── expenses.py             #   Expense CRUD with equal splits
│   │   ├── settlements.py          #   Balances, settlement computation, payments
│   │   ├── shopping.py             #   Shopping sessions, items, receipts, OCR
│   │   └── friends.py              #   Friend requests and management
│   ├── services/                   # Business logic and authorization rules
│   │   ├── expense.py              #   Expense calculations and split distribution
│   │   ├── group.py                #   Group operations
│   │   ├── membership.py           #   Membership validation
│   │   ├── settlement.py           #   Settlement algorithms and payment logic
│   │   ├── shopping.py             #   Shopping session lifecycle (largest service, 34KB)
│   │   ├── friends.py              #   Friend management logic
│   │   └── ocr.py                  #   Tesseract OCR processing
│   ├── models/                     # 18 SQLAlchemy ORM models
│   │   ├── user.py                 #   User accounts
│   │   ├── group.py                #   Groups
│   │   ├── membership.py           #   Group memberships with roles
│   │   ├── expense.py              #   Expense records
│   │   ├── expense_split.py        #   Per-member expense shares
│   │   ├── settlement.py           #   Settlement batches and individual transfers
│   │   ├── shopping_session.py     #   Shopping trip records
│   │   ├── shopping_item.py        #   Line items
│   │   ├── shopping_item_split.py  #   Per-sharer item allocation
│   │   ├── shopping_session_participant.py  # Session participants
│   │   ├── receipt_upload.py       #   Receipt S3 metadata
│   │   ├── receipt_extracted_item.py  # OCR-extracted items
│   │   ├── friendship.py           #   Bidirectional friend edges
│   │   ├── refresh_token.py        #   Token rotation tracking
│   │   ├── idempotency_key.py      #   Request deduplication
│   │   └── activity_log.py         #   Audit trail
│   ├── schemas/                    # Pydantic request/response schemas
│   │   ├── auth.py                 #   Auth DTOs
│   │   ├── user.py                 #   User DTOs
│   │   ├── group.py                #   Group DTOs
│   │   ├── membership.py           #   Membership DTOs
│   │   ├── expense.py              #   Expense DTOs
│   │   ├── settlement.py           #   Settlement DTOs
│   │   ├── shopping.py             #   Shopping DTOs
│   │   ├── friends.py              #   Friend DTOs
│   │   └── base.py                 #   Shared base schemas
│   ├── auth/                       # Authentication subsystem
│   │   ├── jwt.py                  #   JWT creation and validation (HS256)
│   │   ├── password.py             #   Bcrypt hashing and verification
│   │   ├── dependencies.py         #   FastAPI auth dependency (get_current_user)
│   │   └── refresh_tokens.py       #   Refresh token rotation with JTI
│   ├── core/                       # Core utilities
│   │   ├── config.py               #   Settings via Pydantic BaseSettings + SecretStr
│   │   ├── rate_limit.py           #   In-memory sliding window rate limiter
│   │   ├── idempotency.py          #   Idempotency key handling
│   │   └── identity.py             #   Case-insensitive identity normalization
│   ├── db/                         # Database configuration
│   │   ├── session.py              #   SQLAlchemy async session factory
│   │   └── connect_args.py         #   TLS connection parameters
│   ├── settlement/                 # Settlement algorithm submodule
│   ├── scripts/
│   │   └── migration_precheck.py   #   Pre-migration identity validation
│   └── tests/                      # 143+ tests across 13 files
│       ├── conftest.py             #   Fixtures (transactional isolation, test client, S3 stub)
│       ├── test_auth.py            #   24 auth tests
│       ├── test_security.py        #   19 security tests
│       ├── test_groups.py          #   31 group tests
│       ├── test_expenses.py        #   26 expense tests
│       ├── test_settlements.py     #   19 settlement tests
│       ├── test_shopping.py        #   51 shopping tests (largest test file)
│       ├── test_friends.py         #   21 friend tests
│       ├── test_refresh_tokens.py  #   4 token rotation tests
│       ├── test_rate_limit.py      #   6 rate limit tests
│       ├── test_ocr.py             #   1 OCR test
│       ├── test_connect_args.py    #   4 connection tests
│       └── test_backend_e2e.py     #   1 end-to-end smoke test
├── alembic/                        # Database migrations
│   ├── env.py                      #   Migration environment setup
│   └── versions/                   #   14 migration files (0001–0014)
├── Dockerfile                      # Python 3.11-slim + Tesseract OCR
├── Makefile                        # Dev commands (run, test, lint, migrate)
├── requirements.txt                # 23 production dependencies
├── requirements-dev.txt            # Test, lint, and security tool dependencies
├── pytest.ini                      # Test runner configuration
├── alembic.ini                     # Migration framework configuration
├── setup_db.sh                     # Database initialization script
├── run_migration.sh                # Migration runner script
└── .python-version                 # Python 3.11 specification
```

## iOS Structure

```
ios/ClearSplit/
├── Sources/ClearSplit/             # Main source code (87 Swift files)
│   ├── ClearSplitApp.swift         #   App entry point
│   ├── RootView.swift              #   Auth gating view
│   ├── Config/APIConfig.swift      #   Base URL resolution
│   ├── State/AppState.swift        #   Central state coordinator (438 lines)
│   ├── Models/                     #   7 Codable model files
│   ├── Networking/                 #   APIClient + 5 domain services + HealthClient
│   ├── ViewModels/                 #   7 screen-level view models
│   ├── Views/                      #   44 view files
│   │   ├── (18 screen views)       #   Login, groups, shopping, receipts, friends, profile
│   │   └── Components/             #   26 reusable UI components
│   ├── DesignSystem/               #   Colors, spacing/radius/elevation tokens, button styles
│   ├── Storage/KeychainService.swift  # Secure token persistence
│   ├── Extensions/                 #   Hex color support
│   ├── Utilities/                  #   Currency/date formatting
│   └── ViewModifiers/              #   Elevation modifiers
├── Tests/ClearSplitTests/          # Unit tests (XCTest)
├── ClearSplit/                     # Xcode project
│   ├── ClearSplit.xcodeproj        #   Project file
│   └── ClearSplitUITests/          #   UI smoke tests
├── scripts/                        # Build automation
│   ├── ios_ci_common.sh            #   Shared CI utilities
│   ├── ios_build.sh                #   Simulator build
│   ├── ios_test.sh                 #   Test execution (unit/ui/all)
│   ├── ios_lint.sh                 #   SwiftLint validation
│   └── ios_archive.sh              #   Unsigned archive for validation
├── fastlane/                       # Deployment automation
│   ├── Fastfile                    #   Lane definitions
│   └── Appfile                     #   App configuration
├── Package.swift                   # SPM manifest (iOS 16+, macOS 12+)
├── .swiftlint.yml                  # SwiftLint rules
├── Gemfile                         # Ruby gems (Fastlane)
└── RECEIPT_REVIEW_README.md        # Receipt feature documentation
```

## Documentation

```
docs/
├── INDEX.md                        # Documentation entry point
├── project-overview.md             # Product scope, features, tech stack
├── architecture.md                 # System design, data flows, patterns
├── backend-reference.md            # API endpoints, models, auth, config
├── ios-reference.md                # App architecture, networking, navigation
├── repository-map.md               # This file — directory layout reference
├── workflows-and-operations.md     # Local dev, testing, CI/CD, deployment
├── dependencies.md                 # Runtime and dev dependency versions
├── features/                       # Feature specifications
│   ├── SHOPPING_MODEL.md           #   Shopping session model and workflow
│   └── RECEIPT_OCR_DECISIONS.md    #   OCR implementation decisions
├── backend-docs/                   # Backend implementation details
│   ├── AUTH_IMPLEMENTATION.md
│   ├── EXPENSES_IMPLEMENTATION.md
│   ├── GROUPS_IMPLEMENTATION.md
│   ├── MODELS_IMPLEMENTATION.md
│   └── SCHEMAS_IMPLEMENTATION.md
└── adr/                            # Architecture Decision Records
    └── 0001-non-negotiables.md     #   Core constraints (cents, immutability, UTC)
```

## Operational Scripts

```
scripts/
├── secret-scan.sh          # Tracked-file secret scanning (JWT, passwords, API keys, AWS keys)
├── verify-security.sh      # Repo security baseline (gitignore, env files, SecretStr usage)
└── s3_smoke_test.py        # S3 upload/download URL validation
```

## CI/CD Workflows

```
.github/workflows/
├── ci.yml                  # Backend CI: main-branch release gate (PR/main)
├── deploy-aca-reusable.yml # Reusable ACA deploy workflow (build/promote modes)
├── ios-pr-checks.yml       # iOS PR: SwiftLint + build + unit tests
├── ios-main-checks.yml     # iOS main: full validation + optional TestFlight
├── security-scan.yml       # Security: TruffleHog + pip-audit + Bandit
├── deploy-staging.yml      # Staging wrapper (build + deploy via reusable)
├── deploy-production.yml   # Production wrapper (gated promote via reusable)
└── README.md               # Workflow documentation
```
