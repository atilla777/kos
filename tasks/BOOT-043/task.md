---
title: Planning And Development Artifact Flow
task: BOOT-043
created: 2026-09-15
status: completed
---

# BOOT-043: Planning And Development Artifact Flow

## Goal

Make the production `quick-fix@1.0.1` planning and development statuses operational through one verified candidate SHA and its passed test artifacts, ready for an independent review attempt.

## User Outcome

Starting with a confirmed task worktree, planning commits one implementation plan, development commits one candidate and records its passed checks, and KOS advances the task atomically to `review` without inferred repository state or fabricated evidence.

## Context

The pinned workflow, approved task input, artifact validation, generic commit effects, repository adapter, and individual planning and development transitions already exist. The orchestrator cannot connect them safely because the CLI does not expose a complete repository snapshot, the worktree read omits persisted HEAD and observation state, and the canonical procedure does not synchronize a successful commit back into the durable reservation before the next status.

## Requirements

- BOOT-043-REQ-001: Add an authenticated repository-scoped `repository.get` read that returns the complete persisted repository snapshot required by `kos-repository` without direct API, SQLite, filesystem, or Git discovery by the orchestrator.
- BOOT-043-REQ-002: Extend `worktree.get` with the persisted confirmation, HEAD, and observation fields needed to construct and verify current adapter snapshots without changing reservation persistence.
- BOOT-043-REQ-003: After each successful planning or development commit effect, observe a clean worktree at the exact returned commit SHA and durably reconcile that observation before returning the effect result to the executor.
- BOOT-043-REQ-004: Planning must register exactly one task-scoped produced implementation-plan document backed by the planning commit and then advance atomically to development.
- BOOT-043-REQ-005: Development must start from the durably synchronized planning HEAD, use its successful commit SHA as the sole produced candidate, and bind one or more actual passed-test artifacts to that exact SHA.
- BOOT-043-REQ-006: Missing, duplicate, failed, stale, mismatched-SHA, unknown, or unresolved evidence must not advance the task to review.
- BOOT-043-REQ-007: Preserve published workflow versions and existing review, publication, persistence, Git-adapter, and artifact-validation behavior.

## Scope

- Version 1 repository and worktree read schemas, REST endpoints, CLI bindings, and documentation.
- Canonical CLI and orchestration skill guidance for post-commit worktree synchronization.
- A real-Git vertical integration path from planning through development to review and focused failure coverage.
- Runtime installation integrity updates required by changed canonical skills.

## Non-Goals

- Selecting or persisting a path for a new task worktree, or running the initial allocation protocol.
- Background lease renewal during a foreground child turn.
- Generic observation for an unknown repository effect.
- Independent review, publication, rebase orchestration, or complete quick-fix execution.
- A new database relationship between transition artifacts and repository-effect rows.
- A migration, workflow-version change, or new ADR.

## Related Specifications And ADRs

- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Publication](../../docs/specs/publication.md)
- [ADR-0001](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0002](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-043-DEC-001: Begin with an already reserved, materialized, and confirmed worktree. Authoritative allocation-path selection remains a separate task because no current specification defines that product or persistence policy.
- BOOT-043-DEC-002: Reuse the existing clean adapter observation and `worktree.reconcile` mutation after commit instead of adding another persistence operation.
- BOOT-043-DEC-003: Keep existing persisted Git evidence and attempt records without a migration or new foreign key. Completion validates that the frozen attempt's one successful commit effect, reservation observation, and transition artifact name the same commit.
- BOOT-043-DEC-004: Preserve the existing post-child lease freshness check; continuous lease renewal remains a separately recorded operational limitation.

## Acceptance Criteria

- BOOT-043-AC-001: A repository-scoped CLI read returns the complete closed current repository snapshot required by adapter requests.
- BOOT-043-AC-002: A worktree read returns lifecycle-appropriate persisted confirmation, HEAD, and observation data in a closed resource.
- BOOT-043-AC-003: Planning receives the exact approved task input, reconciles its successful commit into the reservation, registers one implementation-plan document, and advances to development.
- BOOT-043-AC-004: Development context uses the planning commit as worktree HEAD; development reconciles its commit, registers exactly one candidate and one or more passed tests for that SHA, and advances to review.
- BOOT-043-AC-005: At the review boundary the reservation HEAD equals the candidate SHA, both attempts succeeded, no attempt is active, and no repository effect is unresolved.
- BOOT-043-AC-006: Invalid artifact cardinality, failed checks, mismatched candidate generations, stale reservation state, and failed, unknown, or unresolved effects cannot produce the successful boundary.
- BOOT-043-AC-007: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-043 active externally.
2. Add `repository.get` to the versioned schemas, catalog, REST API, CLI, skills, and user-facing protocol documentation.
3. Complete the worktree reservation resource with existing persisted confirmation, HEAD, observation, and lifecycle timestamp fields.
4. Update canonical orchestration guidance to observe and reconcile the exact clean post-commit HEAD before returning a successful effect result and accepting planning or development evidence.
5. Add a real-Git vertical integration scenario and focused API, CLI, schema, skill, and failure contracts.
6. Update affected runtime installation digests and documentation.
7. Run focused and full verification, validate the diff, and obtain independent review.
8. Record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused repository/worktree read, CLI, schema, skill, workflow completion, repository-effect, and real-Git integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-15:

- The focused real-Git workflow, completion, repository-effect, repository/worktree API, CLI, schema, and skill suites passed.
- Final `mise run check` passed with 748 examples and no failures, 192 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- Affected OpenCode runtime installation and launcher integrity coverage passed with 54 examples and no failures.
- `git diff --check` passed.
- Independent review found and prompted fixes for missing completion-time HEAD/effect enforcement and legacy idempotency-response compatibility. Final re-review found no remaining blocking correctness or security issues.

## Implementation Result

- Added the authenticated repository-scoped `repository.get` REST and CLI read with the complete immutable registration and trust resource.
- Extended current worktree serialization with confirmation HEAD, latest observation, lifecycle timestamps, and update time while retaining schema compatibility with persisted pre-upgrade idempotency responses.
- Made planning and development completion require the frozen reservation, exactly one successful commit effect from that attempt, matching effect/artifact SHA, and a clean reconciled durable HEAD.
- Updated canonical runtime skills to obtain authoritative repository and worktree snapshots and perform post-commit observe/reconcile before returning success to the workflow executor.
- Added real-Git vertical coverage from planning through development to review, including rejection before HEAD synchronization and rejection without a successful commit effect.

## Risks

- The flow begins only after an authoritative worktree reservation is confirmed; a new task still lacks an operational allocation-path source.
- OpenCode foreground child execution still has no background lease keeper, so post-turn freshness validation prevents stale mutation but cannot stop edits made after lease expiry.
- Skill instructions and static contracts cannot prove compliance by every model.
