---
title: Atomic Workflow Step Completion
task: BOOT-022
created: 2026-09-11
---

# BOOT-022: Atomic Workflow Step Completion

## Goal

Implement `step.complete` so a successful workflow step validates its result and artifact contract, registers transition artifacts, succeeds its attempt, and advances its task atomically.

## User Outcome

An orchestrator can submit one successful result manifest through the KOS CLI and receive the advanced task with its immutable registered artifacts. Invalid, stale, or concurrent submissions cannot leave partial workflow state.

## Context

Published workflows already persist typed states, transitions, conditions, and artifact requirements. Workflow attempts already provide repository-scoped idempotency, frozen-context binding, optimistic locking, leases, fencing, and terminal persistence. The draft CLI v1 contract declares `step.complete`, but no completion operation, transition evaluator, API route, or CLI binding exists.

## Requirements

- BOOT-022-REQ-001: `step.complete` checks repository and task scope, path/body identity, expected task lock version, active attempt ownership, fencing token, and lease expiry before changing workflow state.
- BOOT-022-REQ-002: Completion accepts only a `succeeded` result manifest whose attempt ID and input-context digest exactly match the active attempt's frozen context.
- BOOT-022-REQ-003: The requested target must be a declared outgoing transition from the task's current state in its pinned workflow version, and generic completion cannot bypass specialized publication completion.
- BOOT-022-REQ-004: Transition conditions, required artifact types, allowed states, and cardinality are evaluated from only the current successful manifest. Undeclared artifacts are rejected.
- BOOT-022-REQ-005: Candidate-scoped evidence names one consistent current candidate generation. A candidate trailer matches the owning task, and review evidence names the current review attempt, which differs from the candidate-producing attempt.
- BOOT-022-REQ-006: Document and candidate Git evidence is verified against the registered repository through a safe read-only adapter without extending the database write transaction around Git commands.
- BOOT-022-REQ-007: Artifact registration, attempt success and immutable manifest persistence, active-lease release, and task workflow-state advancement occur in one database transaction.
- BOOT-022-REQ-008: Repository-scoped idempotency replays a completed result before mutable lock, lease, and fencing checks. Competing completions produce one transition and one artifact set.
- BOOT-022-REQ-009: API and CLI use the existing draft version 1 `step.complete` request, response, status, and stable error contracts.
- BOOT-022-REQ-010: A succeeded attempt durably references the immutable workflow transition it completed so any selected `decision` condition and value remain recoverable after later task transitions.

## Scope

- Workflow-transition and artifact-contract validation for successful generic step completion.
- Read-only Git verification required by document and candidate artifact contracts.
- Atomic completion application operation.
- Authenticated REST route, thin controller action, and Ruby CLI binding for `step.complete`.
- Service, request, CLI, contract, rollback, and multi-process concurrency tests.
- Narrow draft schema or specification clarifications required by implementation findings.

## Non-Goals

- `step.context`, standalone `artifact.register`, or any worktree, repository-effect, or publication mutation.
- Dependency and hierarchy execution, which remain deferred beyond the quick-fix MVP.
- Mutating Git operations or substantive assessment of artifact quality.
- A new protocol version, command, stable error code, or architecture decision.

## Related Specifications And ADRs

- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Task Model](../../docs/specs/task-model.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)

## Task-Local Decisions

- BOOT-022-DEC-001: `step.complete` registers only source-state transition artifacts supplied by its successful manifest; previously registered standalone artifacts never satisfy completion retroactively.
- BOOT-022-DEC-002: Cardinality `one` means exactly one artifact and `many` means one or more artifacts.
- BOOT-022-DEC-003: The current candidate is the candidate from the latest succeeded candidate-producing attempt by fencing token. A new candidate therefore starts a new evidence generation without mutating historical artifacts.
- BOOT-022-DEC-004: Read-only Git checks run before the short locked write transaction; immutable object IDs and content make their successful observation stable enough to validate the subsequent registration.
- BOOT-022-DEC-005: The specialized `publication.complete` command remains the only path from publication to the terminal state.
- BOOT-022-DEC-006: Store the selected transition as nullable `WorkflowAttempt#completed_transition_id`; successful completion sets it atomically, while non-successful and pre-existing attempts may leave it absent without changing CLI v1 resources.

## Acceptance Criteria

- BOOT-022-AC-001: Valid implementation-planning, development, approved-review, and changes-requested-review manifests register exactly their supplied artifacts and advance to the declared state.
- BOOT-022-AC-002: Missing, extra, wrongly stated, or wrongly cardinalized artifacts fail without persisted artifacts, terminal attempt state, or task transition.
- BOOT-022-AC-003: Candidate tests and reviews cannot use an old or inconsistent candidate, and a review cannot approve its own candidate-producing attempt.
- BOOT-022-AC-004: Invalid Git document, commit, digest, or task-trailer evidence fails safely.
- BOOT-022-AC-005: Stale lock, expired lease, stale fencing, context mismatch, undeclared transition, and generic publication completion retain stable version 1 failures without partial state.
- BOOT-022-AC-006: Idempotent replay returns the original task and artifacts after lease release, and two competing completions cannot both succeed.
- BOOT-022-AC-007: Focused checks, the full project check, RuboCop, and diff validation pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-022 active externally.
2. Add backward-compatible completed-transition persistence and database guards for newly succeeded attempts.
3. Implement shared transition, artifact, candidate-generation, review-independence, and read-only Git evidence validation.
4. Implement the atomic successful step-completion operation using existing ownership and idempotency infrastructure.
5. Add Rails routing and controller transport plus the Ruby CLI command binding.
6. Add service, request, CLI, contract, rollback, idempotency, and synchronized multi-process concurrency coverage.
7. Run focused checks, the full project quality gate, RuboCop, and diff validation.
8. Review the completed diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused completion service, API request, CLI transport, contract, Git-adapter, and concurrency specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused completion, API, CLI, protocol, idempotency, Git-evidence, migration/rollback, and synchronized process-concurrency suites passed without failures during implementation.
- `mise run check`: passed with 376 examples, 0 failures, 115 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review findings covering cardinality, manifest outcome, task paths, Git object identity and replacement/lazy-fetch behavior, durable decisions, publication specialization, migration trigger preservation, and completion preconditions were corrected and regression-tested.

## Implementation Result

- Added atomic `WorkflowSteps::Complete` validation and persistence for pinned transitions, current-manifest artifact contracts, candidate generations, independent reviews, attempt success, lease release, and task advancement.
- Added safe read-only Git verification for task-scoped document blobs, content digests, exact commit objects, and unique task trailers while disabling replacement refs, global/system configuration, and lazy fetch.
- Added durable completed-transition provenance with database guards and migration/rollback coverage that preserves all existing workflow-attempt triggers.
- Added authenticated REST and Ruby CLI bindings for the existing draft v1 `step.complete` command, including idempotent preparation outside the write transaction and exact response replay.
- Added service, request, CLI, contract, rollback, failure-atomicity, historical-candidate, and separate-process race coverage.

## Risks

- BOOT-022-RISK-001: Git evidence checks must not hold a SQLite write lock while invoking a process.
- BOOT-022-RISK-002: Historical candidate artifacts must not accidentally satisfy a later candidate generation.
- BOOT-022-RISK-003: Concurrent completion must preserve both task ownership and artifact atomicity under SQLite process contention.

The acceptance risks are covered by automated tests. A remaining adapter-hardening risk is that local Git subprocesses have no explicit wall-clock timeout and document blob verification reads the complete blob into memory; protocol-level artifact size limits are not currently specified, so imposing one was left out of this task.
