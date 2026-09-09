---
title: KOS Workflow Execution
status: active
---

# KOS Workflow Execution

## Workflow Definitions

A project-controlled workflow definition in `.kos/` defines the workflow-status graph for one task type. Executable statuses are distinct from the one terminal status. Each executable status declares:

- a stable identifier;
- a Markdown instruction and execution mode of main session or subagent;
- allowed outgoing transitions;
- required output artifacts with type, cardinality, subject, and allowed states;
- transition completion conditions; and
- whether a worktree is required and what changes are allowed.

Workflow status is not free text. The CLI accepts only a transition declared by the task's pinned schema and allowed from its current status. It validates the required artifact contract before performing an atomic transition; it neither executes skill work nor judges its substantive quality.

The workflow language is a small typed schema without arbitrary expressions or Ruby code. An edge is declared once. Conditions are limited to `always`, `artifact-present`, `artifact-state`, `decision`, and `not-applicable`. `artifact-present` requires the source requirement's cardinality in any allowed state; `artifact-state` requires that cardinality in the named allowed state. `not-applicable` names the source `artifact_type` whose requirement is explicitly waived on that branch. An edge has at most one artifact condition per `artifact_type`, so evidence and `not-applicable` cannot contradict each other. A generic `decision` contains stable `decision` and `value` identifiers and records the branch selected by taking that edge; it is not artifact evidence and does not waive artifact requirements. One edge cannot assign multiple values to the same decision. Any durable evidence required for the choice is declared by an additional artifact condition. Multiple conditions on one transition are conjunctive. Every source artifact requirement must be evidenced or explicitly waived on each outgoing edge, and all of its allowed states must be covered by evidence across the outgoing routes. An `always` condition is the transition's sole condition and is valid only when the source has no required artifact output. Two outgoing decision branches from the same source cannot use the same `(decision, value)`. Configuration validation rejects unknown conditions, unreachable statuses, duplicate edges, ambiguous decision branches, output conditions inconsistent with their artifact requirements, and references outside the bundle. The exact document shapes are defined by the versioned schemas identified in [Project Configuration](project-configuration.md).

## Attempts And Ownership

A `WorkflowAttempt` represents one execution of the current workflow status. It records an attempt ID, task and status, owner ID, idempotency key, monotonic fencing token, state (`started`, `succeeded`, `failed`, `interrupted`, or `needs_human`), start, heartbeat, and completion times, the immutable executable context and input-context digest after context finalization, and the result manifest after submission.

Before mutating repository files or attempt-owned KOS state, an orchestrator atomically claims a lease for the task, workflow status, and expected lock version through the CLI. The lease has a bounded lifetime, can be renewed by its owner, and is released when the attempt completes, enters `needs_human`, or expires. After expiry, a new orchestrator reconciles the unfinished attempt before creating another. Every mutation owned by an active attempt and every `kos-repository` operation carries the current fencing token; task creation, attempt claim, and expired-attempt reconciliation do not. An attempt with a stale token cannot complete the step. Exact command preconditions are defined by [CLI Protocol Version 1](cli-protocol.md).

Attempt failure does not change workflow status. KOS records durable intent before an external operation and, after interruption, reconciles observed state instead of blindly repeating the operation. [ADR-0002](../decisions/0002-recoverable-workflow-attempts.md) records this recovery decision.

Every mutating CLI command requires an idempotency key. Repeating the same command and key returns the recorded result instead of creating another entity or side effect. Wire representation and command-specific requirements are defined by [CLI Protocol Version 1](cli-protocol.md).

## Execution

The main-session `kos-orchestrate` skill obtains task state and the complete executable step context through the CLI and follows the pinned workflow. It runs statuses that require direct human interaction itself and invokes the common `kos-workflow-step` executor for every subagent status. Main-session and subagent statuses use the same context retrieval contract.

