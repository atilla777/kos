# Rewrite The CLI Skill

## Goal

Replace the detailed CLI protocol skill with concise guidance for using the
public, self-describing `kos` executable.

## Scope

- Keep configuration, authentication, exit-status, and safe input essentials.
- Direct agents to command help instead of duplicating every option.
- Remove manual projection validation and extensive retry algorithms from prose
  when deterministic CLI behavior provides them.
- Update tests to check behavior and discoverability rather than exact wording.

## Out Of Scope

- Scheduler or step-agent behavior.
- Workflow redesign.
- Git publication behavior.

## Acceptance Criteria

- The skill describes role, configuration, discovery, and essential error
  handling concisely.
- CLI command syntax has one authoritative implementation and help source.
- Skill tests do not lock incidental prose.
- `bin/check` passes.
