# Architecture Rules

These rules govern implementation decisions in this repository.

## Boundaries

- Rails owns persistent state, validation, and transactional transitions.
- The CLI is a thin HTTP client and never reads SQLite directly.
- Skills own orchestration, substantive work, artifacts, checks, review, and
  Git operations.
- The file system owns current uncommitted work and Markdown artifacts.
- Git owns published commits and their SHA values.
- No hidden daemon, runtime broker, or general workflow engine is introduced.

## Design Rules

- Add a mechanism only when the end-to-end scenario requires it.
- Keep the REST API and CLI protocol small and explicit.
- Enforce state invariants at the server boundary and inside transactions.
- Prefer database constraints in addition to model validation where practical.
- Derive machine-local paths; do not persist them as domain state.
- Treat workflow definitions as immutable values after first use.
- Keep external side effects outside Rails transactions.
- Recover uncertain external operations by observation before retrying them.
- Never create a task commit before the publication step.

## Current Foundation

At `PLAN-001`, the application intentionally contains no KOS domain models,
domain controllers, authentication, Git integration, or skills. The only HTTP
route is Rails' readiness endpoint, and the CLI only prints help.

See [the product specification](specification.md) for the complete first-version
contract.
