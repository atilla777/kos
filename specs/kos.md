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
  type IDs, workflow IDs, project IDs, claims, leases, or worktree paths.
- A command identifies its project from the invoking checkout's `origin` as a
  canonical `host/namespace/repository` name such as
  `github.com/atilla777/kos`. Users do not configure `KOS_PROJECT_*`
  environment variables.
- Project registration binds that canonical repository name to the project's
  display name, Git remote, default branch, and internal database identity.
  Database preparation installs the built-in catalog but does not silently
  register a repository.
- One shared CLI procedure owns CLI discovery, compatibility checks, safe
  invocation, response validation, and observation before retrying an
  ambiguous request. Orchestrators use that procedure instead of duplicating
  the transport protocol.
- An orchestrator owns task selection, durable command intent, ownership,
  workflow routing, human-answer preservation, and artifact verification. It
  does not restate how an individual workflow step performs development,
  checks, review, or publication.
- Before each step attempt, the orchestrator removes only a safe regular current
  step artifact. The step produces a new artifact at that path, and the
  orchestrator validates its bytes and the agent's exact outcome response before
  advancing task state. Artifact acceptance never depends on filesystem
  identity.
- A generic step procedure owns only the one-step execution boundary, supplied
  context validation, artifact persistence, and exact outcome response.
  Instructions specific to planning, diagnosis, implementation and checks,
  documentation, review, publication, or Git live with the corresponding step
  authority rather than in the generic procedure.
- The Git procedure owns repository and worktree verification, base movement,
  commit creation, push, and publication recovery. It does not own workflow
  routing, project checks, review decisions, or KOS task state.
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
- A missing project registration reports the canonical repository name and the
  administrative registration action; it never substitutes another project or
  guesses an internal ID.
- Project discovery stops before task or local recovery-state mutation when
  `origin` is absent, its fetch and push destinations identify different
  repositories, its canonical name is invalid, or lookup is ambiguous.
- A symbolic link, directory, or other unexpected object at the current step
  artifact path is a technical blocker and is not removed. A failed agent,
  invalid response, or missing or invalid new artifact leaves the task on the
  current step and does not report an attempt.

# Edge Cases

- After an interrupted request, the orchestrator observes durable task, file,
  Git, and remote state before retrying an operation.
- SSH and HTTPS remotes that unambiguously name the same host, namespace, and
  repository resolve to the same canonical project name. A fork with a
  different namespace is a different project.
- Renaming or transferring a repository requires the administrator to update
  the existing project registration so its internal identity, tasks, durable
  intents, artifacts, and worktree paths remain attached to the same project.
- If the default branch moves before publication, implementation checks,
  documentation, and independent review repeat on the new base.
- Brief-created child tasks stay unavailable until their published parent brief
  is complete, and the complete child graph is materialized atomically.
- Retrying a step removes an unconfirmed regular artifact from the previous
  attempt before running one new step agent. A lost or invalid agent response
  never permits the orchestrator to infer an outcome from artifact content.

# Acceptance Criteria

- A clean installation provides the brief, development, and fix scenarios
  without hand-authored workflow JSON or numeric task type configuration.
- After one explicit project registration, all three commands discover the
  project from the invoking checkout without `KOS_PROJECT_ID`,
  `KOS_PROJECT_REMOTE_URL`, or `KOS_PROJECT_DEFAULT_BRANCH`.
- Installation documentation distinguishes database preparation from project
  registration, shows how to detect and register a missing project, and
  verifies automatic discovery before declaring the installation ready.
- CLI transport rules and each workflow authority have one canonical skill or
  agent instruction source; shared procedures contain only genuine cross-step
  invariants and do not duplicate step-specific execution policy.
- Required checks, independent review, one verified publication commit, final
  task completion, ownership release, and durable Markdown artifacts are
  observable for completed work.
- Restart and lost-response recovery do not duplicate tasks, transitions,
  child graphs, commits, or pushes.
- A valid step artifact may be written directly by the agent with ordinary file
  tools. Acceptance requires a new nonempty UTF-8 regular file that matches the
  current template and returned outcome, not a changed inode, temporary file,
  rename, fsync, marker, or attempt identifier.

# Non-goals

KOS is not a general workflow engine, an autonomous requirements authority, a
code-review judge, a Git hosting service, or a storage system for product
specifications and execution artifacts.

# Technical References

Implementation boundaries are defined in
[Architecture Rules](../docs/architecture.md). Verification layers and commands
are defined in [Testing Rules](../docs/testing.md). These technical contracts
are linked rather than duplicated here.
