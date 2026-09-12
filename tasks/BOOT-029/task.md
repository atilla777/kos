---
title: Verified Task Rebase Adapter
task: BOOT-029
created: 2026-09-12
---

# BOOT-029: Verified Task Rebase Adapter

## Goal

Implement a verified `rebase` operation in `kos-repository` that rebases a confirmed clean task worktree from its exact expected HEAD onto a verified fetched commit and returns the resulting HEAD with canonical evidence.

## User Outcome

An orchestrator can safely synchronize a task branch with the newly fetched trusted base. A stale, untrusted, conflicting, or ambiguous operation cannot silently rewrite the task branch or leave an ordinary conflict unresolved.

## Context

BOOT-027 implemented the durable REST and CLI lifecycle for generic rebase effects, and BOOT-028 implemented verified trusted fetch. The local repository adapter does not yet execute rebase or bind its target to verified fetch evidence.

## Requirements

- BOOT-029-REQ-001: Add closed version 1 adapter request, success, and operation-specific failure documents for rebase without changing the released CLI protocol version 1 documents.
- BOOT-029-REQ-002: Bind the request and evidence to the registered repository, confirmed reservation, generic-effect identity, current owner attempt, fencing token, and canonical durable rebase-request digest without querying Rails.
- BOOT-029-REQ-003: Accept `onto_sha` only when a schema-valid fetch request and result for the same registered repository and base ref have valid canonical evidence and returned that exact observed commit.
- BOOT-029-REQ-004: Validate canonical Git common-directory identity before lock creation, then repeat complete repository, reservation marker, worktree path, task branch, exact HEAD, clean index and worktree, and unfinished-operation validation under the common adapter lock.
- BOOT-029-REQ-005: Derive the replay range as a contiguous linear suffix of commits carrying the task number derived from the reserved branch; reject merge commits, a missing task suffix, or a foreign task commit, and require the fetched base to descend from the suffix's original base.
- BOOT-029-REQ-006: Treat an already synchronized task branch as a successful no-op; otherwise execute a deterministic non-interactive rebase without autostash, update-refs, rebase-merges, hooks, signing, editors, rerere, repository-configured executable filters, or custom merge drivers.
- BOOT-029-REQ-007: On an ordinary rebase conflict, abort and prove restoration of the original branch, HEAD, index, clean worktree, and absence of rebase metadata before returning a terminal nonretryable conflict.
- BOOT-029-REQ-008: Return a retryable uncertain failure when the resulting state or conflict restoration cannot be proved; durable recovery must observe state rather than blindly replaying the effect.
- BOOT-029-REQ-009: Return success only after verifying the reserved branch and worktree resulting HEAD, ancestry from `onto_sha`, clean index and worktree, absence of rebase metadata, and no ordinary ref changes except the reserved task branch.
- BOOT-029-REQ-010: Return canonical SHA-256 evidence binding repository, reservation and fencing snapshot, durable effect, verified fetch, original base, expected HEAD, onto SHA, and resulting HEAD. Failures expose no raw Git diagnostics, supplied paths, URLs, or credentials.

## Scope

- Repository-adapter schema, dispatch, rebase implementation, and minimal shared verification primitives.
- Contract and controlled real-Git integration coverage for success, rejection, conflict recovery, configuration isolation, and serialization.
- Focused repository-isolation specification and README updates.

## Non-Goals

- Rails persistence, REST or CLI workflow schema, or generic-effect lifecycle changes.
- Runtime skill or orchestrator integration.
- Updating the durable reservation HEAD after a successful rebase.
- Push or publication reconciliation.
- Merge-preserving rebase or manual continuation of a conflicted rebase.

## Related Specifications And ADRs

- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Publication](../../docs/specs/publication.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-029-DEC-001: Rebase authority comes from the immediately supplied verified fetch request and success evidence, not merely from a locally present commit object.
- BOOT-029-DEC-002: The task replay range is a linear contiguous suffix of commits with the reservation-derived task trailer. Version 1 rejects merge commits and foreign commits in that suffix rather than inferring an ambiguous fork point.
- BOOT-029-DEC-003: The fetched base must be a descendant of the original task base. Divergent or rewritten base history is not automatically reconciled.
- BOOT-029-DEC-004: An ordinary conflict is aborted and returned as a terminal conflict only after exact clean restoration is proved. Unprovable state is retryable and uncertain.
- BOOT-029-DEC-005: BOOT-029 implements only the local adapter effect. Runtime orchestration and durable reservation-HEAD synchronization remain separate work.

## Acceptance Criteria

- BOOT-029-AC-001: A non-conflicting rebase and an already synchronized no-op return a schema-valid resulting HEAD and evidence rooted in the verified fetched base.
- BOOT-029-AC-002: Invalid fetch provenance, stale HEAD, dirty state, incorrect reservation, nonlinear task history, and foreign task commits fail before the task branch changes.
- BOOT-029-AC-003: An ordinary content conflict restores the original clean worktree and HEAD before returning a nonretryable conflict; an unverified restoration is explicitly uncertain.
- BOOT-029-AC-004: No other ordinary ref, worktree, or index state changes on success, and no unfinished rebase metadata remains.
- BOOT-029-AC-005: Repository configuration cannot invoke external hooks, filters, merge drivers, signing, editors, rerere, autostash, update-refs, or merge-preserving behavior.
- BOOT-029-AC-006: Existing worktree, commit, and fetch behavior remains covered and unchanged; concurrent adapter operations serialize.
- BOOT-029-AC-007: Focused contract and integration tests, `mise run check`, and `git diff --check` pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-029 active externally.
2. Extend the adapter schema with closed rebase documents and contract tests.
3. Implement verified fetch provenance, task-history selection, and complete rebase preconditions.
4. Implement deterministic rebase execution, conflict abort and recovery classification, postconditions, and evidence.
5. Add real-Git success, safety, conflict, recovery, configuration-isolation, and concurrency coverage.
6. Update the repository-isolation specification and README.
7. Run focused checks, `mise run check`, and `git diff --check`.
8. Review the diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused repository adapter contract and integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-12:

- Focused repository adapter contract and real-Git integration specs passed with 108 examples and no failures.
- Final `mise run check` passed with 535 examples and no failures, 143 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- The repository adapter schema passed its draft 2020-12 metaschema check.
- `git diff --check` passed.
- Independent recovery and security reviews found and verified fixes for configured rebase strategies, deterministic rename and fork-point behavior, hardened abort execution, and unexpected post-effect exception classification. No high- or medium-severity findings remained.

## Implementation Result

- Added closed rebase request, success, and operation-specific failure documents carrying the confirmed reservation, durable effect snapshot, and complete verified fetch request and result.
- Recomputed the durable rebase and fetch request digests and fetch evidence digest, then required exact repository, trust, effect, owner, fencing, reservation, expected-HEAD, and target bindings.
- Derived only a nonempty linear suffix of commits with the reservation-derived `KOS-Task` trailer and rejected divergent fetched bases, merge histories, and foreign or missing task suffixes.
- Added deterministic `ort` replay with fixed rename semantics and disabled fork-point, autostash, update-refs, rebase-merges, rerere, notes rewriting, submodule recursion, maintenance, hooks, signing, and editors. Repository executable filters, merge drivers, submodule update commands, and rebase strategy overrides are rejected.
- Added verified successful no-op and replay outcomes with canonical evidence covering repository, reservation, durable effect, fetched target, original base, expected HEAD, and resulting HEAD.
- Added automatic conflict abort with exact semantic index, ref, HEAD, cleanliness, and unfinished-state restoration checks. Timeouts, failed aborts, unrelated ref movement, and unexpected post-effect observation errors return retryable `rebase_state_uncertain`.
- Covered success, no-op, evidence and target mismatch, dirty and staged state, unfinished operation, invalid and divergent history, conflict restoration, abort and observation faults, hardened configuration, primary-worktree isolation, and common-lock serialization with controlled Git repositories.
- Documented the adapter request, trust, replay, conflict, uncertainty, and deferred reservation synchronization contracts.

## Risks

- The adapter verifies the integrity and binding of supplied fetch evidence but cannot independently establish the freshness of orchestrator-supplied owner and fencing snapshots without querying Rails.
- Runtime orchestration does not yet invoke rebase or synchronize a successful resulting HEAD into the durable reservation.
- Unrelated Git processes do not honor the adapter lock. Ref and worktree postconditions detect observed interference, but a process race outside `kos-repository` cannot be atomically fenced by Git.
- Rebase depends on objects reachable from the verified fetched commit, while verified fetch proves the commit object but not complete reachable-object closure; missing objects cause a safe rebase failure rather than a successful result.
