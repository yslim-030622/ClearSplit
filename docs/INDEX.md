# Documentation Index

Entry point for all ClearSplit documentation. Every file listed here is kept in sync with the codebase.

## Start Here

| Document | Description |
|----------|-------------|
| [Project Overview](project-overview.md) | Product scope, features, tech stack, and database schema |
| [Repository Map](repository-map.md) | Directory layout with file-level annotations |
| [Architecture](architecture.md) | System topology, request lifecycle, domain flows, iOS architecture |

## Engineering References

| Document | Description |
|----------|-------------|
| [Backend Reference](backend-reference.md) | API endpoints, environment config, auth rules, data model, migrations |
| [iOS Reference](ios-reference.md) | App structure, state management, networking, navigation, design system |
| [Dependencies](dependencies.md) | Runtime and development dependencies with versions and purpose |

## Operations

| Document | Description |
|----------|-------------|
| [Workflows & Operations](workflows-and-operations.md) | Local dev, testing, CI/CD pipelines, staging deployment, troubleshooting |
| [Security](../SECURITY.md) | Security model, controls, scanning, and incident response |

## Feature Documentation

| Document | Description |
|----------|-------------|
| [Shopping Model](features/SHOPPING_MODEL.md) | Shopping session workflow, data model, split logic, authorization |
| [Receipt OCR Decisions](features/RECEIPT_OCR_DECISIONS.md) | OCR implementation decisions and product scope |

## Backend Implementation Details

| Document | Description |
|----------|-------------|
| [Auth Implementation](backend-docs/AUTH_IMPLEMENTATION.md) | Authentication and token system details |
| [Groups Implementation](backend-docs/GROUPS_IMPLEMENTATION.md) | Group and membership logic |
| [Expenses Implementation](backend-docs/EXPENSES_IMPLEMENTATION.md) | Expense and split calculation details |
| [Models Implementation](backend-docs/MODELS_IMPLEMENTATION.md) | SQLAlchemy model patterns |
| [Schemas Implementation](backend-docs/SCHEMAS_IMPLEMENTATION.md) | Pydantic schema patterns |

## Architecture Decisions

| Document | Description |
|----------|-------------|
| [Non-Negotiables](adr/0001-non-negotiables.md) | Core constraints: integer cents, atomic transactions, immutable settlements, UTC timestamps |
