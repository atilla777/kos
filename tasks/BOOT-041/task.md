---
title: Production Quick-Fix Workflow
task: BOOT-041
created: 2026-09-14
status: completed
---

# BOOT-041: Production Quick-Fix Workflow

## Goal

Publish and globally activate the corrected immutable central workflow version `quick-fix@1.0.1` for new quick-fix tasks.

## User Outcome

Every newly created quick-fix task is pinned to one reviewed production workflow whose planning executor uses the exact approved task input from its frozen context. Existing tasks retain their pinned versions, including the unusable `quick-fix@1.0.0` where already selected.

## Context

The central catalog already supports authenticated draft import, validation, immutable publication, activation, and canonical export. `quick-fix@1.0.0` was published and activated during the first implementation attempt, but independent review found that its planning instruction requires input unavailable to an isolated executor. BOOT-044 now persists immutable versioned approved task input and transports it in every newly finalized executable context. Because published workflow content is immutable, this task must preserve `1.0.0` as historical content and publish a corrected semantic version. The normative graph and artifact contracts are already specified.

## Requirements

- BOOT-041-REQ-001: Preserve the exact reviewable source for published `quick-fix@1.0.0` and add a corrected production source for `quick-fix@1.0.1`, while retaining the central SQLite catalog as the live source of truth.
- BOOT-041-REQ-002: Use the specified `implementation-planning`, `development`, `review`, and `publication` executable statuses followed by terminal `completed`, including the `changes_requested` route from review back to development.
- BOOT-041-REQ-003: Keep every executable status in `subagent` mode with a required worktree; allow repository changes only during planning and development.
- BOOT-041-REQ-004: Keep the minimal typed-effect allowlists: planning and development may request `commit`, review may request no effects, and publication may request `fetch`, `push`, and `worktree_remove`.
- BOOT-041-REQ-005: Instruct planning to use the exact immutable approved task input from the frozen executable context and create and commit `tasks/<task-number>/implementation-plan.md` from the supplied template with current and target state, design, affected components and contracts, implementation sequence, tests, risks, and task-local traceability where applicable.
- BOOT-041-REQ-006: Instruct development to implement only the approved task input and committed plan, run required verification, request a verified task commit, and return one candidate plus passed test evidence for the exact candidate.
- BOOT-041-REQ-007: Instruct review to inspect the exact candidate independently against the approved task input and committed plan, without repository changes, and return either approved or changes-requested evidence for that candidate.
- BOOT-041-REQ-008: Instruct publication to publish only the approved prepared candidate, safely release its worktree after observed publication, and never convert failed or unknown effects into success.
- BOOT-041-REQ-009: Validate both exact production documents through the version 1 schema and whole-graph validator and pin the corrected `1.0.1` canonical content digest in contract coverage.
- BOOT-041-REQ-010: Import, validate, publish, and globally activate the exact `1.0.1` production document through the existing authenticated CLI, then verify canonical export, digest, immutable version identity, active task-type selection, and unchanged pinning for an existing task.

## Scope

- Historical `quick-fix@1.0.0` and corrected `quick-fix@1.0.1` workflow definitions, inline instructions, and implementation-plan template.
- Focused contract coverage and removal of a divergent quick-fix test definition.
- Live central-catalog publication and global activation through `bin/kos`.
- Task documentation and external development-plan updates.

## Non-Goals

- Rails, API, CLI, schema, migration, or seed changes.
- Automatic catalog publication during setup or deployment.
- Completing the full quick-fix operational slice or its remaining orchestration surfaces.
- Rebase orchestration or broader repository-effect allowlists.
- Changing workflow versions pinned by existing tasks.

## Related Specifications And ADRs

- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-041-DEC-001: Preserve the published interchange source at `workflows/quick-fix/1.0.0.json` and store its corrected successor at `workflows/quick-fix/1.0.1.json`; publication makes the central catalog authoritative rather than turning this directory into runtime configuration.
- BOOT-041-DEC-002: Replace the concise test fixture with the corrected production definition as the shared default used by catalog tests, while retaining the exact historical source for immutable-version review.
- BOOT-041-DEC-003: Preserve the conservative effect allowlists already represented by the normative MVP graph; later base-movement orchestration will be a separate task.
- BOOT-041-DEC-004: Activate `quick-fix@1.0.1` globally for future quick-fix tasks. Existing tasks remain unchanged by catalog contract.
- BOOT-041-DEC-005: If the live catalog already contains different content under `quick-fix@1.0.1`, stop rather than attempting to replace immutable content or silently choosing another version.
- BOOT-041-DEC-006: Treat the frozen context's versioned `task_input` as the sole approved requirements source for planning; repository bootstrap records and parent dialogue are not workflow input.

## Acceptance Criteria

