---
title: Idempotent Task Creation
task: BOOT-013
created: 2026-09-11
---

# BOOT-013: Idempotent Task Creation

## Goal

Implement repository-scoped, idempotent `quick-fix` task creation that allocates an immutable public number and pins the active immutable workflow version and its initial state atomically.

## User Outcome

An agent can use `bin/kos task create` to create a task once despite retries, receive its repository-specific public number, and know that later workflow activation cannot change the task's selected workflow.

## Context

Repositories, task types, published workflow versions, tasks, idempotency records, the read-only REST API, CLI transport, and protocol schemas already exist. The task-create operation, repository-scoped idempotency execution, REST endpoint, CLI binding, and concurrent allocation coverage are not implemented.

## Requirements

- BOOT-013-REQ-001: Accept only a nonblank title and the `quick-fix` task type through the version 1 `task.create` command; clients cannot select a workflow version or initial state.
- BOOT-013-REQ-002: Allocate the repository's next sequence and derive the immutable `<PREFIX>-NNNNNN` public number without reuse, widening, or wrapping.
- BOOT-013-REQ-003: Resolve the task type's current published workflow version and its initial state and create the task in the same transaction as sequence allocation.
- BOOT-013-REQ-004: Keep a created task pinned to that workflow version when another version is activated later.
- BOOT-013-REQ-005: Scope idempotency records and request fingerprints by command and repository UUID; replay the original task and HTTP 201 without allocating another sequence.
- BOOT-013-REQ-006: Permit the same idempotency key in another repository or command and reject reuse with another body as `idempotency_conflict`.
- BOOT-013-REQ-007: Reject repository path/body mismatch and whitespace-only titles as `malformed_input`.
- BOOT-013-REQ-008: Return nonretryable conflict errors `task_number_exhausted` after sequence 999999 and `task_type_unavailable` when no active published version can be selected, without changing state.
- BOOT-013-REQ-009: Serialize concurrent sequence allocation and workflow activation so every successful task has a unique number and a matching immutable version and initial state.
- BOOT-013-REQ-010: Expose the operation through the authenticated REST API and noninteractive JSON CLI with the existing bounded retry behavior and stable error envelopes.

## Scope

- A focused task-creation application operation and repository-scoped idempotency execution.
- REST routing and controller handling for `POST /api/v1/repositories/{repository_id}/tasks`.
- CLI parsing and transport binding for `kos task create`.
- Protocol error and title-validation schema updates, user documentation, and external development-plan updates.
- Service, request, CLI, contract, persistence, and multi-process SQLite concurrency tests.

## Non-Goals

- Attempt claim, lease, workflow-step completion, worktree, artifact, or publication mutations.
- Client-selected workflow versions or migration of existing tasks between versions.
- Parent-child relations, task dependencies, or task cancellation.
- Changes to public-number format or repository-prefix ownership.

## Related Specifications And ADRs

- [Task Model](../../docs/specs/task-model.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0001: Central REST API](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0006: Repository Task Prefixes](../../docs/decisions/0006-repository-task-prefixes.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-013-DEC-001: Task creation has no client lock precondition. Repository sequence allocation and workflow selection are serialized in the creation transaction; the returned task starts with lock version zero.
- BOOT-013-DEC-002: Sequence 1000000 is the persisted exhaustion sentinel. Creation at 999999 succeeds and advances to the sentinel; later creation returns `task_number_exhausted`.
- BOOT-013-DEC-003: Missing active workflow configuration returns `task_type_unavailable`, while exhausted numbering returns `task_number_exhausted`; both are conflict-category, HTTP 409, CLI exit 6, and nonretryable.
- BOOT-013-DEC-004: Whitespace-only titles are rejected by the protocol schema as malformed input rather than reaching model validation.

## Acceptance Criteria

- BOOT-013-AC-001: A valid API or CLI request returns a schema-valid task with HTTP 201, lock version zero, the next public number, and the active version's initial workflow status.
- BOOT-013-AC-002: Separate repositories allocate independently, while sequential and concurrent creations in one repository receive unique monotonically allocated sequences.
- BOOT-013-AC-003: Completed idempotency replay returns the same task and original status, consumes one sequence, and repository or command scope permits independent reuse.
- BOOT-013-AC-004: Conflicting idempotency input, failed creation, inactive task type, and sequence exhaustion do not create a task or consume a sequence.
- BOOT-013-AC-005: Activation after creation affects only later tasks, and concurrent activation cannot create a mismatched task version and initial state.
- BOOT-013-AC-006: Authentication, repository isolation, repository path/body equality, request shape, idempotency-key format, and stable errors are covered at the API boundary.
- BOOT-013-AC-007: CLI transport sends the repository-scoped POST request and reuses the original body and key for bounded transient retries.
- BOOT-013-AC-008: Focused checks, the full project check, and diff validation pass before the task is committed and pushed to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-013 active externally.
2. Implement atomic task allocation and workflow pinning with explicit domain failures.
3. Generalize idempotency execution for explicit global and repository scopes without changing catalog behavior.
4. Add the task-create REST route and action, repository path/body validation, error mapping, and CLI binding.
5. Update protocol schemas, specification, and user documentation for title validation and explicit edge errors.
6. Add service, request, CLI, contract, and synchronized multi-process SQLite concurrency coverage.
7. Run focused checks, the full project check, and diff validation; resolve all failures.
8. Complete the task and external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused task-creation, idempotency, request, CLI, contract, and persistence specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused task-creation, idempotency, request, CLI, contract, persistence, and synchronized subprocess concurrency suites passed throughout implementation.
- `mise run check`: passed with 319 examples, 0 failures, 96 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining findings after final-failure persistence, nested rollback, repository-scoped retry, and activation serialization corrections.

## Implementation Result

- Added atomic repository-local sequence allocation with immutable active workflow-version and initial-state pinning.
- Added repository-scoped idempotency fingerprints and records while preserving global catalog scope, including durable replay of successful and final failure results.
- Added the authenticated `task.create` REST endpoint and noninteractive JSON CLI binding with path/body scope validation.
- Added explicit `task_number_exhausted` and `task_type_unavailable` conflicts and rejected whitespace-only titles at the schema boundary.
- Added service, request, CLI, contract, rollback, replay, and synchronized multi-process SQLite concurrency coverage.
- Documented task creation in the user README.

## Risks

- BOOT-013-RISK-001: SQLite write contention can expose allocation or replay races that transactional model examples miss; synchronized separate-process integration coverage is required.
- BOOT-013-RISK-002: Workflow activation and task creation lock shared catalog state in different operations; consistent locking must prevent stale or mismatched version selection without widening transactions.
- BOOT-013-RISK-003: Completed failure replay uses a private `_operation_error` discriminator in persisted idempotency response data; future persistence changes must preserve that representation.
