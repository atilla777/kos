---
title: Durable Publication Intent Lifecycle
task: BOOT-030
created: 2026-09-12
---

# BOOT-030: Durable Publication Intent Lifecycle

## Goal

Implement the durable publication intent lifecycle through the Rails REST API and `kos` CLI and make complete publication step context available without executing Git push.

## User Outcome

An orchestrator can durably prepare, inspect, reconcile, and recover publication of the exact reviewed candidate to the registered trusted remote and base ref before any external Git effect occurs.

## Context

The version 1 CLI schemas and publication specification already define publication resources and commands. Candidate and independent approved-review artifacts exist, but publication persistence, API and CLI bindings, recovery adoption, and publication context are not implemented. Publication `step.context` currently returns `context_unavailable` unconditionally.

## Requirements

- BOOT-030-REQ-001: Persist an immutable publication intent bound to its repository, task, preparing attempt, current owner attempt, reviewed candidate SHA, trusted remote, full base ref, expected remote OID, and preparation time.
- BOOT-030-REQ-002: Allow at most one unresolved publication per task and expose it through the task's `active_publication_id` with database-enforced repository and task scope.
- BOOT-030-REQ-003: Prepare only for the active leased publication attempt, exact current candidate, matching approved independent review transition, and repository-registered trusted remote and base ref.
- BOOT-030-REQ-004: Expose schema-valid `publication.get`, `publication.prepare`, and `publication.reconcile` operations through repository-scoped REST API and CLI bindings with standard idempotency, lock, lease, and fencing behavior.
- BOOT-030-REQ-005: Persist the latest owner-bound remote observation. Keep reachable or unchanged-base observations unresolved, and atomically supersede and detach an unreachable publication when the observed base moved while returning durable `base_moved`.
- BOOT-030-REQ-006: Reconcile an expired attempt as `publication_unknown` only when it owns an unresolved publication and no unresolved generic repository effect takes precedence.
- BOOT-030-REQ-007: Atomically adopt unresolved publications on a replacement claim without changing prepared parameters, and prevent a stale owner from mutating the adopted publication.
- BOOT-030-REQ-008: Prevent attempt failure, needs-human, or step completion while the attempt owns an unresolved publication.
- BOOT-030-REQ-009: Return complete immutable publication step context only after preparation or adoption and confirmed worktree allocation, including the exact publication ID, candidate SHA, trusted remote, base ref, and expected remote OID.
- BOOT-030-REQ-010: Do not execute Git, update refs, authenticate remote observations, complete publication, register publication artifacts, or advance the task to `completed`.
- BOOT-030-REQ-011: After base movement supersedes a publication, reject another publication intent for the same candidate SHA while allowing a newly checked and independently reviewed candidate generation.

## Scope

- Publication migration, constraints, model, associations, serialization, and task pointer.
- Prepare, get, reconcile, recovery adoption, reconciliation classification, and completion guards.
- Publication step context and digest capture.
- REST routes/controller and CLI transport bindings.
- A narrowly typed committed domain-error path for durable `base_moved`.
- Request, service, persistence, migration, concurrency, recovery, context, CLI, and regression tests.
- Focused user documentation updates.

## Non-Goals

- `kos-repository` push support or any Git subprocess execution.
- Mandatory-check execution, fetch-after-push, or adapter-authenticated remote evidence.
- `publication.complete`, publication artifact registration, or transition to `completed`.
- Runtime orchestration and a new candidate-generation path after base movement.

## Related Specifications And ADRs

