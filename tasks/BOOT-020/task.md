---
title: Production State Lifecycle
task: BOOT-020
created: 2026-09-10
---

# BOOT-020: Production State Lifecycle

## Goal

Make central SQLite state safe to operate in production through checkout-independent paths, private filesystem objects, service exclusion, explicit migration preparation, consistent backups, and startup schema guards.

## User Outcome

An operator can run `RAILS_ENV=production bin/rails kos:state:prepare` to create or safely migrate KOS state, while the API refuses unsafe paths, concurrent preparation, and incompatible schemas.

## Context

BOOT-010 implemented the base SQLite schema and models, but production still points at `storage/production.sqlite3`. State-root resolution, filesystem safety, service locking, backup, explicit preparation, and production startup guards are specified but not implemented.

## Requirements

- BOOT-020-REQ-001: Resolve the production state root from absolute `KOS_STATE_ROOT`, then absolute `$XDG_STATE_HOME/kos`, then absolute `$HOME/.local/state/kos`; fail when no absolute root can be resolved.
- BOOT-020-REQ-002: Let absolute `KOS_DATABASE_PATH` override the default `<state-root>/kos.sqlite3` path and reject relative overrides.
- BOOT-020-REQ-003: Create the state root, `backups`, and `locks` directories with mode `0700` and state files with mode `0600`, subject to a stricter umask.
- BOOT-020-REQ-004: Reject symlink path components, unexpected object types, objects not owned by the effective user, and existing state objects with group or other permissions.
- BOOT-020-REQ-005: Let API processes hold a shared non-blocking lock on `locks/service.lock` for their lifetime and let preparation hold the exclusive non-blocking lock, so multiple Puma workers may run while migration remains service-exclusive.
- BOOT-020-REQ-006: Add idempotent `RAILS_ENV=production bin/rails kos:state:prepare` behavior that creates an absent database and applies all pending migrations without letting ordinary API startup apply DDL.
- BOOT-020-REQ-007: Before migrating an existing database, create a SQLite-consistent backup rather than copying database and WAL files directly.
- BOOT-020-REQ-008: Atomically and durably write the backup and a JSON manifest containing source schema version, UTC creation time, byte size, and SHA-256 digest; verify the digest and SQLite integrity before migration.
- BOOT-020-REQ-009: Preserve a completed pre-migration backup if migration fails and report the last applied migration version.
- BOOT-020-REQ-010: Refuse production API startup when the database is absent, migrations are pending, or the database contains migration versions unknown to the running release.
- BOOT-020-REQ-011: Return explicit operational failures without exposing secrets or silently changing state.

## Scope

- Production state path resolution, safe filesystem creation, ownership and permission validation.
- Shared API and exclusive prepare service locking.
- SQLite-consistent backup and manifest generation and verification.
- The `kos:state:prepare` Rake task and production startup schema guards.
- Production database configuration and focused automated tests.
- External development-plan updates.

## Non-Goals

- Automated restore, backup retention, or backup deletion.
- systemd or deployment packaging.
- API and CLI task operations, repository registration, or alternate database backends.
- Changes to the existing domain schema.

## Related Specifications And ADRs

- [Central Persistence](../../docs/specs/central-persistence.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0005: Central Persistence And Repository Registration](../../docs/decisions/0005-central-persistence-and-registration.md)

## Task-Local Decisions

- BOOT-020-DEC-001: API processes use a shared `flock` and preparation uses an exclusive `flock`; this permits multiple serving processes while preserving migration exclusion.
- BOOT-020-DEC-002: An existing database means a regular database file present before preparation. Initial database creation does not require a pre-migration backup.
- BOOT-020-DEC-003: Backup filenames include a UTC timestamp and source schema version; temporary files remain in `backups` so atomic rename does not cross filesystems.
- BOOT-020-DEC-004: Restore remains an explicit operator procedure and is not automated in this task.

## Acceptance Criteria

- BOOT-020-AC-001: Production path fallback and overrides resolve deterministically, while relative, symlinked, incorrectly typed, foreign-owned, or non-private state objects are rejected before use.
- BOOT-020-AC-002: Newly created state directories and files have the required private permissions.
- BOOT-020-AC-003: Preparation cannot run while an API lock or another prepare lock is held, and API locks can coexist.
- BOOT-020-AC-004: Preparing an absent database creates and migrates it without a backup; preparing an up-to-date database is a no-op and creates no backup.
- BOOT-020-AC-005: Preparing an existing database with pending migrations creates and verifies a durable consistent backup before the first schema change.
- BOOT-020-AC-006: Migration failure preserves the backup and reports the last applied version.
- BOOT-020-AC-007: Production API startup rejects absent, pending, and newer schemas and accepts exactly compatible schema state without applying migrations.
- BOOT-020-AC-008: Focused and full required checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this baseline and mark BOOT-020 active externally.
2. Implement production state path resolution, private object creation, and filesystem validation.
3. Implement shared API and exclusive preparation service locking.
4. Implement consistent SQLite backup, manifest writing, durability, digest verification, and integrity checking.
5. Add the idempotent `kos:state:prepare` task and production migration startup guards.
6. Add isolated tests for successful paths and failures that protect state, migration, and locking invariants.
7. Run focused specs, the full project check, and diff validation; independently review the change.
8. Complete the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run focused state lifecycle and task specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-10:

- `bundle exec rspec spec/lib/kos/state spec/integration/kos/state/prepare_spec.rb`: 33 examples, 0 failures.
- `mise run check`: passed with 168 examples, 0 failures, 53 RuboCop-inspected files with no offenses, successful Zeitwerk eager loading, no Brakeman warnings, and no vulnerable dependencies.
- The production CI boot command with an absolute database path passed.
- `git diff --check`: passed.
- Independent review found no remaining high- or medium-severity findings after migration-error, path-ancestor, CI-path, and process-lock corrections.

## Implementation Result

- Production now resolves central state through the specified environment and XDG fallbacks instead of the source checkout.
- State directories, the database, service lock, backups, and manifests are created privately and unsafe ownership, permissions, object types, symlinks, sidecars, and path ancestors are rejected.
- Rails server processes retain a shared lifetime lock while `kos:state:prepare` requires an exclusive lock.
- Explicit preparation creates a missing database, rejects unknown schema versions, backs up an existing database before pending migrations, and verifies backup integrity, size, digest, and durable publication.
- Production server startup rejects absent, pending, and unknown schemas without applying DDL.
- Focused unit and subprocess integration coverage exercises path safety, WAL-aware backup, migration failures, idempotent preparation, schema guards, and cross-process exclusion.

## Risks

- BOOT-020-RISK-001: File locking, ownership, permission, and durability behavior is platform-specific; the implementation and tests target the supported Linux environment.
- BOOT-020-RISK-002: A process loss during migration relies on SQLite transaction behavior and the completed backup; automatic restore is intentionally excluded.
- BOOT-020-RISK-003: The operator restore procedure is specified but not exercised end to end in this task.
- BOOT-020-RISK-004: Tests verify the server hook across processes but do not launch a multi-worker Puma cluster; shared `flock` inheritance follows the supported Linux process semantics.