After claim and confirmation of any required worktree, the orchestrator finalizes an attempt-bound versioned context envelope with the idempotent `kos step context` mutation. KOS stores that immutable input before returning it. The context contains task and attempt identities, workflow status, bundle digest, exact pinned Markdown instruction, referenced materials and their digests, expected lock version, fencing token, repository identity, worktree, base ref, candidate SHA, required artifacts, and an allowed capability list. The executor follows the inline instruction and invokes only allowed capability skills. Neither orchestrator nor executor reads KOS snapshot storage directly. A new step kind is introduced by a project instruction, not a new runtime skill.

A main-session status such as `grooming` persists questions, decisions, the selected branch, and open items as a durable artifact. Waiting for a human changes the attempt to `needs_human` and releases its lease.

A subagent:

- works only in the allocated task worktree when the step changes repository files;
- does not mutate KOS state through SQLite, the CLI, or the API, and does not perform mutating Git operations;
- returns a versioned result manifest with attempt ID, input-context digest, produced artifacts, and `succeeded`, `failed`, or `needs_human` outcome.

Only the lease-owning orchestrator submits the manifest. The CLI verifies the manifest against the stored input-context digest, then registers artifacts and changes workflow status with the expected lock version in one transaction, as specified by [Artifact Contracts](artifact-contracts.md).

## Initial And Deferred Workflows

The contract fixture for the operational `quick-fix` workflow has executable `implementation-planning`, `development`, `review`, and `publication` statuses followed by terminal `completed`. All executable statuses use a subagent and require a worktree. Planning and development allow repository changes; review and publication forbid them. Planning has no capability, while development, review, and publication allow only `kos-development`, `kos-review`, and `kos-publish`, respectively; `kos-repository` is never a workflow capability.

Planning produces one task-scoped implementation-plan document in `produced` state and advances to development only with that artifact. Development advances to review only with one produced task candidate and one or more passed candidate test artifacts. Review records one candidate review and uses `artifact-state` to route `changes_requested` back to development or `approved` to publication. Publication reaches `completed` only with one published artifact for that candidate. The orchestrator may attach validated repository-adapter artifact evidence after a requested commit effect as defined by the CLI protocol; no human approval is added. `completed` has no instruction or attempt.

When later introduced, `feature` begins with `grooming`. An explicit decision either continues one task through `domain-specification`, optional `architecture-decision`, `implementation-planning`, `development`, `review`, and `publication`, or follows `decomposition-and-specification`, `specification-review`, `specification-publication`, `coordinating`, and `completed`. `initiative` follows `grooming`, `requirements`, `decomposition-and-specification`, `specification-review`, `specification-publication`, `coordinating`, and `completed`.

`domain-specification` is required for observable domain behavior changes and is explicitly `not-applicable` for a pure refactor or fix without behavior change. `architecture-decision` is required when a decision is long-lived or crosses tasks, domains, architecture, external contracts, data models, or substantial mechanisms; the selected branch requires its registered ADR artifact before `implementation-planning`, while local decisions remain task-local. `development` includes implementation, tests, linters, and local checks. Required specification changes and a candidate commit must exist before review.

`implementation-planning` creates `tasks/<task-number>/implementation-plan.md`, referencing affected domain specifications and any ADR required by the selected workflow branch, and describing current and target state, technical design, affected components and contracts, implementation sequence, test strategy, and risks. It uses task-local traceability IDs for sections that are present. Behavioral contracts stay in `docs/specs/`; the implementation plan contains technical decisions and work steps, not a duplicate low-level specification.

Decomposition creates `tasks/<parent-task-number>/specification.md` with the shared goal, boundaries, key decisions, and child-task map. Child tasks link to it and retain only their narrow requirements and plans.

## Retrospective

Retrospective support is deferred beyond the quick-fix MVP. After that increment is introduced, each subagent runs `kos-retrospective` on its own dialogue before finishing, and the main agent runs it after terminal workflow status only for the main-session dialogue and orchestration quality. The orchestrator does not inspect private subagent dialogues.

A retrospective evaluates dialogue for unclear context, faulty decomposition or delegation, repeated errors, unnecessary work, and missing rules or instructions. It either takes no action or proposes a separate follow-up task, which the owning orchestrator creates through the CLI with an idempotency key. It never changes a completed task or makes hidden post-publication edits. It is best-effort post-processing with its own idempotent attempt, and failure does not reverse terminal workflow status.
