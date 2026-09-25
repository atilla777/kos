# Run Simplified Live Acceptance

## Goal

Prove the simplified workflows and reviewed multi-commit publication through all
three real slash-command paths on clean local KOS state.

## Scope

- Remove local pre-release KOS database and task worktrees.
- Reinstall the current CLI, catalog, commands, profiles, and skills.
- Run `/kos-brief`, `/kos`, and `/kos-fix` through terminal publication.
- Exercise at least one task with multiple reviewed commits.
- Record task, graph, remote history, timing, and agent-launch evidence.

## Acceptance Criteria

- Clean installation contains no verifier or graph-validation command.
- All three tasks complete at `publish` and release ownership.
- Remote history preserves each reviewed commit unchanged.
- Brief publication materializes the reviewed child graph atomically.
- No verifier agent is launched.
- `bin/check` and independent remote checks pass.
