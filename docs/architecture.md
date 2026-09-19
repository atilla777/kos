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

At `PLAN-006`, Rails exposes the required administrative and task lifecycle
operations through a small bearer-authenticated JSON API while its readiness
endpoint remains public. Explicit response projections include each task's
snapshotted workflow and current step; known request, validation, transition,
ownership, and lookup failures have stable JSON errors. Pre-claim task
definition edits replace description, parent, and blockers atomically. The
lifecycle layer creates, edits, claims, resumes, transitions, pauses, completes,
and cancels tasks while fencing stale owners and repeated reports. Development
and production SQLite databases live in the configured local KOS data directory
outside the repository, and lease duration is configured by
`KOS_LEASE_SECONDS`. The application still contains no Git integration or
skills, and the CLI only prints help.

See [the product specification](specification.md) for the complete first-version
contract.
