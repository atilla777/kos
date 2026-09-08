---
title: Central REST API and Multi-Repository State
status: accepted
date: 2026-09-08
---

# ADR-0001: Central REST API and Multi-Repository State

## Context

KOS needs one stable process boundary for concurrent agents and a CLI that can be used without loading the Rails application. The original draft assigned one SQLite state directory to one Git repository and excluded an HTTP API from the first version. That model would require a separate persistence process per repository and would couple the CLI to Rails persistence.

## Decision

A central Rails API owns one SQLite database and may manage multiple Git repositories. Repository-owned entities and operations are scoped by an immutable `repository_id`; database uniqueness constraints include that scope where the invariant is repository-local.

The Ruby CLI remains the only agent-facing programmatic interface. It communicates with Rails through a versioned JSON REST API under `/api/v1` and never accesses SQLite or loads Active Record. Agents and skills do not call the API directly.

The first deployment is local. Rails binds to loopback by default and requires a bearer token for API endpoints other than health checks. Secrets are supplied outside the repository and are not logged.

## Consequences

- Rails persistence code is the only code allowed to access SQLite.
- API requests must resolve and authorize repository scope before invoking application operations.
- Idempotency, public numbers, leases, reservations, and other repository-local invariants must include `repository_id` in their database constraints.
- CLI and API schemas become durable external contracts and require versioned contract tests.
- One service lifecycle and migration process replaces per-repository database lifecycle management.
- SQLite remains a single-writer bottleneck, so write transactions must stay short and contention handling must remain bounded.

## Rejected Alternatives

### One Rails and SQLite instance per repository

This preserves stronger physical isolation but complicates process discovery, upgrades, and coordination across repositories.

### CLI loading Rails and accessing SQLite directly

This avoids HTTP transport but couples every CLI invocation to application persistence and prevents a stable process boundary for concurrent clients.

### One SQLite database per repository behind a central API

This retains physical isolation but introduces dynamic connection management and multi-database migration complexity without a demonstrated requirement.
