# KOS Agent Guide

KOS is a local, reliable workflow system for AI-assisted software development. Work toward the smallest correct change that preserves its state, Git, and workflow invariants.

## Required Reading

Before changing code, read the rules relevant to the work:

- `docs/rules/architecture.md` for domain boundaries, persistence, CLI, and Git side effects.
- `docs/rules/code-style.md` for Ruby and Rails conventions.
- `docs/rules/testing.md` for required verification.
- `docs/specs/` for applicable behavioral specifications. This directory has no domain specifications yet; do not invent requirements when none exist.

- `docs/decisions/` for applicable accepted ADRs.

## Working Rules

- Keep changes small, cohesive, and covered by tests.
- Treat the Ruby CLI as the sole agent-facing programmatic interface to KOS state. The CLI uses the Rails REST API; do not access SQLite directly outside Rails persistence code.
- Preserve workflow, locking, idempotency, artifact, and Git-worktree invariants. Do not bypass them for convenience.
- Keep domain logic independent of controllers, CLI parsing, Active Record callbacks, and Git command execution.
- Use Rails and Ruby best practices: clear names, small objects with one responsibility, explicit error handling, database constraints, and framework conventions.
- Run RuboCop and the relevant test suite before declaring work complete. Fix new lint violations rather than disabling cops without an agreed reason.
- Update a behavioral specification or ADR when a change alters an established external contract or architectural decision.
- Do not commit generated files, credentials, local databases, logs, or unrelated changes.

## Completion

Report the change, tests and lint run, and any remaining risk or unverified behavior. Ask for clarification when a required product decision is absent from the specifications.
