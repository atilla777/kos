# Complete Built-In Tasks At Publication

## Goal

Remove the redundant built-in verification step. A successful publication that
has observed the expected remote result completes the task.

## Scope

- Remove `verify` from the brief, development, and fix workflows and agent inventory.
- Make `published` complete built-in tasks and release ownership.
- Keep remote observation and brief child existence as publication prerequisites.
- Keep required-check gates at review and publication.
- State that the shared bearer token trusts its holders, while ownership fencing
  provides concurrency consistency rather than authorization.
- Treat the change as pre-release and breaking; do not add legacy workflow support.

## Out Of Scope

- Brief graph API simplification.
- Multiple pre-publication commits.
- RBAC, scoped credentials, or per-agent authorization.

## Acceptance Criteria

- Fresh built-in workflows contain no `verify` step.
- `published` is the only successful built-in completion outcome.
- Publication reports are accepted only after applicable check and graph gates.
- The scheduler and installed inventory contain no verifier profile.
- Deterministic tests and normative documentation describe terminal publication.
- `bin/check` passes.
