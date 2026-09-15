---
title: Base-Moved Publication Recovery
task: BOOT-047
created: 2026-09-15
status: completed
---

# BOOT-047: Base-Moved Publication Recovery

## Goal

Recover a quick-fix task from a durably confirmed publication base movement by synchronizing it with the current trusted base, producing a new checked candidate generation, and returning it to independent review.

## User Outcome

A quick-fix no longer remains stranded in `publication` after another publisher moves the trusted base. KOS safely rebases the task work onto the observed current base, requires checks for the resulting candidate, and repeats review before another publication attempt.

## Context

`quick-fix@1.0.1` is immutable and permits only `publication -> completed`; its `development` status permits only `commit`. Publication reconciliation already records `base_moved`, supersedes the publication, detaches it from the task, and prevents reuse of that candidate, but no declared workflow path can recover the task. The repository adapter already supports trusted fetch and verified rebase, while orchestration does not yet synchronize a successful rebase into the durable worktree reservation.

## Requirements

- BOOT-047-REQ-001: Preserve published `quick-fix@1.0.0`, `quick-fix@1.0.1`, and every released version 1 CLI/API contract unchanged.
- BOOT-047-REQ-002: Publish and activate immutable `quick-fix@1.0.2` with a dedicated executable `base-synchronization` status and a declared `publication -> base-synchronization -> review` recovery path.
- BOOT-047-REQ-003: Permit the recovery edge only through a specialized idempotent version 2 operation that revalidates a durable `base_moved` publication, current candidate generation, active publication attempt, lease, fencing token, task lock, and pinned transition.
- BOOT-047-REQ-004: Atomically close the publication attempt with durable transition evidence and move the task to `base-synchronization` without registering fabricated publication evidence.
- BOOT-047-REQ-005: Limit base synchronization to one trusted fetch followed by one verified rebase of the frozen worktree HEAD onto the fetched base-ref OID.
- BOOT-047-REQ-006: After successful rebase execution, verify canonical adapter rebase evidence, observe the exact resulting clean HEAD, and atomically reconcile rebase success and that canonical observation into the worktree reservation before returning the effect result to the executor. After interruption following that commit, require a replacement owner's trusted fetch and verified no-op rebase before completion.
- BOOT-047-REQ-007: Complete base synchronization only with the owner-bound successful fetch and rebase, the same frozen reservation, a new clean durable HEAD, one candidate artifact for that SHA, and one or more actual passed test artifacts bound to it.
- BOOT-047-REQ-008: Preserve immutable prior candidate, test, review, and publication evidence while preventing any prior-generation evidence from satisfying the new review or publication generation.
- BOOT-047-REQ-009: Preserve idempotency, optimistic-lock, lease, fencing, workflow-version pinning, repository trust, and concurrency invariants throughout recovery.
- BOOT-047-REQ-010: Update canonical runtime guidance and installation integrity for the complete recovery path.

## Scope

- Publication, workflow-execution, repository-isolation, artifact, and CLI version 2 specifications.
- An architecture decision for declared base-movement recovery through a new immutable workflow version.
- `quick-fix@1.0.2` source, publication fixtures, and activation in the bootstrap catalog.
- A minimal version 2 publication recovery command, REST binding, and application service.
- Base-synchronization completion guards and post-rebase worktree reconciliation.
- Canonical CLI, orchestration, and workflow-step guidance plus runtime installation integrity data.
- Focused service, request, CLI, schema, concurrency, contract, and real-Git tests.

## Non-Goals

- Migrating tasks pinned to `quick-fix@1.0.1`.
- Modifying or deleting published workflow versions.
- Successful terminal publication, `publication.complete`, worktree cleanup, or transition to `completed`.
- Durable pending publication results or interrupted terminal-cleanup recovery.
- Unknown generic-effect recovery, authoritative worktree allocation, or a background lease keeper.
- Automatic rebase-conflict resolution.

## Related Specifications And ADRs

- [Publication](../../docs/specs/publication.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 2](../../docs/specs/cli-protocol-v2.md)
- [ADR-0002](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)
- [ADR-0007](../../docs/decisions/0007-central-workflow-catalog.md)
- [ADR-0011](../../docs/decisions/0011-minimal-cli-v2-coexistence.md)

