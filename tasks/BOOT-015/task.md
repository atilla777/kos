---
title: Contextual Completion Reports
task: BOOT-015
created: 2026-09-08
---

# BOOT-015: Contextual Completion Reports

## Goal

Make completion reports understandable without requiring the user to look up task identifiers or reconstruct outcomes from prior messages.

## User Outcome

Each completion report briefly explains the completed task and the next task, states what was delivered, and describes what changed for a KOS user.

## Context

The completion rules list the required report fields, but they allow a terse report that names tasks only by identifier and does not make the delivered result or user impact sufficiently prominent.

## Requirements

- BOOT-015-REQ-001: Identify the completed or blocked task by both its identifier and a concise, context-rich description.
- BOOT-015-REQ-002: State what was done in the current task.
- BOOT-015-REQ-003: State what changed for a KOS user, explicitly saying when behavior did not change.
- BOOT-015-REQ-004: Identify the next task by both its identifier and a concise, context-rich description.
- BOOT-015-REQ-005: Keep the completion report brief and clear.

## Scope

- Strengthen the completion report requirement in the collaboration rules.

## Non-Goals

- Changing completion criteria, verification, publication, or external planning requirements.
- Starting BOOT-006 in this session.

## Acceptance Criteria

- BOOT-015-AC-001: The completion rules prohibit reporting the completed and next tasks as bare identifiers.
- BOOT-015-AC-002: The rules separately require the delivered work and user impact.
- BOOT-015-AC-003: Existing requirements for checks, publication, user action, and remaining risk are preserved.
- BOOT-015-AC-004: Project checks pass and the change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved task baseline.
2. Strengthen the completion report rule without changing the rest of the completion contract.
3. Run documentation and project checks.
4. Commit and push the repository changes.
5. Record completion externally and leave BOOT-006 as the next task.

## Verification

- Review the amended completion rule against every requirement and acceptance criterion.
- Run `git diff --check`.
- Run `mise run lint`.
- Run `mise run check`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-015-RISK-001: Repeating task descriptions, delivered work, and user impact can make reports verbose. Require concise descriptions while keeping each item explicit.
