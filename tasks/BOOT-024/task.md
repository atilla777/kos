---
title: Recoverable Worktree Reservation Lifecycle
task: BOOT-024
created: 2026-09-11
---

# BOOT-024: Recoverable Worktree Reservation Lifecycle

## Goal

Implement the idempotent worktree reservation lifecycle through the REST API and CLI: `reserve -> confirm`, recovery through `reconcile`, and explicit cleanup through `release`, without executing Git commands in the KOS state service.

## User Outcome

An orchestrator can safely reserve a unique task branch and worktree path, hand materialization or removal to `kos-repository`, confirm observed state, and recover after a lost lease or response without allowing another task to occupy the worktree.

## Context

Worktree reservation persistence, lease and fencing ownership, optimistic locking, repository-scoped idempotency, the read-only `worktree.get` command, and the version 1 wire contracts already exist. The reservation mutation operations, API routes, and CLI bindings do not.

## Requirements

- BOOT-024-REQ-001: Every operation checks repository scope, path/body identity, expected task lock version, active attempt ownership, lease expiry, and fencing token before mutation.
- BOOT-024-REQ-002: `worktree.reserve` accepts only the task-derived branch and a lexically canonical absolute path without traversal or NUL bytes.
- BOOT-024-REQ-003: Active task, repository branch, and installation-wide path uniqueness remain transactionally enforced.
- BOOT-024-REQ-004: Repository-scoped idempotency replays the original result, while key reuse with a different payload returns `idempotency_conflict`.
- BOOT-024-REQ-005: A new attempt adopts an unresolved reservation after reconciliation of its previous attempt by changing only its current owner and fencing token.
- BOOT-024-REQ-006: `worktree.confirm` verifies the observed Git common-directory digest against the registered repository, stores the confirmed HEAD, and attaches the reservation to the task.
- BOOT-024-REQ-007: `worktree.reconcile` durably records the allowed observation and evidence. A clean observation with a HEAD confirms or preserves an adoptable reservation; absence completes safe release; dirty or mismatched observations preserve the allocation and prohibit automatic adoption or removal.
- BOOT-024-REQ-008: `worktree.release` uses two-phase cleanup: an observed clean worktree enters `release_pending`, while a later absent observation atomically clears the task pointer and marks the reservation released.
- BOOT-024-REQ-009: Released reservations remain immutable history but stop occupying active uniqueness keys.
- BOOT-024-REQ-010: SQLite protects lifecycle, allocation identity, ownership, and terminal-history invariants when application validation is bypassed.
- BOOT-024-REQ-011: API and CLI implement the existing version 1 request, response, status, and stable error contracts without changing the wire schema.
- BOOT-024-REQ-012: KOS does not inspect or mutate Git or the filesystem and never automatically removes a dirty or mismatched worktree.

## Scope

- Application operations for reserve, confirm, reconcile, and release.
- Adoption of an unresolved reservation by a newly claimed attempt.
- Database lifecycle guards required by the operations.
- Authenticated REST routes, thin controller actions, serialization, and Ruby CLI bindings.
- Service, persistence, request, CLI, idempotency, recovery, and concurrency tests.
- Narrow behavioral specification and user documentation updates.

## Non-Goals

- Implementing `kos-repository` or executing any Git command.
- Generic repository effects or publication lifecycle operations.
- Automatically deleting dirty, mismatched, or unknown worktrees.
- Changing CLI protocol version 1.

## Related Specifications And ADRs

- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-024-DEC-001: State-service path validation is lexical only. Filesystem identity, symlink containment, and Git common-directory observation remain `kos-repository` responsibilities.
- BOOT-024-DEC-002: The expected common-directory digest is SHA-256 over the repository's canonical persisted UTF-8 path.
- BOOT-024-DEC-003: `release_pending` is the durable intent boundary between observing a removable clean worktree and observing its later absence.
- BOOT-024-DEC-004: A clean reconciliation requires an observed HEAD; dirty and mismatched observations remain durable blockers without releasing uniqueness keys.
- BOOT-024-DEC-005: Existing CLI version 1 resource documents remain unchanged and therefore do not expose internal observation columns.

## Acceptance Criteria

- BOOT-024-AC-001: All four mutation commands return schema-valid reservation resources with their cataloged HTTP statuses.
- BOOT-024-AC-002: Crashes before materialization, after materialization, and after removal can be reconciled without blindly repeating a Git effect.
- BOOT-024-AC-003: Concurrent reserve operations cannot create conflicting active task, branch, or path allocations.
- BOOT-024-AC-004: Stale lock, expired lease, stale fencing, invalid branch or path, cross-repository access, and invalid lifecycle transitions fail without partial state.
- BOOT-024-AC-005: A new attempt can adopt an unresolved reservation and the previous fencing token can no longer mutate it.
- BOOT-024-AC-006: Dirty or mismatched worktrees are never automatically released.
- BOOT-024-AC-007: Focused checks, the full project check, RuboCop, and diff validation pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-024 active externally.
2. Add database guards for allowed lifecycle transitions and immutable reservation evidence.
3. Implement reservation operations and adoption during attempt claim.
4. Add REST routes and controller transport plus Ruby CLI bindings.
5. Add recovery, idempotency, repository-isolation, and synchronized concurrency coverage.
6. Update behavioral specifications and README.
7. Run focused checks, `mise run check`, and `git diff --check`.
8. Review the completed diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused reservation service, request, CLI, persistence, idempotency, and concurrency specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused reservation lifecycle, persistence, API, CLI, idempotency, recovery, adoption, and synchronized multi-process path-contention specs passed.
- `mise run check`: passed with 408 examples, 0 failures, 131 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found and verified fixes for pending-cleanup HEAD rebinding, unguarded `release_pending`, direct release without a prepared cleanup intent, and mutable pending HEAD. Final review found no remaining high- or medium-severity findings.

## Implementation Result

- Added idempotent reservation, confirmation, reconciliation, and two-phase release application operations with repository, lock, lease, and fencing validation.
- Added lexical allocation-path validation, task-derived branch enforcement, registered common-directory digest verification, and durable clean, absent, dirty, and mismatched observations without Git or filesystem access.
- Added unresolved-reservation ownership transfer during a later attempt claim while preserving allocation identity.
- Added SQLite lifecycle, confirmation-identity, pending-HEAD, and released-history guards.
- Added authenticated REST routes and Ruby CLI bindings for all four existing version 1 worktree mutation contracts.
- Covered recovery, stale ownership, idempotent replay and conflict, path/body mismatch, repository isolation, database bypass, and installation-wide concurrent path allocation.

## Risks

- BOOT-024-RISK-001: Claim, reserve, reconcile, and release must use a consistent lock order to avoid contention and stale ownership.
- BOOT-024-RISK-002: Observation evidence is trusted only from the current lease owner; later adapter contract tests must prove how `kos-repository` generates it.
- BOOT-024-RISK-003: Lexical path canonicalization does not prove filesystem identity; the repository adapter must still reject symlink escape and common-directory mismatch before a Git effect.

The first risk is covered for installation-wide path contention, but claim/adoption racing directly with reconcile or release is not separately process-tested. Adapter-generated evidence, symlink containment, filesystem identity, and a populated-state migration upgrade remain deferred or unverified as described by the approved boundary.
