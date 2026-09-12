---
title: Durable Generic Repository Effects
task: BOOT-027
created: 2026-09-12
---

# BOOT-027: Durable Generic Repository Effects

## Goal

Implement the durable lifecycle for generic `commit`, `fetch`, and `rebase` repository effects through the REST API and Ruby CLI without executing Git operations.

## User Outcome

An orchestrator can idempotently prepare an effect intent before an external Git call, read it, record a `succeeded`, `failed`, or `unknown` result, and transfer every unresolved effect to a replacement attempt after lease recovery.

## Context

The version 1 CLI schemas already define generic effect requests, typed results, resources, commands, bindings, and stable errors. BOOT-026 implemented the local verified commit adapter, but Rails does not yet persist or expose generic effect intents.

## Requirements

- BOOT-027-REQ-001: Persist repository-scoped generic effect intents with immutable request, canonical request digest, preparing attempt, task, repository, and preparation time.
- BOOT-027-REQ-002: Implement `effect.get`, `effect.prepare`, and `effect.reconcile` through the existing version 1 REST and CLI contracts without executing Git.
- BOOT-027-REQ-003: Prepare an effect only for the active leased attempt with matching lock version, fencing token, frozen context digest, and allowed operation.
- BOOT-027-REQ-004: Bind `commit` and `rebase` reservation and expected HEAD to the frozen worktree context, and bind a `commit` task number to the owning task.
- BOOT-027-REQ-005: Compute the request digest over the complete effect request using RFC 8785 canonical JSON.
- BOOT-027-REQ-006: Reconcile only through the current owning attempt and require every result identity, context digest, request digest, and operation to match the stored intent.
- BOOT-027-REQ-007: Treat `prepared` and `unknown` as unresolved; allow an owned `unknown` intent to become `succeeded`, `failed`, or an updated `unknown`, while `succeeded` and `failed` remain immutable.
- BOOT-027-REQ-008: Allow multiple generic effects and atomically transfer all unresolved effects to a replacement attempt after reconciliation and claim without changing their original requests.
- BOOT-027-REQ-009: Reject attempt failure, needs-human completion, or successful step completion while the attempt owns an unresolved generic effect.
- BOOT-027-REQ-010: Accept `repository_effect_pending` attempt reconciliation only when an unresolved generic effect exists, and reject another observation classification while one exists.
- BOOT-027-REQ-011: Preserve repository-scoped idempotency, completed replay ordering, original HTTP status, and safe cross-repository not-found behavior.

## Scope

- Repository-effect migration, model, associations, constraints, and lifecycle guards.
- Prepare and reconcile application operations, read serialization, REST routes, and CLI transport.
- Claim adoption and guards on attempt reconciliation and completion.
- Model, service, request, CLI, migration, idempotency, and concurrency coverage.
- Focused specification and README updates for the implemented lifecycle.

## Non-Goals

- Executing `commit`, `fetch`, or `rebase` through `kos-repository`.
- Runtime skills or orchestrator integration.
- Publication and push lifecycle.
- Retaining a history of every intermediate unknown observation.
- Changing the CLI protocol version 1 document shape or adding a fetch trust policy.

## Related Specifications And ADRs

- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-027-DEC-001: Multiple generic effects are allowed; every `prepared` or `unknown` effect must be resolved before its owning attempt can finish.
- BOOT-027-DEC-002: Reconciliation replaces the latest `unknown` result. Version 1 does not retain separate observation history.
- BOOT-027-DEC-003: Fetch remote and ref receive schema validation only in this task; a later repository executor owns operation-specific trust validation.
- BOOT-027-DEC-004: Preparing the durable resource and completed idempotency response is one transaction, so the existing completed idempotency lifecycle is sufficient.

## Acceptance Criteria

