---
title: Concise Numbered Approval Prompts
task: BOOT-014
created: 2026-09-08
---

# BOOT-014: Concise Numbered Approval Prompts

## Goal

Make required approval and implementation authorization prompts concise and answerable with a number alone.

## User Outcome

When the agent needs approval of a final baseline or authorization to implement it, the user receives short numbered choices and does not need to repeat a prescribed approval sentence.

## Context

The collaboration rules require explicit approval of the final requirements and implementation plan followed by separate implementation authorization. They do not currently specify a concise response format, which led to a request for a long confirmation phrase.

## Requirements

- BOOT-014-REQ-001: Present approval and implementation authorization as concise numbered choices.
- BOOT-014-REQ-002: Accept the corresponding number alone as an explicit response.
- BOOT-014-REQ-003: Do not require the user to repeat a prescribed confirmation sentence.
- BOOT-014-REQ-004: Preserve separate approval and implementation authorization.

## Scope

- Update the collaboration rules governing approval prompts.

## Non-Goals

- Changing when approval or implementation authorization is required.
- Changing how open-ended discovery questions or material alternatives are discussed.
- Starting BOOT-006 in this session.

## Task-Local Decisions

- BOOT-014-DEC-001: Apply the numeric response requirement specifically to final baseline approval and implementation authorization prompts.

## Acceptance Criteria

- BOOT-014-AC-001: The collaboration rules require concise numbered approval and authorization choices.
- BOOT-014-AC-002: The rules state that a number alone is sufficient and prohibit requiring a prescribed confirmation phrase.
- BOOT-014-AC-003: Separate approval and implementation authorization remain mandatory.
- BOOT-014-AC-004: Documentation checks pass and the change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved task baseline.
2. Add the concise numeric response requirement to the approval rules.
3. Run documentation and project checks.
4. Commit and push the repository changes.
5. Record completion externally and leave BOOT-006 as the next task.

## Verification

- Review the amended approval rules against all requirements and acceptance criteria.
- Run `git diff --check`.
- Run `mise run lint`.
- Run `mise run check`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-014-RISK-001: A broad numeric-only rule could make open-ended discovery awkward. Limit the rule to baseline approval and implementation authorization prompts.
