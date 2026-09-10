---
title: Workflow Execution Persistence
task: BOOT-011
created: 2026-09-10
---

# BOOT-011: Workflow Execution Persistence

## Goal

Add reliable SQLite persistence for workflow attempts and leases, idempotency records, task artifacts, and worktree reservations.

## User Outcome

KOS can durably represent workflow-step ownership, fencing, mutation replay, immutable evidence, and recoverable worktree allocation. API, CLI, and workflow operations remain later tasks.

## Context

BOOT-010 established repositories, the central workflow catalog, and tasks. The execution entities already have normative workflow and CLI contracts but no persistence schema or models.

## Requirements

- BOOT-011-REQ-001: Persist workflow attempts with repository and task scope, workflow state, owner, lifecycle state, monotonically increasing fencing token, lease timestamps, frozen executable context and digest, and result manifest.
- BOOT-011-REQ-002: Store lease state on its owning attempt rather than as an independent resource, and prevent more than one unreconciled started attempt per task.
- BOOT-011-REQ-003: Persist global and repository-scoped idempotency records without a fabricated global repository, including command, key, canonical request fingerprint, in-progress intent locator, and completed semantic response.
- BOOT-011-REQ-004: Retain idempotency records for their scope lifetime and protect their scope, request identity, completed response, and deletion at the database boundary.
- BOOT-011-REQ-005: Persist immutable task artifacts with repository, task, and attempt ownership, closed type/state pairings, producer, and typed JSON metadata.
- BOOT-011-REQ-006: Persist worktree reservations with task, repository, current owning attempt and fencing token, immutable branch and canonical path, lifecycle state, and confirmation or reconciliation evidence.
- BOOT-011-REQ-007: Enforce one active reservation per task and branch within a repository and one active reservation per canonical path installation-wide; released reservations no longer occupy those keys.
- BOOT-011-REQ-008: Permit explicit reservation ownership transfer to a later attempt while preserving repository, task, branch, and path.
- BOOT-011-REQ-009: Add task pointers to its active attempt and current worktree reservation, with database-enforced task and repository consistency.
- BOOT-011-REQ-010: Enforce UUID, identifier, digest, JSON, enum, lifecycle, ownership, uniqueness, immutability, and fencing invariants in SQLite as well as local model validation.
- BOOT-011-REQ-011: Keep models limited to associations, local validation, UUID assignment, and JSON serialization; do not implement workflow operations or Git effects.

## Scope

- Rails migration, SQL structure, Active Record models, associations, validations, and JSON serialization.
- Database checks, indexes, composite foreign keys, and SQLite triggers.
- Focused persistence and direct database-constraint tests.

## Non-Goals

- REST API, CLI, serializers, authentication, and command handlers.
- Attempt claim, renewal, failure, reconciliation, step completion, or context construction operations.
- Canonical JSON digest calculation or complete JSON Schema validation.
- Git commands, worktree materialization or removal, repository-effect intents, and publication intents.
- Task creation, task relations, dependencies, or background cleanup jobs.

## Related Specifications And ADRs

- [Central Persistence](../../docs/specs/central-persistence.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-011-DEC-001: A lease is attempt-owned state because it has no independent protocol identity.
- BOOT-011-DEC-002: Store polymorphic artifact metadata and frozen workflow documents as validated JSON text while keeping ownership and lifecycle fields relational.
- BOOT-011-DEC-003: Represent global idempotency scope with a null repository foreign key and partial unique indexes, never a sentinel repository.
- BOOT-011-DEC-004: Treat canonical active worktree paths as installation-global resources while branch uniqueness remains repository-scoped.
- BOOT-011-DEC-005: Reservation ownership and fencing may transfer between attempts; its task, repository, branch, and path remain immutable.

## Acceptance Criteria

- BOOT-011-AC-001: Migrations apply to an empty test database and define the approved tables, indexes, checks, foreign keys, and triggers.
- BOOT-011-AC-002: All new records persist and load through Active Record with their specified associations and JSON documents.
- BOOT-011-AC-003: SQLite rejects cross-repository ownership, a second started attempt, non-monotonic or reused fencing tokens, and conflicting active reservations.
- BOOT-011-AC-004: Global and repository idempotency scopes isolate keys correctly, and SQLite rejects mutation or deletion of protected records.
- BOOT-011-AC-005: SQLite rejects artifact mutation, deletion, invalid type/state pairs, and metadata discriminator mismatches.
- BOOT-011-AC-006: Attempt lifecycle, frozen context, result-manifest, reservation ownership transfer, and task-pointer constraints are covered by persistence tests.
- BOOT-011-AC-007: Required focused and full project checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-011 active externally.
2. Add the execution persistence migration and database invariants.
3. Add minimal Active Record models and associations.
4. Add focused persistence and direct database-constraint specs.
5. Recreate and migrate the test database, then run focused and full checks.
6. Independently review the change and resolve findings within scope.
7. Record verification and implementation results, complete the external plan, commit, and push normally.

## Verification

- Run focused model persistence specs while iterating.
- Recreate and migrate the test database.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-10:

- Direct migration execution against an empty test database: passed for both migrations.
- Fresh `db/structure.sql` load followed by SQLite `foreign_key_check`: passed.
- `bundle exec rspec spec/models/workflow_attempt_spec.rb`: 36 examples, 0 failures.
- `mise run check`: passed with 204 examples, 0 failures, 59 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining high- or medium-severity findings after idempotency status, typed artifact metadata, task-pointer reciprocity, terminal-state, heartbeat, and SQLite trigger-rebuild corrections.

## Implementation Result

- Added persistence for workflow attempts and their leases, global and repository-scoped idempotency records, immutable task artifacts, and recoverable worktree reservations.
- Added composite ownership foreign keys, partial uniqueness, monotonic fencing, lifecycle and JSON checks, immutable-history triggers, and reciprocal task-pointer protection.
- Restored the existing task triggers after SQLite table reconstruction so the new cyclic references do not weaken BOOT-010 invariants.
- Added minimal Active Record associations, validations, UUID assignment, and JSON round-tripping without implementing workflow operations.
- Added database-level regression coverage for repository isolation, idempotency scopes, attempt ownership and lifecycle, typed artifact evidence, reservation transfer and uniqueness, and task execution pointers.

## Risks

- BOOT-011-RISK-001: SQLite partial indexes, triggers, and cyclic task-attempt references require direct database-level coverage.
- BOOT-011-RISK-002: This task protects stored shapes and relationships but intentionally defers operation-level transition and canonical digest validation.
