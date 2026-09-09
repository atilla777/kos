---
title: Central Workflow Catalog And Runtime Contract Rebaseline
task: BOOT-018
created: 2026-09-09
---

# BOOT-018: Central Workflow Catalog And Runtime Contract Rebaseline

## Goal

Replace the unimplemented project-owned workflow snapshot architecture with a central KOS-owned workflow catalog and define the agreed generic workflow executor and retrospective lifecycle before persistence work begins.

## User Outcome

KOS owns shared task types, workflow drafts, immutable published workflow versions, step instructions, and artifact templates in SQLite. Projects retain source code and artifact payloads, while every workflow step is executed by one generic skill and an installation-wide optional retrospective can propose separate improvements without changing completed work.

## Context

The active specifications and draft machine contracts currently make `.kos/` files in each target repository authoritative and copy them into a filesystem snapshot store. KOS has no persistence models, API, CLI, snapshot adapter, or runtime skills yet, so the architecture can be corrected without data migration or protocol-version compatibility work. The next planned persistence task, BOOT-010, must not implement the superseded snapshot model.

## Requirements

- BOOT-018-REQ-001: Make central Rails-owned SQLite the canonical store for shared task types, mutable workflow drafts, immutable published workflow versions, instructions, templates, task workflow state, and artifact metadata.
- BOOT-018-REQ-002: Keep artifact payloads such as task documents and Git evidence in target repositories while retaining the metadata required for atomic transition validation in KOS.
- BOOT-018-REQ-003: Pin each task by immutable `workflow_version_id`; do not copy a workflow instance or store a bundle digest on the task.
- BOOT-018-REQ-004: Remove project `.kos` workflow ownership, the filesystem workflow snapshot store, member manifests, and member digest contracts.
- BOOT-018-REQ-005: Preserve `input_context_digest` and external artifact or Git evidence digests where they bind data across an asynchronous or storage boundary.
- BOOT-018-REQ-006: Execute all workflow step instructions through `kos-workflow-step`; remove separate `kos-development`, `kos-review`, and `kos-publish` skills while retaining `kos-repository` as the sole mutating Git adapter.
- BOOT-018-REQ-007: Replace the vague `materials` concept with inline instructions and optional artifact templates; defer separate context documents until a concrete need exists.
- BOOT-018-REQ-008: Define an installation-wide opt-in `kos-retrospective` lifecycle for every gracefully ending KOS orchestrator and workflow-step subagent session, independent of the primary result.
- BOOT-018-REQ-009: Keep retrospective transcripts private to the invoking agent and expose only a sanitized structured `no_action` or improvement proposal to the orchestrator and user.
- BOOT-018-REQ-010: Classify proposals as KOS product, installation, shared workflow, or project problems; do not persist proposals or create tasks automatically in the first increment.
- BOOT-018-REQ-011: Correct the unreleased CLI v1 schemas, fixtures, errors, and contract tests in place.
- BOOT-018-REQ-012: Update the external development plan so persistence and later runtime work follow the revised architecture.

## Scope

- Add the central workflow catalog ADR and specification and a focused retrospective specification.
- Supersede ADR-0003 and the snapshot-store portion of ADR-0005 without rewriting completed task records.
- Update affected domain specifications, architecture and testing rules, draft CLI v1 schemas, fixtures, and contract tests.
- Remove obsolete project workflow schemas, `.kos` fixtures, and filesystem bundle contract tests.
- Update the bootstrap dashboard, roadmap, and backlog.

## Non-Goals

- Implementing migrations, Active Record models, API controllers, CLI commands, runtime skills, or OpenCode adapter hooks.
- Migrating existing workflow data; no workflow data has been implemented.
- Adding repository-specific workflow overrides, workflow-version migration for active tasks, durable retrospective proposals, automatic retrospective task creation, users, roles, or a web UI.
- Guaranteeing retrospective execution after process loss or an abrupt runtime termination.
- Rewriting historical completed `tasks/BOOT-*/task.md` records.

## Related Specifications And ADRs

