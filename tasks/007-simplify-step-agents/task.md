# Simplify Step Agents

## Goal

Let focused agents perform substantive work without carrying a large mechanical
KOS protocol in every prompt.

## Scope

- Keep role-specific profiles and model assignments.
- Shorten step prompts to role, task context, expected result, and essential
  boundaries.
- Let the server enforce ownership, fencing, transitions, and artifact
  acceptance.
- Reduce repeated context and predecessor validation instructions.

## Out Of Scope

- Changing the built-in workflow graph.
- Automating Git publication in the CLI.
- Changing the Rails data model.

## Acceptance Criteria

- Each profile is concise and understandable without protocol archaeology.
- Agents can use normal repository tools appropriate to their role.
- Invalid reports remain rejected by the server.
- Independent review and verification roles remain explicit.
- `bin/check` passes.
