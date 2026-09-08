---
title: Bootstrap Documentation and Planning System
task: BOOT-005
created: 2026-09-08
---

# BOOT-005: Bootstrap Documentation and Planning System

## Goal

Establish a small, reliable Obsidian planning system until KOS can own task state itself, and define how task-local documentation is kept in Git without duplicating specifications or ADRs.

## User Outcome

The user has one Obsidian entry point showing the current and next work, a bounded ordered backlog, a roadmap, an idea inbox, and a completion archive. An agent can start a new session from that state without treating Obsidian as a second source of product requirements.

## Context

The existing implementation plan combines a dashboard, roadmap, backlog, decisions, risks, and changelog in one file. KOS is not operational yet, so Obsidian temporarily owns planning state while normative documentation remains in Git.

## Requirements

- BOOT-005-REQ-001: Split bootstrap planning into a dashboard, roadmap, backlog, inbox, and archive using plain Markdown without required plugins.
- BOOT-005-REQ-002: Allow at most one `in-progress` bootstrap task and exactly one next task.
- BOOT-005-REQ-003: Assign monotonic temporary IDs in the form `BOOT-NNN`; preserve them as legacy references when tasks are imported into KOS.
- BOOT-005-REQ-004: Keep only the current and next roadmap phases expanded into backlog tasks.
- BOOT-005-REQ-005: Store the approved task baseline and implementation plan in `tasks/<temporary-id>/task.md` in Git. Do not create a separate `todo.md`.
- BOOT-005-REQ-006: Keep requirements, behavioral specifications, engineering rules, and ADRs in Git; Obsidian stores only operational planning state and links.
- BOOT-005-REQ-007: After KOS becomes operational, make the Obsidian dashboard a generated read-only projection of KOS state.

## Scope

- Restructure the current Obsidian implementation plan without losing active roadmap, risk, backlog, or completion information.
- Add this task document as the first bootstrap task record in Git.
- Update collaboration rules for the new dashboard path, bootstrap IDs, task records, session-local todos, and future generated dashboard.

## Non-Goals

- Migrating the high-level Obsidian specification into repository specifications.
- Implementing KOS task persistence, CLI commands, dashboard generation, or backlog import.
- Defining the final KOS task, workflow, artifact, or checkpoint schemas.
- Creating an Obsidian note for every backlog item.

## Related Specifications

- The high-level specification remains temporarily in Obsidian and will be migrated by BOOT-006.

## Related ADRs

- [ADR-0001: Central REST API and Multi-Repository State](../../docs/decisions/0001-central-rest-api.md)

## Task-Local Decisions

- BOOT-005-DEC-001: Use a single backlog row for planned work; create a detailed task document in Git only after implementation is authorized.
- BOOT-005-DEC-002: Use `BOOT-NNN` identifiers before KOS issues permanent `TASK-NNNNNN` identifiers.
- BOOT-005-DEC-003: Use plain Markdown and Obsidian links without Dataview or another required plugin.
- BOOT-005-DEC-004: Keep at most one bootstrap task in progress globally.
- BOOT-005-DEC-005: Keep the agent's detailed todo list session-local; use Git, the external plan, and an explicit blocker or next action for handoff.
- BOOT-005-DEC-006: Retain `KOS.md` after bootstrap as a generated read-only projection whose source of truth is KOS.

## Open Questions

None.

## Acceptance Criteria

- BOOT-005-AC-001: `KOS.md` identifies one current task or none, exactly one next task, blockers, active phase, and the last publication.
- BOOT-005-AC-002: Roadmap, backlog, inbox, and archive have non-overlapping documented responsibilities.
- BOOT-005-AC-003: Completed work and all current roadmap outcomes and risks remain discoverable after removing the monolithic plan.
- BOOT-005-AC-004: The backlog contains cohesive tasks only for phases 0 and 1 and records `next_boot_id` without reusing IDs.
- BOOT-005-AC-005: Repository collaboration rules point to the new dashboard and describe the approved bootstrap process.
- BOOT-005-AC-006: The obsolete monolithic plan is removed after links and migrated content are verified.
- BOOT-005-AC-007: Repository checks pass and the repository changes are committed and pushed to the default branch.

## Implementation Plan

1. Create this approved task baseline in Git.
2. Create the Obsidian dashboard, roadmap, backlog, inbox, and archive.
3. Move completed work into the archive and group phase 0 and phase 1 work into cohesive `BOOT-NNN` backlog entries.
4. Preserve later phases as roadmap outcomes and preserve current planning risks.
5. Update the collaboration rules to reference the dashboard and define bootstrap task records and handoff behavior.
6. Verify migrated content and links, then remove the old monolithic plan.
7. Run the required checks, commit the repository files, and push the default branch.
8. Record the publication in the dashboard and archive, leaving BOOT-006 as the next task.

## Verification

- Review every section of the old plan against its destination.
- Verify all Obsidian wiki links and repository Markdown links resolve.
- Run `git diff --check`.
- Run `mise run lint`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-005-RISK-001: Splitting the plan could lose a future task or risk. Compare every old section before deletion.
- BOOT-005-RISK-002: A manually maintained dashboard can drift. Keep one active task and one next task, and replace manual status with a generated projection after KOS is operational.
- BOOT-005-RISK-003: Temporary IDs could be mistaken for permanent KOS task numbers. Preserve them explicitly as legacy references during import.
