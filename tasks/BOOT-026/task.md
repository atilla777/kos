---
title: Verified Task Commit Adapter
task: BOOT-026
created: 2026-09-12
---

# BOOT-026: Verified Task Commit Adapter

## Goal

Extend `kos-repository` with a safe task commit operation that creates a commit only after proving the reservation, HEAD, requested diff, and staged index.

## User Outcome

An orchestrator can ask the repository adapter to commit an exact set of task files and receive the observed commit SHA and evidence. A stale, mismatched, or ambiguous request cannot create a commit or include unrelated staged work.

## Context

BOOT-025 implemented the closed local adapter contract and safe Git boundary for worktree materialization, observation, and removal. CLI protocol version 1 already defines the typed commit request and its diff, index, and `KOS-Task` trailer requirements, but the repository adapter does not execute that operation yet.

## Requirements

- BOOT-026-REQ-001: Add a closed version 1 `commit` request and result to `kos-repository` without changing the existing CLI protocol version 1 documents.
- BOOT-026-REQ-002: Accept commits only for a confirmed reservation whose repository, marker, canonical worktree path, branch, fencing snapshot, and exact HEAD match the request.
- BOOT-026-REQ-003: Require a clean index relative to the expected HEAD before staging and reject unfinished Git operations.
- BOOT-026-REQ-004: Accept only unique canonical repository-relative file paths, treat them as literal paths, and reject directories, aliases, overlap, pathspec magic, and paths outside the worktree.
- BOOT-026-REQ-005: Verify `expected_diff_digest` from the exact protocol-defined Git diff bytes with external diff and text conversion disabled before staging only the requested paths.
- BOOT-026-REQ-006: Verify `expected_index_digest` from the protocol-defined byte-sorted staged entries before creating a commit, and reject an empty staged result.
- BOOT-026-REQ-007: Reject an input message containing a parsed `KOS-Task` trailer and append exactly one authoritative `KOS-Task: <task-number>` trailer.
- BOOT-026-REQ-008: Require the task number to derive the reservation branch and verify that the created commit has the expected parent, exact validated tree, and exactly one correct task trailer.
- BOOT-026-REQ-009: Restore the index to the expected HEAD after an index mismatch or commit failure while preserving worktree files.
- BOOT-026-REQ-010: Serialize the complete operation under the common-directory lock; construct the exact tree through an isolated index; advance the task branch only with a compare-and-swap from the expected HEAD; and disable hooks, editors, signing, external diff, text conversion, global and system configuration, replacement objects, filesystem monitors, prompts, pagers, and lazy fetching.
- BOOT-026-REQ-011: Return a closed safe result containing the created commit SHA and canonical evidence digest, or a stable error without raw Git stderr or unsafe path disclosure.

## Scope

- Repository adapter schema, dispatch, shared reservation validation, and commit execution.
- Contract and real-Git integration tests for successful, rejected, interrupted, and concurrent operations.
- Repository-isolation specification and README updates.

## Non-Goals

- Rails persistence or REST/CLI implementation for `effect.prepare`, `effect.get`, or `effect.reconcile`.
- Runtime skills, orchestrator integration, or a runtime mechanism for producing expected digests.
- Fetch, rebase, push, or publication operations.
- Changing a released CLI protocol document shape or semantic version. The draft version 1 digest command may be corrected to explicitly disable text conversion required by its existing no-external-command invariant.
- Predictable commit SHAs, author identity, committer identity, or timestamps; Git uses the repository-local identity and current time while signing remains disabled.

## Related Specifications And ADRs

- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Publication](../../docs/specs/publication.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-026-DEC-001: Existing staged changes are rejected rather than preserved or included.
- BOOT-026-DEC-002: A caller-supplied `KOS-Task` trailer is rejected; only the adapter adds the authoritative trailer.
- BOOT-026-DEC-003: Commit paths name exact files. Directory expansion and overlapping path scopes are not supported.
- BOOT-026-DEC-004: A failed operation restores the index to the expected HEAD while preserving worktree content.
- BOOT-026-DEC-005: BOOT-026 implements the local adapter effect only. Durable generic-effect orchestration remains separate work.
- BOOT-026-DEC-006: Review demonstrated that `--no-ext-diff` still permits repository-configured text conversion. The approved revised baseline adds `--no-textconv` to the normative digest command.
- BOOT-026-DEC-007: The adapter stages and validates through an isolated temporary index, creates a commit from the explicit verified tree, and advances the reserved branch with an expected-HEAD compare-and-swap so unrelated index mutation cannot enter the commit.

## Acceptance Criteria

- BOOT-026-AC-001: A valid request creates one schema-valid task commit whose parent, tree, paths, and sole `KOS-Task` trailer match the request.
- BOOT-026-AC-002: Repository, reservation, marker, fencing snapshot, branch, HEAD, path, diff, index, task-number, and unfinished-operation mismatches fail before a commit is created.
- BOOT-026-AC-003: Unrequested staged or unstaged files, including entries introduced concurrently by a non-adapter Git process, cannot enter the commit, and unsafe or ambiguous paths are rejected.
- BOOT-026-AC-004: Digest mismatch and Git commit failure preserve worktree files and restore the original clean index.
- BOOT-026-AC-005: Commit execution cannot invoke hooks, editors, signing, external diff, text conversion, filesystem monitors, or global/system Git configuration.
- BOOT-026-AC-006: Concurrent adapter operations serialize; only a request whose expected HEAD remains current can commit.
- BOOT-026-AC-007: Existing materialize, observe, and remove behavior remains covered and unchanged.
- BOOT-026-AC-008: Focused contract and integration tests, `mise run check`, and `git diff --check` pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-026 active externally.
2. Add the commit request, success, and closed error contract with contract tests.
3. Extract shared reservation and worktree verification needed by worktree and commit operations.
4. Implement exact path, diff, index, staging, trailer, commit, rollback, and evidence behavior.
5. Add real-Git success, safety, recovery, configuration-isolation, and concurrency coverage.
6. Update the repository-isolation specification and README.
7. Run focused checks, `mise run check`, and `git diff --check`.
8. Review the diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused repository adapter contract and integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Initial review found safety gaps in mutable-index isolation, text-conversion suppression, configured clean filters, ref-update classification, and path traversal races. Revised verification completed on 2026-09-12:

- Focused repository adapter contract and real-Git integration specs passed with 71 examples and no failures.
- `mise run check` passed with 479 examples, 0 failures, 134 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- The repository adapter schema passed its draft 2020-12 metaschema check.
- `git diff --check` passed.
- Independent reviews verified isolated-index commit creation, filter suppression, compare-and-swap recovery, operation-specific schemas, and descriptor-relative path containment. The final review found no remaining high- or medium-severity findings after its path-race fix.

## Implementation Result

- Extended the closed repository adapter version 1 contract and dispatch with a confirmed-reservation `commit` operation, operation-specific success, and closed operation-specific failures.
- Added exact repository, marker, path, task-derived branch, fencing snapshot, HEAD, clean-index, and unfinished-operation validation under the common-directory lock.
- Added literal exact-regular-file validation, including nested deletions and tracked-symlink rejection, and protocol-defined diff and temporary-index digest verification with external diff and text conversion disabled.
- Added parsed trailer rejection, one authoritative `KOS-Task` trailer, and post-commit parent, tree, HEAD, and trailer verification.
- Added an isolated index seeded from the expected HEAD, complete exact-tree validation, explicit `commit-tree` creation, and compare-and-swap advancement of only the reserved branch with uncertain-result observation.
- Added post-success requested-path index reconciliation under Git's index lock so concurrent unrelated staged entries are preserved and a concurrently locked real index is never overwritten.
- Made successful compare-and-swap definitive, with observation-based classification only for failed or raised updates, including timeout recovery and unavailable observations.
- Rejected requested paths with configured clean or process filters before diff generation or staging.
- Replaced temporary-index `git add` with no-filter blob creation and explicit mode/OID/path index updates or tracked-file removal, preserving normal `core.filemode` behavior and making the expected index digest authoritative.
- Rechecked filter policy around diff and staging and covered a deterministic late-attribute/configuration injection without executing its clean filter.
- Replaced pathname revalidation with Linux descriptor-relative traversal from a proven canonical reservation-root descriptor, keeping all parent descriptors open through hashing and rejecting deterministic intermediate-directory swap-and-restore attacks before `hash-object`.
- Covered success, nested deletion, deleted symlink rejection, stale and unsafe requests, unrelated staged-index races, occupied real index locks, uncertain ref-update recovery, definitive CAS behavior, configuration isolation including textconv and clean-filter traps, and concurrent commit serialization with real Git repositories.
- Documented the adapter invocation, safety contract, digest protocol, evidence, and deferred Rails/runtime integration boundary.

## Risks

- BOOT-026-RISK-001: Git cannot atomically validate that an orchestrator-supplied KOS fencing token remains current. The adapter constrains stale effects with the durable reservation marker, exact branch and HEAD, and common-directory serialization.
- BOOT-026-RISK-002: Expected digest production and durable lost-response reconciliation are not executable end to end until generic repository-effect persistence and runtime integration exist.
- BOOT-026-RISK-003: A process termination during compare-and-swap branch update can produce an unknown result. The adapter observes the reserved ref when it receives an uncertain response; a lost adapter response still requires the caller to observe HEAD and reconcile the durable effect rather than replay the stale request.
- BOOT-026-RISK-004: Real-index refresh after a successful commit is best effort. If another process owns the Git index lock, the adapter preserves that lock and index byte-for-byte; requested entries may remain stale until a later refresh, but commit success and exact committed content are unaffected.