## Task-Local Decisions

- BOOT-047-DEC-001: Add `quick-fix@1.0.2` for new tasks instead of changing immutable `1.0.1` or adding an in-flight workflow migration mechanism.
- BOOT-047-DEC-002: Use a dedicated `base-synchronization` status rather than overloading ordinary development, whose single-commit contract also serves review-change recovery.
- BOOT-047-DEC-003: Keep the recovery operation in the additive version 2 surface because version 1 is released and immutable.
- BOOT-047-DEC-004: Treat rebase conflict, failure, or unknown outcome as non-success that leaves the task in recovery without a new candidate generation.

## Acceptance Criteria

- BOOT-047-AC-001: A durably superseded moved-base publication transitions exactly once from `publication` to `base-synchronization`, and replay returns the recorded result.
- BOOT-047-AC-002: Missing, foreign, stale, unresolved, wrong-candidate, or non-moved publication evidence cannot change task or attempt state.
- BOOT-047-AC-003: Concurrent reconciliation and recovery cannot create two transitions or bypass task lock, lease, or fencing ownership.
- BOOT-047-AC-004: Base synchronization fetches only registered trust, rebases only the frozen task worktree onto that fetched OID, and records a clean resulting HEAD in the durable reservation.
- BOOT-047-AC-005: Conflict, failed, unknown, mismatched, duplicate, or unsynchronized effects do not produce a candidate or advance to review.
- BOOT-047-AC-006: The new candidate differs from the superseded candidate, all supplied passed tests name it, and transition to review makes only that SHA current.
- BOOT-047-AC-007: Prior candidate tests, review, publication, and preflight evidence cannot satisfy the new generation.
- BOOT-047-AC-008: `quick-fix@1.0.2` is published and active for new tasks while `1.0.1` and version 1 contract fixtures remain byte-compatible.
- BOOT-047-AC-009: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-047 active externally.
2. Update affected behavioral specifications and add the base-movement recovery ADR.
3. Add and validate `quick-fix@1.0.2` with its recovery status and declared transitions.
4. Add the idempotent version 2 recovery schema, REST/CLI bindings, and atomic domain operation.
5. Add base-synchronization completion guards and post-rebase durable worktree HEAD reconciliation.
6. Update canonical runtime instructions, installation integrity data, and the live workflow catalog.
7. Add focused service, request, CLI, schema, concurrency, contract, and real-Git recovery coverage.
8. Run focused and full verification, validate the diff, and obtain independent review.
9. Record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused workflow catalog, publication recovery, workflow completion, repository-effect, API, CLI, schema, skill, concurrency, and real-Git specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-047-RISK-001: A new executable status expands the quick-fix graph; isolating recovery prevents ordinary development and review-change behavior from becoming conditional on publication history.
- BOOT-047-RISK-002: Rebase conflict cannot produce a safe automatic candidate and remains explicit non-success for later policy or human resolution.
- BOOT-047-RISK-003: Local real-Git tests do not fully verify live HTTPS or SSH authentication behavior.
- BOOT-047-RISK-004: Tasks already pinned to `quick-fix@1.0.1` remain fail-closed without automatic migration.

## Completion

- Implemented the declared `publication -> base-synchronization -> review` recovery path with atomic publication recovery and atomic rebase/worktree reconciliation.
- Preserved the released version 1 contracts and original full-snapshot rebase evidence digest while adding the partial version 2 recovery commands.
- Covered durable moved-base preconditions, idempotency, process races, canonical evidence, real Git fetch/rebase, post-reconciliation interruption, repeated interruption, candidate regeneration, checks, and renewed review.
- Published live `quick-fix@1.0.2` as `6954d17d-f43e-45eb-97d2-8cf2892ccc24` with digest `sha256:3ef55969eb81400d058e152e0d0fb903fe5db00d8ea89caea5118edd2f1016b5` and activated it for new quick-fix tasks.
- Final independent review reported no findings. `mise run check` passed with 819 examples; RuboCop, Zeitwerk, Brakeman, Bundler Audit, and `git diff --check` passed.