- [Product Boundary](../../docs/specs/product-boundary.md)
- [Task Model](../../docs/specs/task-model.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [ADR-0003: Pinned Project Workflows](../../docs/decisions/0003-pinned-project-workflows.md)
- [ADR-0005: Central Persistence And Repository Registration](../../docs/decisions/0005-central-persistence-and-registration.md)

## Task-Local Decisions

- BOOT-018-DEC-001: Store workflow content in SQLite because the intended installation serves one to three projects and benefits more from one transactional backup boundary than from a separate immutable filesystem store.
- BOOT-018-DEC-002: A mutable draft is an authoring resource; publication atomically creates a complete immutable version. Activating a version affects only subsequently created tasks.
- BOOT-018-DEC-003: A task plus its pinned version and current state is the workflow instance; no separate mutable workflow-instance copy is introduced.
- BOOT-018-DEC-004: The generic workflow executor follows database-backed step instructions. Only typed repository effects cross into `kos-repository`.
- BOOT-018-DEC-005: Retrospective is a runtime lifecycle postprocessor, not a workflow status, artifact, or allowed workflow capability.
- BOOT-018-DEC-006: Retrospective is disabled by default at installation scope, runs on every graceful eligible session when enabled, and cannot alter or delay the durable primary outcome.
- BOOT-018-DEC-007: The first retrospective increment reports sanitized proposals to the user and does not create or persist follow-up work automatically.

## Acceptance Criteria

- BOOT-018-AC-001: Active specifications and ADR indexes identify KOS-owned shared workflow versions as canonical and contain no active project `.kos` or filesystem snapshot contract.
- BOOT-018-AC-002: The task and CLI contracts pin an immutable workflow version by identifier and retain only digests with a defined boundary purpose.
- BOOT-018-AC-003: Workflow publication, activation, graph validation, immutable version behavior, instruction and template storage, and future repository override boundaries are unambiguous.
- BOOT-018-AC-004: Runtime contracts use `kos-workflow-step` for all workflow instructions and keep mutating Git effects in `kos-repository`.
- BOOT-018-AC-005: Retrospective eligibility, opt-in scope, privacy, result transport, failure independence, recursion prevention, proposal categories, and no-automatic-task behavior are explicit.
- BOOT-018-AC-006: Draft CLI v1 schemas and contract tests represent the revised catalog, task, context, and error contracts and no longer reference bundle members.
- BOOT-018-AC-007: The external dashboard, roadmap, and backlog place BOOT-018 before revised persistence work and include workflow administration and retrospective runtime outcomes.
- BOOT-018-AC-008: Required project checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this baseline and mark BOOT-018 active externally.
2. Add the central catalog and retrospective normative documents and supersede conflicting ADR decisions.
3. Align product, task, workflow, artifact, persistence, initialization, runtime, CLI, architecture, and testing contracts.
4. Replace obsolete project bundle schemas and fixtures with central workflow publication contracts and update CLI v1 schemas and tests.
5. Update the external roadmap and backlog for revised BOOT-010 through BOOT-013 work, new workflow administration work, and runtime retrospective delivery.
6. Run contract tests, the full suite, lint, security, autoloading, and consistency checks; resolve findings within scope.
7. Complete the external plan, commit the task files, and push normally to the default branch.

## Implementation Result

- Added the central workflow catalog ADR and specifications for workflow publication, generic execution, and retrospective lifecycle.
- Replaced project-owned workflow bundle contracts with immutable catalog versions and one canonical definition digest.
- Defined draft import, validation, publication, activation, export, frozen step context, and typed repository-effect CLI contracts.
- Added durable generic commit/fetch/rebase intents, explicit success/failure/unknown effect results, and recovery ownership bindings; worktree and push effects retain their reservation and publication protocols.
- Replaced specialized workflow skills in the runtime contract with `kos-workflow-step` and defined private, opt-in, post-primary retrospective delivery.
- Removed obsolete project schemas, `.kos` fixtures, and snapshot bundle contract tests; added closed JSON schemas and graph, artifact, effect, SemVer, and retrospective contract coverage.

## Verification

- Run `bundle exec rspec spec/contracts` while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Search active specifications and schemas for obsolete `.kos`, snapshot, bundle, and specialized workflow-skill contracts.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-09 with `mise run check`, focused CLI contract tests, `git diff --check`, obsolete-contract searches, and independent review. No high- or medium-severity review findings remain.

## Risks

- BOOT-018-RISK-001: Central SQLite becomes the only durable workflow-content store. Production backup and restore must include that content and remain verified.
- BOOT-018-RISK-002: Incomplete database immutability could let an active task's behavior change. Persistence must enforce published-version update and deletion prohibitions.
- BOOT-018-RISK-003: A generic executor could broaden authority. Step contracts must enumerate typed repository effects, and only `kos-repository` may perform them.
- BOOT-018-RISK-004: Runtime end-session hooks may be unavailable or bypassed by crashes. Retrospective is guaranteed only on graceful eligible completion and remains best effort.
- BOOT-018-RISK-005: Non-persisted proposals can be lost after a session. Durable proposal storage remains a separate future decision.
