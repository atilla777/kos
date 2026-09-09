---
title: KOS Task Model
status: active
---

# KOS Task Model

## Task Types

A `TaskType` defines a task's purpose and has exactly one associated workflow schema. A schema may contain an explicit branch, such as a post-grooming decomposition decision. Lifecycles with different purposes use different task types rather than implicit alternatives in one schema.

The initial types are:

- `quick-fix`, a short fix or small change without grooming, required by the operational MVP;
- `feature`, a product change that may continue as one task or be decomposed, deferred until after that MVP; and
- `initiative`, known complex work with child tasks, deferred until after that MVP.

## Tasks

A `Task` is one unit of managed work. It records at least:

- an internal identifier and title;
- an immutable repository-specific public number;
- its task type;
- status and workflow status;
- an optional parent and task relations or dependencies;
- a lock version for optimistic locking;
- workflow identity, version, and pinned bundle digest; and
- allocated worktree and branch details when its workflow changes repository files.

In the MVP, `status` is not independently mutable. It is derived from terminal workflow status and active-attempt state as `open`, `active`, `blocked`, `completed`, or `cancelled`; workflow status remains the sole lifecycle source.

## Public Numbers And Traceability

Every registered repository has an immutable task prefix of 2 through 10 uppercase ASCII letters or digits beginning with a letter. The prefix is globally unique within one KOS installation. Every task combines that prefix with a six-digit numeric sequence to receive an immutable public number such as `KOS-000123`. The SQLite primary key is internal. The numeric sequence is allocated within the task-creation write transaction, protected by a repository-scoped uniqueness constraint, and never reused within that repository. Creation fails explicitly after sequence `999999`; it does not widen or wrap the public number. Public numbers are used by the CLI, branch names, task-artifact paths, Git trailers, and human or agent references. Child tasks have their own numbers; relations, not composite numbers, define hierarchy.

Task creation requires an idempotency key, so retrying after a lost response returns the original task.

Task-local Markdown artifacts use stable IDs derived from the public number for homogeneous sections:

```text
KOS-000123-REQ-001
KOS-000123-DEC-001
KOS-000123-Q-001
KOS-000123-RISK-001
KOS-000123-AC-001
```

An ID is neither changed nor reused when its document is edited. A resolved question references the requirement or decision that resolved it. A decision records the accepted choice, rationale, consequences, and rejected alternatives; rejected alternatives do not each need an ID.

These IDs are task-local. Long-lived domain documentation uses independent stable IDs such as `ORD-BEH-003`, and a long-lived architecture decision receives its own ADR number in `docs/decisions/`. An ADR originating from a KOS task includes `kos_task: KOS-000123` in frontmatter and is registered as an `architecture_decision` artifact.

[ADR-0006](../decisions/0006-repository-task-prefixes.md) records why public task numbers use a globally unique repository prefix.

Code may reference a task decision, domain specification, or ADR only where a non-trivial decision needs durable rationale. A short `@see` comment is preferred; KOS does not require such comments in every changed file or function.

## Relations And Dependencies

Parent-child relations and separate dependencies must be acyclic. A relation's type explicitly determines whether it blocks execution or publication. Relation creation and cycle validation occur in one write transaction.

A blocking dependency must be in a successful terminal status before the dependent task can claim its next step. A parent in `coordinating` completes only when every required child is in a successful terminal status; required children cannot be added after that completion.

Hierarchy and dependency execution are deferred beyond the quick-fix MVP, but implementations that add them must preserve this contract.
