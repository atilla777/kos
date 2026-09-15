---
title: Durable Approved Task Input
status: accepted
date: 2026-09-15
bootstrap_task: BOOT-044
---

# ADR-0010: Durable Approved Task Input

## Context

An isolated workflow executor receives only its finalized executable context. A task title does not contain the approved requirements, scope, non-goals, decisions, and acceptance criteria needed to plan a change, while the parent dialogue and repository bootstrap task records are outside KOS workflow state. Deriving missing requirements from either source would make execution non-reproducible and would bypass the approval boundary.

The CLI version 1 schemas have no implemented release and the first operational workflow is blocked by this missing input. Existing persisted tasks and frozen contexts can nevertheless exist in development state and must remain inspectable.

## Decision

Every newly created task stores one closed, versioned `task_input` containing its title and an approved Markdown brief. Markdown preserves the complete human-approved baseline without prematurely standardizing every product's requirement sections as protocol fields. The brief is nonblank, UTF-8, and bounded to 128 KiB.

Task input is created atomically with task identity and pinned workflow selection and is immutable at the database boundary. Task reads return it. Every newly finalized executable context includes the exact persisted input, so the existing canonical context digest binds the executor's input. A legacy task without approved input remains readable but cannot finalize another context. An already frozen legacy context remains valid and is never rewritten.

The CLI parser and Rails persistence boundary validate exact UTF-8 before storage. SQLite triggers additionally require text storage, supported schema version, bounded bytes, and non-whitespace content; SQLite does not independently validate the encoding of a value already bound as TEXT. This is acceptable only while Rails remains the sole persistence interface required by the architecture.

Correct the pre-release CLI version 1 task and context documents in place. This is a draft-contract correction, not a compatibility precedent after an implemented release.

## Consequences

- Planning can operate from authoritative KOS state without dialogue or filesystem access.
- Idempotency fingerprints bind task creation to the complete approved brief.
- New tasks cannot be created through persistence code without approved input.
- Existing tasks are not assigned invented approval data; they fail closed only when new execution input is requested.
- Changing or replacing approved input requires a future explicit task-revision design rather than an ordinary update.
- Local clients must adopt the corrected draft request before creating another task.

## Rejected Alternatives

### Store only structured requirement fields

This would make the first transport more queryable but would prematurely impose one product-document structure and risk omitting approved context that the planner needs.

### Read a repository task record or parent dialogue

Those sources are unavailable to the isolated executor, are not attempt-bound KOS state, and cannot provide the same immutable replay guarantee.

### Backfill legacy tasks from their titles

A title is not an approved brief. Treating it as one would fabricate requirements and defeat the fail-closed boundary.

### Introduce CLI and API version 2 now

Maintaining complete parallel namespaces before version 1 has an implemented release would substantially broaden this prerequisite without preserving a released consumer contract.