- BOOT-041-AC-001: Both production definitions pass JSON Schema and whole-graph validation and the expected canonical digest of corrected `1.0.1` is asserted by an automated test.
- BOOT-041-AC-002: Planning, development, review, publication, artifacts, transitions, repository policies, and effect allowlists match the approved requirements.
- BOOT-041-AC-003: Isolated catalog coverage proves canonical publication/export and that activation selects `1.0.1` for new tasks without changing an existing task's pinned version.
- BOOT-041-AC-004: The live catalog exports the reviewed `1.0.1` definition with the asserted digest and reports its immutable version as the active quick-fix selection.
- BOOT-041-AC-005: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record the approved revised baseline, mark BOOT-041 active externally, and reconcile the saved diff with published prerequisite BOOT-044.
2. Preserve the historical `1.0.0` definition and add corrected `1.0.1` instructions and planning template using frozen approved task input.
3. Point catalog test support at corrected `1.0.1` and add focused contract assertions for both documents, the corrected graph and content, canonical digest, export, activation, and task pinning.
4. Run focused specs, the full project quality gate, and diff validation.
5. Read live catalog locks, import and validate the `1.0.1` draft, publish it atomically, and globally activate the returned version using stable idempotency keys.
6. Verify the live export, content digest, immutable version identity, and active task-type selection.
7. Record verification, update the external plan, perform independent review, commit only task files, and push normally to `main`.

## Verification

- Run focused workflow-catalog and production-definition contract specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Verify the published version through `bin/kos workflow get`, `workflow export`, `workflow list`, and `task-type list`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed before blockage on 2026-09-14:

- Focused workflow definition, validator, publication, and CLI specs passed with 131 examples and 0 failures.
- `mise run check` passed with 728 examples, 0 failures, 189 RuboCop-inspected files with no offenses, no Brakeman warnings, no vulnerable dependencies, and successful Zeitwerk eager loading.
- `git diff --check` passed after excluding development-database schema dump drift from the task.
- The local central development state was brought through its one pending migration using Rails persistence, then the exact source was imported, validated, published, activated, and read back exclusively through the version 1 CLI.
- Live publication created workflow version `8b25224a-e295-471a-af72-7d8ca21d2ca6` with content digest `sha256:b5e2205f398b12e27dcb6d48053d2aee32f457049d9655a42eaf54f06ce69d6b`; canonical export matched and the quick-fix task-type lock advanced to `1`.

Verification completed after resumption on 2026-09-15:

- Focused workflow contract, catalog, task-pinning, read API, CLI, and migration coverage passed; the final focused pinning check passed with 14 examples and 0 failures.
- `mise run check` passed with 741 examples and 0 failures, 191 RuboCop-inspected files with no offenses, no Brakeman warnings, no vulnerable dependencies, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent review found that activation coverage did not create a task after selecting `1.0.1`. The test was corrected to use `TaskCreation::Create` both before and after activation; final re-review found no publication-blocking defects.
- The local central development state was brought through the published BOOT-044 migration using Rails persistence.
- The exact `1.0.1` source was imported, validated without graph errors, published, activated, and read back exclusively through the version 1 CLI using idempotent mutations.
- Live publication created workflow version `8d74789d-eb71-47f2-9c40-6ed3ae34026b` with content digest `sha256:db2ffddd73dd0715b00d80c5dac7f45f40f4e93b713ad898cab93a6d258d2e5b`; canonical export matched the exact normalized source, workflow listing retained both immutable versions, and the quick-fix task-type lock advanced to `2` with `1.0.1` active.

## Implementation Result

- Preserved exact historical source and digest coverage for published `quick-fix@1.0.0`.
- Added corrected `quick-fix@1.0.1`, whose planning, development, and review instructions consume the immutable approved task input from frozen executable context.
- Replaced the divergent concise fixture with production sources and made `1.0.1` the shared catalog-test definition.
- Added exact graph, policy, instruction-source, canonical digest, immutable pinning, and post-activation task-selection coverage.
- Published and globally activated `quick-fix@1.0.1` in the live central catalog.

## Previous Blocker And Revised Direction

Independent review found that the production planning instruction requires an approved task record and must return `needs_human` when it is absent, while a normal `task.create` stores only a title and the finalized version 1 step context supplies neither title nor approved requirements. The isolated executor cannot read KOS state or the parent dialogue. A newly created quick-fix task therefore has no guaranteed authoritative input from which to create its implementation plan.

The published `quick-fix@1.0.0` is immutable and already active, so it cannot be corrected in place. The user selected a separate prerequisite rather than broadening this catalog-content task across persistence, API, CLI, schema, and runtime boundaries. No new quick-fix task may be created until that prerequisite provides a durable approved task brief and versioned executable-context transport. BOOT-041 will then resume to publish and activate a corrected semantic version.

The prerequisite was completed by BOOT-044 and published as `16c2f04`. On 2026-09-15 the user approved this revised baseline, authorizing publication of corrected `quick-fix@1.0.1`; the saved diff was then reconciled onto that prerequisite without conflicts.

## Risks

- BOOT-041-RISK-001: Published content is immutable; correcting it requires a new semantic version.
- BOOT-041-RISK-002: Global activation affects every repository's newly created quick-fix tasks.
- BOOT-041-RISK-003: Live publication requires an authenticated running KOS service and cannot complete while `KOS_API_TOKEN` is unavailable.
- BOOT-041-RISK-004: Publication makes the workflow selectable but does not remove the separately recorded operational gaps that still prevent the complete quick-fix E2E slice.
