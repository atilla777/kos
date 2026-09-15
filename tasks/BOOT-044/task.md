---
title: Durable Approved Task Input
task: BOOT-044
created: 2026-09-15
status: completed
---

# BOOT-044: Durable Approved Task Input

## Goal

Persist an approved task brief when a quick-fix task is created and transport that authoritative input unchanged in every newly finalized executable context.

## User Outcome

A planning executor receives enough approved task input from its immutable KOS context to create an implementation plan without reading the parent dialogue or a repository task record.

## Context

The active `quick-fix@1.0.0` planning instruction requires an approved task record, but version 1 `task.create` stores only a title and `step.context` transports neither the title nor requirements. The isolated executor cannot read KOS state or its parent dialogue. BOOT-041 is blocked until this prerequisite closes that input boundary.

The CLI version 1 schemas remain a pre-release draft: this bootstrap repository has no release tag and the operational quick-fix workflow is not usable. Correcting the draft in place is smaller and safer than introducing a complete second API namespace before the first operational release.

## Requirements

- BOOT-044-REQ-001: A new quick-fix task requires one versioned `task_input` containing its nonblank title and a nonblank approved Markdown brief of at most 128 KiB.
- BOOT-044-REQ-002: Task creation stores the title, task-input schema version, and exact approved brief atomically with task number allocation and pinned workflow selection.
- BOOT-044-REQ-003: The approved task input is immutable at the database boundary after creation.
- BOOT-044-REQ-004: `task.create` and `task.get` return the persisted task input; an existing task created before this contract remains readable without it.
- BOOT-044-REQ-005: Every newly finalized executable context requires and contains the exact persisted task input, covered by the existing canonical `input_context_digest`.
- BOOT-044-REQ-006: A legacy task without approved input returns `context_unavailable` before context persistence rather than deriving requirements from its title or another source.
- BOOT-044-REQ-007: An already frozen legacy context remains replayable and valid; KOS does not rewrite immutable attempt input.
- BOOT-044-REQ-008: Task creation remains repository-scoped and idempotent; replay returns the original input and key reuse with another brief remains an idempotency conflict.
- BOOT-044-REQ-009: Correct the pre-release CLI v1 schemas and documented contracts in place while preserving all unrelated command semantics.

## Scope

- Task persistence migration, model validation, creation, serialization, and database constraints.
- Version 1 task-create, task-resource, and executable-context schemas.
- Context assembly and frozen legacy-context validation.
- Behavioral specifications, an architecture decision, CLI user documentation, and canonical runtime skill guidance.
- Model, migration, service, request, CLI, contract, idempotency, and context coverage.

## Non-Goals

- Publishing or activating the corrected quick-fix workflow version from BOOT-041.
- Implementing the planning and development artifact flow from BOOT-043.
- Editing an approved brief after task creation.
- Importing task input from dialogue or repository task records.
- Introducing a complete CLI and REST API version 2.
- Backfilling invented requirements for existing tasks.

## Related Specifications And ADRs

- [Task Model](../../docs/specs/task-model.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [ADR-0001: Central REST API](../../docs/decisions/0001-central-rest-api.md)

## Task-Local Decisions

- BOOT-044-DEC-001: Represent approved requirements as bounded Markdown inside a closed versioned `task_input` object rather than prematurely standardizing every requirement section as separate protocol fields.
- BOOT-044-DEC-002: Correct version 1 in place because it has no implemented release and its first operational workflow is currently blocked by the missing field.
- BOOT-044-DEC-003: Keep legacy tasks readable with omitted task input, but fail closed when they try to finalize a new context.
- BOOT-044-DEC-004: Preserve already frozen legacy contexts as immutable historical input through an explicit legacy context schema branch.
- BOOT-044-DEC-005: Isolate implementation in a separate worktree because BOOT-041 has an unrelated uncommitted diff in the primary worktree.

## Acceptance Criteria

- BOOT-044-AC-001: New task creation rejects absent, blank, oversized, malformed, or unsupported-version task input without allocating a task number.
- BOOT-044-AC-002: Successful creation persists and returns the exact versioned input in the same transaction as the pinned workflow and monotonic number.
- BOOT-044-AC-003: Database constraints prevent new tasks without approved input and prevent later changes to the approved title, brief, or input version.
- BOOT-044-AC-004: Same-key replay returns the original task and a changed brief under the same key returns `idempotency_conflict`.
- BOOT-044-AC-005: A new finalized context contains the exact task input, and its independently calculated digest covers that input.
- BOOT-044-AC-006: Legacy tasks remain readable, cannot finalize new context without approved input, and already frozen legacy contexts remain valid.
- BOOT-044-AC-007: Focused checks, `mise run check`, `git diff --check`, and independent review pass before a normal push to `main`.

## Implementation Plan

1. Record the approved baseline externally and in this task record while preserving the blocked BOOT-041 diff.
2. Specify the approved task-input persistence and transport contract and record the cross-boundary decision in an ADR.
3. Add a forward migration and model/application enforcement for versioned, bounded, immutable task input while retaining readable legacy rows.
4. Carry task input through task creation, resources, and newly finalized executable contexts.
5. Correct the pre-release v1 schemas, CLI examples, runtime guidance, and contract fixtures.
6. Add focused persistence, API, CLI, idempotency, context, legacy-state, and concurrency coverage.
7. Run focused checks, the complete project quality gate, and diff validation.
8. Perform independent review, record verification, update the external plan, commit only BOOT-044 files, and publish normally to `main`.

## Verification

- Run focused model, migration, task creation, task request, CLI, schema contract, idempotency, and context specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-15:

- Focused persistence, migration, task creation, API, CLI, schema, context, idempotency, legacy-state, and concurrency coverage passed with 203 examples and 0 failures before final hardening.
- Final `mise run check` passed with 736 examples and 0 failures, 191 RuboCop-inspected files with no offenses, no Brakeman warnings, no vulnerable dependencies, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent review found malformed-encoding, database whitespace, and pre-idempotency size-validation gaps. All findings were fixed and covered; final re-review found no publication-blocking defects.

## Implementation Result

- Added immutable version 1 approved task input to new quick-fix task creation and task reads.
- Added migration-safe SQLite guards while preserving readable legacy rows and every existing task trigger through rollback.
- Added exact approved task input to newly finalized contexts under the existing canonical digest; legacy tasks fail closed and frozen legacy contexts remain valid.
- Corrected the pre-release CLI v1 schemas, CLI local validation, runtime guidance, specifications, and installation release digest.
- Recorded the durable boundary and compatibility decision in ADR-0010.

## Risks

- BOOT-044-RISK-001: Correcting the draft v1 command requires local clients to provide task input before creating another task.
- BOOT-044-RISK-002: Existing rows cannot be assigned an approved brief without inventing approval; compatibility must remain readable but fail closed for new execution.
- BOOT-044-RISK-003: Changing a closed context schema can invalidate frozen historical input unless the legacy shape remains explicitly valid.
- BOOT-044-RISK-004: BOOT-041 has uncommitted changes based on the same Git commit and may require careful integration after BOOT-044 is published.

SQLite does not independently validate malformed bytes already injected as TEXT. The supported JSON, CLI, and Rails-only persistence paths validate exact UTF-8 before storage, and the database rejects non-TEXT storage; direct SQLite injection remains outside the architecture boundary. Migration rollback coverage verifies restoration of every task trigger by name but not every restored trigger behavior in that one test, while the full persistence suite covers those behaviors separately. Frozen legacy context compatibility is covered at schema and service level rather than with a pre-migration database fixture containing a finalized context.
