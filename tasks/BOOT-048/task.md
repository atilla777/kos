---
title: Durable Publication Result Before Cleanup
task: BOOT-048
created: 2026-09-15
status: completed
---

# BOOT-048: Durable Publication Result Before Cleanup

## Goal

Persist a verified publication result before worktree cleanup so an interrupted terminal release can resume without repeating the child result or Git push.

## User Outcome

A quick-fix publication that has proven the reviewed candidate reachable no longer loses its successful child result when cleanup is interrupted. A replacement attempt can retrieve the immutable result and safely continue only the pending worktree release.

## Context

Publication reconciliation durably records remote reachability, and worktree cleanup already uses a recoverable `release_pending -> remove -> released` protocol. The successful child result remains only in orchestration memory, however, because a started attempt cannot store its terminal result and `publication.complete` is not implemented. A crash before cleanup completion therefore loses the exact result that a later terminal completion must consume.

## Requirements

- BOOT-048-REQ-001: Add a separate immutable publication-result resource that preserves the exact successful child result manifest and verified publication observation before cleanup.
- BOOT-048-REQ-002: Bind the result to one repository, task, publication, producing attempt, frozen input context, reviewed candidate, trusted target, passed checks, and canonical reachable push evidence.
- BOOT-048-REQ-003: Recompute canonical push evidence at the server boundary rather than trusting a caller-supplied digest.
- BOOT-048-REQ-004: Expose idempotent version 2 record and read operations so a replacement owner can discover the result without the original idempotency key.
- BOOT-048-REQ-005: Preserve the original producing attempt and manifest identity; a replacement attempt authorizes recovery and cleanup without rewriting the result.
- BOOT-048-REQ-006: Prevent terminal publication cleanup at the application and database boundaries until the verified result is durable.
- BOOT-048-REQ-007: Preserve the existing two-phase conservative worktree release and allow recovery before release preparation, after `release_pending`, after physical removal, and after durable release.
- BOOT-048-REQ-008: Preserve released version 1 request and response schemas, published workflows, idempotency, optimistic locking, lease, fencing, repository scope, and immutable evidence.
- BOOT-048-REQ-009: Update canonical runtime guidance and installation integrity for immediate result recording and cleanup-only recovery.

## Scope

- Publication, workflow-execution, repository-isolation, artifact, and CLI version 2 specifications.
- An architecture decision for immutable publication-result handoff across attempts.
- Publication-result persistence, evidence verification, API/CLI v2 record/read operations, and cleanup guards.
- Runtime skill guidance and focused persistence, contract, concurrency, and interruption-recovery tests.

## Non-Goals

- Executing or retrying publication push.
- Implementing `publication.complete`, registering the terminal publication artifact, or moving the task to `completed`.
- Full quick-fix terminal end-to-end coverage.
- Changing published workflow definitions or released version 1 schemas.
- Recovering a child result that crashed before the recording transaction committed.

## Related Specifications And ADRs

- [Publication](../../docs/specs/publication.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 2](../../docs/specs/cli-protocol-v2.md)
- [ADR-0002](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)
- [ADR-0011](../../docs/decisions/0011-minimal-cli-v2-coexistence.md)

## Task-Local Decisions

- BOOT-048-DEC-001: Use a separate immutable result rather than changing mutable publication observation or storing a result on a started workflow attempt.
- BOOT-048-DEC-002: Keep the original attempt as result producer while a replacement attempt owns only recovery and cleanup authorization.
- BOOT-048-DEC-003: Add only the required publication-result operations to the partial version 2 surface.
- BOOT-048-DEC-004: Leave dirty or mismatched worktrees pending for explicit safe resolution rather than weakening cleanup checks.

## Acceptance Criteria

- BOOT-048-AC-001: At most one immutable result can be recorded for a publication, and idempotent replay returns it.
- BOOT-048-AC-002: Foreign, stale, unreachable, superseded, wrong-candidate, wrong-target, unreviewed, unchecked, malformed, or noncanonical evidence cannot create a result or change cleanup state.
- BOOT-048-AC-003: Publication cleanup cannot enter `release_pending` before the durable result exists, including when service validation is bypassed.
- BOOT-048-AC-004: After result recording, replacement attempts retrieve the exact original manifest and resume cleanup from every durable release boundary without another child result or push.
- BOOT-048-AC-005: Concurrent recording, claim, and release cannot create duplicate results or bypass task lock, lease, fencing, and repository ownership.
- BOOT-048-AC-006: Version 1 schemas and published workflow definitions remain unchanged.
- BOOT-048-AC-007: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-048 active externally.
2. Update affected behavioral specifications and add the publication-result durability ADR.
3. Add immutable publication-result persistence and canonical server-side push-evidence verification.
4. Add idempotent version 2 result record/read schemas, REST bindings, CLI commands, and serialization.
5. Enforce result-before-cleanup and cover replacement-owner recovery across the release lifecycle.
6. Update canonical runtime instructions and installation integrity data.
7. Add focused model, service, API, CLI, schema, concurrency, recovery, skill, and installer coverage.
8. Run focused and full verification, validate the diff, and obtain independent review.
9. Record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused publication-result, worktree-release, attempt-recovery, API/CLI v2, schema, skill, and installer specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-048-RISK-001: Git remains non-transactional with SQLite; immutable verified evidence and reconciliation bound the recovery state.
- BOOT-048-RISK-002: A crash before result recording commits cannot recover an unsubmitted in-memory child result.
- BOOT-048-RISK-003: Terminal completion remains deliberately unavailable until BOOT-049.

## Completion

- Added one immutable, repository-scoped publication result per publication with exact producer, frozen context, manifest, candidate, trusted target, approved review, passed checks, and canonical reachable push-evidence bindings.
- Added idempotent version 2 `publication_result.record` and `publication_result.get` API/CLI operations without changing version 1 schemas or published workflows.
- Enforced result-before-cleanup in the application and SQLite, including closed manifest structure, exact microsecond observation binding, immutable evidence, and concurrent insert guards.
- Replacement attempts now classify a recorded publication as cleanup-only recovery and resume the two-phase worktree release before preparation, from `release_pending`, after physical removal, or after durable release without another child result or push.
- Updated canonical runtime guidance and installation integrity checks. Terminal `publication.complete`, artifact registration, and transition to `completed` remain for BOOT-049.
- Final independent review reported no findings. `mise run check` passed with 840 examples; RuboCop, Zeitwerk, Brakeman, Bundler Audit, and `git diff --check` passed.
