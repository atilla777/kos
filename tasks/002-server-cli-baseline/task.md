# Establish The Server And CLI Baseline

## Goal

Make the Rails server and packaged `kos` CLI the reliable foundation for all
later simplification work.

## Scope

- Define and verify one supported local installation path for the current CLI.
- Use `KOS_API_URL` and `KOS_API_TOKEN` consistently and remove documented
  reliance on obsolete configuration.
- Provide a straightforward CLI health check.
- Verify database preparation, built-in catalog installation, project lookup,
  and the core task lifecycle through the public CLI.
- Update installation and readiness documentation and tests.

## Out Of Scope

- OpenCode permission changes.
- Skill or workflow redesign.
- Database model simplification.

## Acceptance Criteria

- A clean install exposes the current `kos --version` and command inventory.
- The CLI can confirm server health without requiring a separate `curl` command.
- One documented configuration starts Rails and connects the packaged CLI.
- An automated smoke test exercises the core lifecycle through the CLI.
- Existing persisted development data remains valid.
- `bin/check` passes.
