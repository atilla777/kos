---
title: Safe Git Worktree Adapter
task: BOOT-025
created: 2026-09-11
---

# BOOT-025: Safe Git Worktree Adapter

## Goal

Implement `kos-repository` as the sole local executor for materializing, observing, and removing a reserved Git worktree.

## User Outcome

An orchestrator can safely complete `reserve -> materialize -> confirm` and two-phase worktree removal. Recovery after interruption does not occupy another reservation's worktree or delete dirty or mismatched data.

## Context

BOOT-024 implemented the persistent reservation lifecycle through the REST API and `kos` CLI without executing Git. No `kos-repository` implementation or adapter machine contract currently exists.

## Requirements

- BOOT-025-REQ-001: Provide a separate non-interactive Ruby `bin/kos-repository` executable with a closed versioned JSON contract for `materialize`, `observe`, and `remove`.
- BOOT-025-REQ-002: Before an effect, validate repository UUID, canonical Git common directory, reservation UUID, fencing token, canonical path, branch, and expected base or HEAD SHA.
- BOOT-025-REQ-003: Materialize only an absent target or a worktree provably owned by the same reservation, create the task branch from an explicit expected SHA, and verify the registered base ref resolves to that SHA.
- BOOT-025-REQ-004: A repeated invocation after a completed Git effect returns the same observed result without repeating creation or adopting an unproven worktree.
- BOOT-025-REQ-005: Return a canonical `absent`, `clean`, `dirty`, or `mismatched` observation with the applicable HEAD and a SHA-256 evidence digest.
- BOOT-025-REQ-006: Treat staged, unstaged, untracked, or ignored changes and an unfinished Git operation as dirty.
- BOOT-025-REQ-007: Remove only a proven reservation worktree whose branch and HEAD match the request and whose complete observed state is clean.
- BOOT-025-REQ-008: Use non-forced `git worktree remove`; never recursively delete the path or delete the task branch.
- BOOT-025-REQ-009: Reject symlinked or non-canonical repository, parent, target, and Git metadata paths and require the target parent to exist.
- BOOT-025-REQ-010: Serialize mutations per Git common directory and execute Git with argument arrays, bounded timeouts, no global configuration, prompts, pager, external hooks, replacement objects, or lazy fetch.
- BOOT-025-REQ-011: Support only SHA-1 repositories required by CLI protocol version 1 and return closed safe errors without raw Git stderr, credentials, or unsafe path disclosure.

## Scope

- Executable and Ruby adapter for worktree materialization, observation, and removal.
- Versioned request, result, observation, and error schemas.
- Canonical evidence generation and reservation ownership marker in Git worktree metadata.
- Real-repository integration, race, and fault-injection tests.
- Focused repository-isolation specification and README updates.

## Non-Goals

- Runtime skill installation or OpenCode integration.
- Calling the Rails API or `kos` CLI from the adapter.
- Commit, fetch, rebase, or push operations.
- Changing CLI protocol version 1 or reservation persistence.
- Creating missing parent directories, forced cleanup, branch deletion, or automatic repair of mismatched state.

## Related Specifications And ADRs

- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-025-DEC-001: Phase 3 provides a local Ruby executable and contract; the runtime-facing skill remains phase 4 work.
- BOOT-025-DEC-002: The adapter trusts an orchestrator-supplied closed repository and reservation snapshot but verifies every supplied identity and operation precondition against Git and the filesystem.
- BOOT-025-DEC-003: The exact reservation path is the containment boundary. Its existing parent and every existing target and Git metadata component must already be canonical and non-symlinked.
- BOOT-025-DEC-004: A reservation marker stored in linked-worktree Git metadata is required before an existing worktree can be treated as an idempotent materialization.
- BOOT-025-DEC-005: Ignored files make cleanup dirty to prefer preserving local data over automatic deletion.
- BOOT-025-DEC-006: Local per-common-directory locking reduces adapter races; operation-specific path, branch, marker, and SHA checks provide external-effect fencing where Git cannot enforce a KOS token atomically.

## Acceptance Criteria

- BOOT-025-AC-001: A valid reservation materializes at the exact branch and base SHA and returns schema-valid confirmation evidence.
- BOOT-025-AC-002: Repeating materialization after a lost successful response returns the same observation without creating another worktree.
- BOOT-025-AC-003: Wrong repository, token, path, symlink, branch, HEAD, pre-existing branch, or unproven worktree fails without destructive mutation.
- BOOT-025-AC-004: Dirty and mismatched worktrees are never removed, while successful removal is recoverable as an absent observation.
- BOOT-025-AC-005: Concurrent adapter invocations cannot mutate the same repository simultaneously.
- BOOT-025-AC-006: Contract, integration, recovery, and fault-injection tests, the full project check, RuboCop, and diff validation pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-025 active externally.
2. Add adapter JSON schemas and contract tests.
3. Implement the safe Git runner, canonical path and common-directory validation, locking, and evidence digest.
4. Implement observation, idempotent materialization, and safe removal.
5. Add the executable and structured error transport.
6. Add real Git repository, symlink, dirty-state, collision, concurrency, and interruption coverage.
7. Update the behavioral specification and README.
8. Run focused checks, `mise run check`, and `git diff --check`.
9. Review the diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused adapter contract and integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused adapter contract and real-Git integration specs passed with 32 examples and no failures.
- `mise run check`: passed with 440 examples, 0 failures, 134 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review reproduced and verified fixes for repository-configured fsmonitor execution, private gitdir acceptance, nested Git metadata symlinks, interrupted unlock recovery, and an open-ended error schema. Final review found no remaining high- or medium-severity findings.

## Implementation Result

- Added the closed repository adapter protocol version 1 for materialize, observe, remove, success observations, and stable safe failures.
- Added `bin/kos-repository` with bounded isolated Git execution, SHA-1 enforcement, canonical repository and worktree identity checks, and per-common-directory serialization.
- Added reservation markers in linked-worktree metadata so completed materialization can be replayed without adopting an unproven branch or path.
- Added deterministic evidence for absent, clean, dirty, and mismatched observations, including conservative ignored-file and unfinished-operation detection.
- Added idempotent clean removal that survives an interrupted unlock, never forces deletion, and leaves the task branch intact.
- Covered real Git materialization, replay, cleanup, collisions, symlink containment, fsmonitor suppression, timeout termination, dirty states, deterministic evidence, and concurrent adapter instances.

## Risks

- BOOT-025-RISK-001: Git cannot atomically enforce a KOS fencing token. Reservation identity, durable marker, expected branch and SHA, and local serialization constrain stale effects.
- BOOT-025-RISK-002: Termination inside `git worktree add` can leave an unproven partial worktree. It must be reported as mismatched rather than adopted or deleted automatically.
- BOOT-025-RISK-003: Treating ignored files as dirty may require explicit operator cleanup, but avoids deleting local generated data.

The first risk is constrained by exact reservation marker, branch, path, expected SHA, and common-directory checks plus local serialization. Runtime invocation remains intentionally unverified until the phase 4 runtime skill exists. Concurrency is synchronized through real file locks but the automated race uses concurrent adapter instances in one process rather than separate executable processes.
