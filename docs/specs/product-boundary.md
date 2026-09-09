---
title: KOS Product Boundary
status: active
---

# KOS Product Boundary

## Purpose

KOS is a local workflow system for software development with AI agents. It gives multiple agents one safe, reproducible way to manage tasks, execute workflows, and publish changes to Git repositories.

KOS consists of:

- a Ruby on Rails application with SQLite state for shared workflow definitions, tasks, workflow attempts, workflow statuses, and artifact metadata;
- a Ruby CLI as the only agent-facing programmatic interface to KOS state;
- a canonical set of Agent Skills shipped with KOS; and
- centrally managed, versioned workflow instructions and artifact templates shared by target projects.

The agent is the primary system operator. A human defines goals, makes decisions that require judgment, and controls the result.

## Product Goals

KOS must:

- manage task types, tasks, task hierarchy, and dependencies;
- associate each task type with one workflow schema;
- author, validate, publish, activate, and export shared workflow versions through KOS;
- coordinate multiple agents without conflicting execution;
- recover from interrupted agents, lost CLI responses, and ambiguous Git outcomes without duplicate publication;
- isolate repository-changing workflows in dedicated Git worktrees;
- read and mutate KOS state only through the Ruby CLI;
- validate workflow transitions against a pinned schema and artifact state;
- give every task an immutable public number shared by documents, Git, and artifacts;
- support requirements documentation in OKF-compatible Markdown;
- allow workflows, step instructions, and templates to evolve without KOS code changes; and
- ship skills and templates for adopting KOS in other projects.

The detailed contracts are defined by the other [domain specifications](index.md). [ADR-0001](../decisions/0001-central-rest-api.md) defines central state and the CLI/API boundary.

## Version Boundary

The first version includes tasks, workflow statuses, artifact validation, worktree isolation, skills, documentation, and direct publication of verified changes to the configured base branch.

The first operational MVP is deliberately narrower: one repository, the shared `quick-fix` task type, one supported runtime target, and the workflow `implementation-planning -> development -> review -> publication -> completed`. Lease and fencing, idempotency, immutable workflow-version pinning, worktree reservation, recoverable publication, and opt-in retrospective post-processing are required before adding broader task types or runtime support.

The operational MVP is ready when an agent using KOS skills can:

1. Initialize one Git repository, pin its trusted remote and base ref, and install skills for one supported runtime target.
2. Read shared task types and published workflow versions from KOS.
3. Create a publicly numbered task pinned to an immutable workflow version.
4. Allocate its dedicated worktree through `kos-repository`.
5. Execute the complete `quick-fix` workflow through the orchestrator and shared subagent executor.
6. Record and validate a candidate SHA, test result, and independent review result as one artifact generation.
7. Change workflow status only for a valid transition with the required candidate and artifacts.
8. Publish the reviewed commit safely to the configured base ref without force-push.
9. Relate task artifacts and Git commits to the task's public number.
10. Prevent concurrent execution of one workflow step and reject completion with a stale fencing token.
11. Recover from a crash or lost response during any worktree-reservation or publication phase without duplicate publication or loss of observed remote state.
12. Return the same result when any mutation is repeated with the same idempotency key.
13. Continue a task in a new session using only its pinned workflow version, durable context, and registered artifacts.
14. When enabled for the installation, run a private best-effort retrospective after each graceful KOS agent session and report sanitized improvement proposals without changing the source task.

## Deferred Capabilities

The following capabilities are not commitments for the quick-fix MVP. `feature`, `initiative`, hierarchy, and a second runtime target are subsequent increments and must preserve all MVP guarantees when added.

The following remain outside the first version until a demonstrated need and separate decision exist:

- a web interface, dashboard, or complex visualization;
- users, roles, audit, a knowledge base, taxonomy, or full-text search;
- replaceable storage backends;
- arbitrary Ruby code in workflow schemas;
- repository-specific workflow overrides, a universal artifact registry, overlays, or an Owl-level update mechanism;
- a separate runtime skill for every possible workflow step;
- force-push or automatic rewriting of base-branch history.

New functionality is added only for a concrete need and by a separate decision.

## Documentation Contract

Observable domain behavior belongs in focused files under `docs/specs/`; engineering constraints belong in `docs/rules/`; and long-lived architecture rationale belongs in `docs/decisions/`. Domain specifications describe scenarios, rules, states, validation, errors, and material integration contracts, not private methods or class layout. A difference between an active domain specification and code is a defect.

Conceptual documents use OKF-compatible YAML frontmatter. A target project's compact `AGENTS.md` directs agents to its rules, specifications, and skills, while its `README.md` explains purpose, installation, setup, initialization, and agent use. Detailed documents remain separate so an agent can load only relevant context.
