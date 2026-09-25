# Rewrite Schedulers And Commands

## Goal

Keep `/kos`, `/kos-fix`, and `/kos-brief` while making their commands and
scheduler skills short, permissive, and driven by server state.

## Scope

- Preserve the three user-facing commands and their assigned models.
- Remove detailed orchestration, creation, and recovery algorithms from prompts.
- Share scheduler behavior where practical.
- Keep task selection and progression understandable from CLI state.

## Out Of Scope

- Changing the server workflow graph.
- Simplifying individual step agents.
- Redesigning Git publication.

## Acceptance Criteria

- Command files contain only argument handling, model choice, and skill entry.
- Scheduler skills express intent and lifecycle at a high level.
- Fix and brief creation use the simplified idempotent CLI operation.
- Existing built-in workflows remain operable.
- `bin/check` passes.
