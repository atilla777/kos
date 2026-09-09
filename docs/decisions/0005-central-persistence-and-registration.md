---
title: Central Persistence And Repository Registration
status: accepted
date: 2026-09-09
amended_by: 0007-central-workflow-catalog
---

# ADR-0005: Central Persistence And Repository Registration

The workflow snapshot-store portion of this decision is superseded by [ADR-0007](0007-central-workflow-catalog.md). The state-root, migration, backup, and repository-registration decisions remain accepted.

## Context

The central Rails service needs durable state independent of its source checkout. SQLite rows and immutable workflow bundle bytes have different storage and atomicity needs, and applying schema changes during ordinary startup would make service availability perform an uncontrolled DDL side effect. A repository also needs a stable identity and trusted publication settings before any repository-scoped command can run.

## Decision

Production state uses an XDG state root with explicit environment overrides. Rails owns one SQLite database and a narrow content-addressed filesystem store for immutable workflow snapshots. Snapshot candidates are fully written and verified through same-filesystem staging and atomic rename before a database transaction may reference them. This filesystem boundary is not a general replaceable storage abstraction.

Production migrations run only through an explicit, service-exclusive Rails operation that creates a SQLite-consistent backup before changing an existing database. The API never migrates on normal startup and refuses a pending or newer schema.

Repository registration is an authenticated, unscoped, idempotent CLI/API operation. The server independently verifies the canonical Git common directory and trust settings through the repository adapter. Canonical common directory and the human-selected task prefix are each globally unique; remote URL is not. A matching repeated registration returns the existing immutable repository ID, while differing trust settings or prefix require an explicit future update operation.

The observable contract is defined by [Central Persistence](../specs/central-persistence.md).

## Consequences

- Installed production state survives source checkout replacement and does not place mutable data in a target repository.
- Database references cannot expose partially materialized snapshots, although interrupted staging and unreferenced complete bundles require later reconciliation.
- Deployments must stop the API, prepare state, and then start the API; schema changes cannot be hidden in ordinary startup.
- Registration needs a global idempotency scope because repository scope does not exist before the operation succeeds.
- A repository-specific public task number is globally unambiguous because its immutable prefix is globally unique, as refined by [ADR-0006](0006-repository-task-prefixes.md).
- Separate clones of one remote remain separate repository registrations, and moving a checkout requires an explicit future rebind.
- Backup retention, snapshot garbage collection, rebind, registration update, and alternate backends remain separate work.

## Rejected Alternatives

### Store production state in the KOS checkout

This couples durable data to source deployment paths and makes checkout replacement or cleanup unsafe.

### Store workflow bundles as database blobs

This would simplify one transaction boundary but would enlarge SQLite write transactions and the single-writer bottleneck with immutable project files.

### Run migrations during API startup

This makes every service start a potential schema mutation and complicates backup, failure diagnosis, and rollback to a compatible release.

### Identify repositories by normalized remote URL

Multiple local clones can intentionally track the same remote and need separate worktrees and filesystem validation.

### Let repeated registration update trust settings

Implicitly changing publication authority during an ensure-like operation is unsafe and makes retries behaviorally significant.