- BOOT-027-AC-001: All three generic effect types complete schema-valid prepare, get, and reconcile round trips through REST and CLI.
- BOOT-027-AC-002: Idempotent replay returns one intent and the original status without rechecking an expired lease; changed input conflicts.
- BOOT-027-AC-003: Scope, context, allowlist, lock, lease, fencing, reservation, HEAD, task-number, digest, owner, and operation mismatches change no state.
- BOOT-027-AC-004: Successful and failed effects are immutable; prepared and unknown effects are adopted by a replacement attempt, whose ownership fences out the old attempt.
- BOOT-027-AC-005: Attempts cannot finish or report an inconsistent recovery classification while unresolved effects exist.
- BOOT-027-AC-006: Concurrent prepare, reconcile, and claim operations preserve ownership and lifecycle invariants.
- BOOT-027-AC-007: Existing attempt and worktree behavior remains covered and unchanged.
- BOOT-027-AC-008: Focused tests, `mise run check`, and `git diff --check` pass before commit and normal push to `main`.

## Implementation Plan

1. Record the approved baseline and mark BOOT-027 active externally.
2. Add repository-effect persistence with database-enforced ownership, shape, immutability, and lifecycle invariants.
3. Implement prepare, read, reconcile, serialization, REST routes, and CLI bindings.
4. Integrate unresolved-effect adoption and attempt reconciliation and completion guards.
5. Add focused lifecycle, API, CLI, migration, idempotency, and concurrency coverage.
6. Update applicable specifications and README.
7. Run focused checks, `mise run check`, and `git diff --check`.
8. Review the diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused model, service, request, CLI, migration, idempotency, and concurrency specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-12:

- Focused repository-effect, attempt, CLI, migration, and process-concurrency coverage passed with 127 examples and no failures before the final lifecycle additions.
- Final `mise run check` passed with 498 examples and no failures, 143 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- A populated execution database migrated forward, exercised the new durable effect and completion guard, and rolled back while preserving its pre-existing task and attempt rows.
- Independent reviews found and verified fixes for unknown-result owner attribution after adoption, active-owner database enforcement, incomplete request shape handling, stale request coverage, and concurrent replacement claim adoption.

## Implementation Result

- Added durable repository-effect persistence with composite repository/task/attempt ownership, canonical request digests, operation-specific JSON shape checks, lifecycle checks, immutable terminal state, retained history, and active leased-owner triggers.
- Implemented `effect.get`, `effect.prepare`, and `effect.reconcile` through the existing version 1 REST and CLI contracts for `commit`, `fetch`, and `rebase` without executing Git.
- Bound preparation to the active lease, fencing token, task lock, frozen context, effect allowlist, task number, reservation, and expected HEAD.
- Bound reconciliation to the current owner and exact stored intent identities, context digest, request digest, operation, and typed outcome.
- Added multiple-effect recovery: expired attempts report actual pending effects, replacement claims atomically adopt every unresolved intent, stale owners are fenced out, and unknown results remain schema-bound to the current owner.
- Blocked failed, needs-human, and successful completion while prepared or unknown effects remain unresolved, with both service-level stable errors and a database guard.
- Covered all three operation round trips, idempotency replay and conflict, ownership and context mismatches, unknown replacement, terminal immutability, cross-repository isolation, populated migration, and separate-process prepare/reconcile/claim races.
- Documented the implemented generic-effect lifecycle and CLI usage while retaining Git execution as a later adapter/runtime boundary.

## Risks

- BOOT-027-RISK-001: Version 1 retains only the latest unknown observation, not a complete observation history.
- BOOT-027-RISK-002: Git evidence authenticity remains dependent on a later repository-adapter contract.
- BOOT-027-RISK-003: Fetch trust policy is deferred to the executor boundary.
- BOOT-027-RISK-004: The populated-state production migration upgrade needs explicit verification.

The populated-state migration and rollback are covered through the Rails migration boundary. The production `kos:state:prepare` backup path was not rerun because this migration does not change that previously verified operator protocol.
