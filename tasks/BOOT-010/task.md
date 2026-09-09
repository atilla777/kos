---
title: Base SQLite Persistence
task: BOOT-010
created: 2026-09-09
---

# BOOT-010: Base SQLite Persistence

## Goal

Create the first working KOS persistence layer by configuring SQLite and implementing the relational schema for repositories, the central workflow catalog, and tasks.

## User Outcome

KOS can reliably persist registered repository records, mutable workflow drafts, immutable published workflow versions, and tasks pinned to one workflow version. API, CLI, and creation operations remain later tasks.

## Context

The central persistence, workflow catalog, and task contracts are defined, but the Rails application currently has no domain tables or models. SQLite pragmas are present in configuration but are not verified by tests. Production state-root lifecycle work has been separated into BOOT-020 so this task remains a cohesive persistence-schema change.

## Requirements

- BOOT-010-REQ-001: Configure and verify SQLite foreign keys, WAL journal mode, `FULL` synchronous policy, and a 5000 ms busy timeout.
- BOOT-010-REQ-002: Persist repositories with a UUID, immutable registration and trust fields, globally unique canonical Git common directory and task prefix, and a repository-local next task sequence.
- BOOT-010-REQ-003: Enforce the task-prefix syntax and task-sequence range through database constraints as well as model validation.
- BOOT-010-REQ-004: Persist task types, mutable workflow drafts with optimistic locking, and normalized immutable published workflow versions and graph members.
- BOOT-010-REQ-005: Protect published workflow versions and their child records from update and deletion with database triggers.
- BOOT-010-REQ-006: Permit a task type to have no current workflow version before the first publication, while requiring any selected version to belong to that task type.
- BOOT-010-REQ-007: Seed the shared `quick-fix` task type idempotently without activating an unpublished workflow.
- BOOT-010-REQ-008: Persist tasks with a repository-local sequence, title, task type, immutable workflow version, current state belonging to that version, and optimistic lock version.
- BOOT-010-REQ-009: Derive public task numbers from repository prefix and sequence rather than storing a duplicated formatted value.
- BOOT-010-REQ-010: Enforce foreign keys, required fields, local uniqueness, enum and range checks, cross-table version membership, and immutable repository and task identity fields in SQLite.
- BOOT-010-REQ-011: Keep persistence models limited to associations, local validation, UUID assignment, and query behavior; do not introduce workflow policy, API, or CLI behavior.

## Scope

- Rails migrations, schema, Active Record models, associations, validations, and UUID assignment.
- SQLite connection configuration and pragma verification.
- An idempotent seed for the `quick-fix` task type.
- Persistence and database-constraint tests.
- External plan updates, including the separate BOOT-020 production-state task.

## Non-Goals

- Production state-root resolution, permissions, service locking, backup and restore, `kos:state:prepare`, or migration startup guards.
- REST API, CLI, authentication, repository registration orchestration, or Git verification.
- Workflow import, whole-graph validation, publication, activation, or export operations.
- Task creation, public-number allocation behavior, or idempotency handling.
- Attempts, leases, artifacts, repository effects, publications, worktree reservations, task relations, or dependencies.
- Publishing or activating `quick-fix@1.0.0`.

## Related Specifications And ADRs

- [Central Persistence](../../docs/specs/central-persistence.md)
- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [Task Model](../../docs/specs/task-model.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [ADR-0005: Central Persistence And Repository Registration](../../docs/decisions/0005-central-persistence-and-registration.md)
- [ADR-0006: Repository-Specific Task Prefixes](../../docs/decisions/0006-repository-task-prefixes.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-010-DEC-001: Store mutable draft definitions as complete JSON documents because draft import replaces the whole document; normalize published graph members so relational constraints and immutability apply to executable content.
- BOOT-010-DEC-002: Allow `TaskType.current_workflow_version_id` to be null only before activation. BOOT-019 will own publication and activation policy.
- BOOT-010-DEC-003: Store repository-local numeric task sequence separately and derive the public number at application and transport boundaries.
- BOOT-010-DEC-004: Defer the complete production state lifecycle to BOOT-020 instead of combining operational filesystem and deployment behavior with the base schema.

## Acceptance Criteria

- BOOT-010-AC-001: Migrations apply successfully to an empty test database and define all approved tables, indexes, checks, foreign keys, and triggers.
- BOOT-010-AC-002: The base entities persist and load through Active Record with their specified associations.
- BOOT-010-AC-003: SQLite rejects invalid prefixes, duplicate repository identities, duplicate workflow versions, invalid task sequences, and a task state from another workflow version even when model validation is bypassed.
- BOOT-010-AC-004: SQLite rejects updates and deletes of a published workflow version and each normalized child type.
- BOOT-010-AC-005: SQLite rejects changes to immutable repository and task identity fields while permitting their explicitly mutable fields.
- BOOT-010-AC-006: Workflow drafts support optimistic locking, and repeated seeding produces exactly one `quick-fix` task type.
- BOOT-010-AC-007: Required focused and full project checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-010 active externally.
2. Add migrations for the base entities, indexes, checks, foreign keys, and immutability triggers.
3. Add minimal Active Record models, validations, associations, and UUID assignment.
4. Add the idempotent `quick-fix` seed.
5. Add persistence tests, including direct database-constraint and trigger coverage.
6. Run focused specs, migration checks, the full project check, and diff validation.
7. Complete the external plan, independently review the change, commit it, and push normally to the default branch.

## Verification

- Run focused model and persistence specs while iterating.
- Recreate and migrate the test database.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-09:

- `bundle exec rspec spec/models`: 50 examples, 0 failures, including a clean test-database recreation from `db/structure.sql`.
- `mise run check`: passed with 135 examples, 0 failures, 38 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining high- or medium-severity findings after UUID, primary-key immutability, and transition-membership corrections.

## Implementation Result

- Added the base repository, task type, workflow draft, normalized published workflow graph, and task schema with UUID identities, optimistic locks, scoped uniqueness, composite foreign keys, and check constraints.
- Added database triggers that preserve immutable primary keys and repository registration, freeze published workflow versions and all normalized children, require published version activation and task pinning, and protect workflow-state membership.
- Added minimal Active Record models, associations, validations, UUID assignment, draft JSON round-tripping, public-number formatting, and an idempotent `quick-fix` seed.
- Configured SQL structure dumps so SQLite triggers remain reproducible and verified WAL, foreign keys, `FULL` synchronous mode, and a 5000 ms busy timeout.
- Added focused model and database-level tests that bypass model validation where required to prove SQLite enforcement.

## Risks

- BOOT-010-RISK-001: SQLite triggers and composite workflow-state membership can differ from Active Record assumptions; direct SQL-level tests must cover them.
- BOOT-010-RISK-002: Whole-graph validity is intentionally not enforced in this task and remains the responsibility of BOOT-019 publication validation.
- BOOT-010-RISK-003: Production state paths and migration lifecycle remain incomplete until BOOT-020; the current production database path is not the final operational contract.
- BOOT-010-RISK-004: The initial migration contains trigger DDL and is intentionally forward-only in normal operation; destructive rollback is not part of the supported production recovery contract.