- [Publication](../../docs/specs/publication.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-030-DEC-001: `publication.complete` remains outside this task so publication persistence and recovery can be reviewed independently from push and terminal artifact semantics.
- BOOT-030-DEC-002: A reconciled publication remains unresolved until future completion or supersession, including when the candidate is observed reachable.
- BOOT-030-DEC-003: An unresolved generic repository effect takes precedence over publication when classifying an expired attempt because its existing contract requires `repository_effect_pending` exactly.
- BOOT-030-DEC-004: The state service validates and stores the supplied expected remote OID and observation bindings but does not establish their Git provenance until the push adapter contract is implemented.
- BOOT-030-DEC-005: Durable `base_moved` uses a narrowly typed committed idempotent error outcome so the state transition and standard 409 response share one transaction.
- BOOT-030-DEC-006: Candidate generation identity is represented minimally by the candidate SHA for superseded-publication rejection; orchestration that creates the replacement generation remains outside this task.

## Acceptance Criteria

- BOOT-030-AC-001: Prepare atomically creates exactly one correctly scoped intent, sets the task pointer, and replays its original `201` response for the same idempotency request.
- BOOT-030-AC-002: Invalid candidate, review, trust, owner, lease, fencing, or changed idempotency payload leaves publication state unchanged.
- BOOT-030-AC-003: Task and publication reads return schema-valid resources without crossing repository scope.
- BOOT-030-AC-004: Publication context is unavailable before preparation and complete, consistent, digest-bound, and immutable after preparation.
- BOOT-030-AC-005: Reconciliation distinguishes reachable, retryable unchanged-base, and durable changed-base observations; terminal publication state is immutable.
- BOOT-030-AC-006: Lease recovery adopts the unresolved publication atomically, rejects the stale owner, and preserves generic-effect reconciliation precedence.
- BOOT-030-AC-007: Attempt terminal operations cannot bypass an unresolved publication.
- BOOT-030-AC-008: Concurrent prepare, reconcile, and claim preserve unique active intent, ownership, task-pointer, and idempotency invariants.
- BOOT-030-AC-009: Existing workflow, repository-effect, worktree, API, CLI, and schema contracts remain passing, and no Git adapter or push contract changes.
- BOOT-030-AC-010: Focused tests, the full project check, and `git diff --check` pass before normal commit and push to `main`.
- BOOT-030-AC-011: A superseded candidate cannot create a second intent or restore the task publication pointer, while a different current candidate remains eligible for normal prepare validation.

## Implementation Plan

1. Record this approved baseline and mark BOOT-030 active externally.
2. Add publication persistence, constraints, associations, serialization, and the active task pointer.
3. Implement prepare and reconcile with idempotent durable success and committed `base_moved` outcomes.
4. Add API routes/controller and CLI transport bindings.
5. Integrate recovery classification, claim adoption, terminal guards, and complete publication context capture.
6. Add focused persistence, request, CLI, context, recovery, idempotency, migration, and concurrency coverage.
7. Update focused user documentation and run focused tests, `mise run check`, and `git diff --check`.
8. Review the diff, record verification, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused publication, attempt recovery, context, CLI, contract, and idempotency specs while iterating.
- Rebuild and migrate the test database and run migration-sensitive publication coverage.
- Run `mise run check`.
- Run `git diff --check`.
- Confirm the repository adapter and its push schema remain unchanged.

Completed verification on 2026-09-12:

- Publication request, model, migration, recovery, context, CLI, idempotency, and multi-process concurrency specs passed during focused iteration.
- The publication migration completed an isolated populated-state `up/down/up` cycle successfully.
- Final `mise run check` passed with 561 examples and no failures, 154 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness and reliability reviews verified fixes for stale and future observation ordering, worktree-candidate consistency, durable observation ownership, SQLite constraints, concurrent preparation and reconciliation, and stale-candidate retry. No high- or medium-severity findings remained within the approved contract.
- `lib/kos/repository.rb` and `schemas/repository/` remained unchanged.

## Implementation Result

- Added durable publication records with immutable intent fields, repository/task/attempt composite foreign keys, one-unresolved-publication uniqueness, an active task pointer, protected observation provenance, lifecycle constraints, and terminal immutability.
- Implemented schema-valid repository-scoped `publication.get`, `publication.prepare`, and `publication.reconcile` REST and CLI operations with standard lock, lease, fencing, and idempotency behavior.
- Bound preparation to the current candidate, the approved independent review transition, and the repository's registered trusted remote and base ref, and prevented reuse of a superseded candidate.
- Added monotonic, bounded-time remote observations. Reachable and unchanged-base observations remain recoverable; changed-base observations atomically supersede and detach the publication while preserving an idempotent `base_moved` response.
- Added a narrowly typed committed operation error so the `base_moved` state change and its durable error response commit in one idempotency transaction.
- Added expired-attempt classification, atomic replacement-owner adoption, stale-owner fencing, generic-effect precedence, and application plus database guards against finishing an attempt with an unresolved publication.
- Made complete publication context available after preparation and confirmed allocation, with exact candidate/worktree HEAD consistency and immutable digest binding.
- Added request, model, migration, CLI, recovery, idempotency, and multi-process race coverage without adding Git execution or changing the repository adapter contract.

## Risks

- Until the push adapter exists, the state service cannot prove that a supplied remote observation came from the trusted Git boundary.
- A superseded publication requires a new candidate, checks, and review, but the operational workflow path that creates that generation is not part of this task.
- Publication and generic effects can coexist during recovery; deterministic classification and atomic multi-resource adoption require concurrency coverage.
- The version 1 publication resource exposes the current owner but not the internal historical observation owner. Persistence retains that provenance for future completion checks without changing the released closed schema.
