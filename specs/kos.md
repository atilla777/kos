---
type: Product Specification
title: KOS task coordination
description: User-visible behavior of KOS task coordination and its three built-in scenarios.
tags:
  - kos
  - workflows
---

# Goal

KOS gives AI agents durable task state and exclusive temporary ownership while
leaving requirements, implementation, verification, review, and publication to
the appropriate agents and repository tools.

# Actors

- A user asks for product clarification, planned development, or a defect fix.
- An orchestrator owns one task and advances its stored workflow.
- Isolated step agents plan, implement, document, review, or publish within
  their granted authority.
- An administrator installs KOS and registers participating projects.

# User Scenarios

- `/kos-brief <request>` clarifies product behavior, publishes its reviewed
  specification, and creates the resulting development work.
- `/kos` selects the next available development task, plans and implements it,
  documents changed behavior, obtains independent review, and publishes it.
- `/kos-fix <problem>` diagnoses an observed problem before following the same
  checked, documented, reviewed, and published delivery path.

# Rules

- Users choose an intent through a command; they do not manage internal task
  type IDs, workflow IDs, claims, leases, or worktree paths.
- A task remains bound to the workflow revision selected when it was created.
- Only one valid owner may advance a task at a time, and stale owners cannot
  report results.
- Incomplete blockers make dependent tasks unavailable.
- Product behavior changes update this `specs/` bundle before independent
  review. Technical-only work records why no product concept changed.
- Work remains uncommitted through implementation and review. Publication is
  the only stage that may commit and push.
- A task completes only after publication and its remote result are observed.

# Errors

- A material product ambiguity pauses at the current step with one precise
  question for the user.
- A technical obstruction pauses at the current step with the observed cause.
- Invalid transitions, stale claims, unavailable tasks, and contradictory
  child-task graphs fail explicitly without partial state changes.

# Edge Cases

- After an interrupted request, the orchestrator observes durable task, file,
  Git, and remote state before retrying an operation.
- If the default branch moves before publication, implementation checks,
  documentation, and independent review repeat on the new base.
- Brief-created child tasks stay unavailable until their published parent brief
  is complete, and the complete child graph is materialized atomically.

# Acceptance Criteria

- A clean installation provides the brief, development, and fix scenarios
  without hand-authored workflow JSON or numeric task type configuration.
- Required checks, independent review, one verified publication commit, final
  task completion, ownership release, and durable Markdown artifacts are
  observable for completed work.
- Restart and lost-response recovery do not duplicate tasks, transitions,
  child graphs, commits, or pushes.

# Non-goals

KOS is not a general workflow engine, an autonomous requirements authority, a
code-review judge, a Git hosting service, or a storage system for product
specifications and execution artifacts.

# Technical References

Implementation boundaries are defined in
[Architecture Rules](../docs/architecture.md). Verification layers and commands
are defined in [Testing Rules](../docs/testing.md). These technical contracts
are linked rather than duplicated here.
