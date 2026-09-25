# Remove OpenCode Permission Policy

## Goal

Remove brittle KOS-specific OpenCode permission rules while preserving commands,
agents, role-specific models, and reasoning settings.

## Scope

- Remove permission blocks from every managed KOS agent profile.
- Keep profile roles, models, and reasoning effort.
- Remove permission-pattern contract tests and claims of sandbox enforcement.
- Preserve clean installation of commands, agents, and skills.

## Out Of Scope

- Rewriting skill behavior.
- Changing workflow steps or models.
- Changing the server or CLI lifecycle.

## Acceptance Criteria

- No managed KOS profile contains a `permission` block.
- Commands, profiles, skills, and model assignments remain installable.
- Tests validate inventory and essential metadata rather than shell patterns.
- Documentation describes OpenCode profiles as role/model selection, not a
  security boundary.
- `bin/check` passes.
