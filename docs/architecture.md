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

At `PLAN-010`, Rails exposes the required administrative and task lifecycle
operations through a small bearer-authenticated JSON API while its readiness
endpoint remains public. Explicit response projections include each task's
snapshotted workflow and current step; known request, validation, transition,
ownership, and lookup failures have stable JSON errors. Pre-claim task
definition edits replace description, parent, and blockers atomically. The
lifecycle layer creates, edits, claims, resumes, transitions, pauses, completes,
and cancels tasks while fencing stale owners and repeated reports. Development
and production SQLite databases live in the configured local KOS data directory
outside the repository, and lease duration is configured by
`KOS_LEASE_SECONDS`. A thin, stateless `kos` HTTP client exposes every current
API operation, reads workflow JSON and task Markdown from files or standard
input, preserves server responses, and reports local or transport failures as
structured errors. A distributable OpenCode Git skill derives task worktree
paths from the configured KOS data home, isolates uncommitted task work, and
defines observation-driven base-update, publication, and interruption-recovery
procedures. It uses Git directly and adds no Git API, wrapper, broker, or
persisted Git state to Rails. The `/kos` OpenCode command loads a CLI-only
orchestrator skill, which verifies ownership before each step, delegates exactly
one step to a fresh executor, requires independent read-only review, atomically
writes the current Markdown artifact before reporting an outcome, and recovers
uncertain reports by observing server state. No artifact state or orchestration
runtime is added to Rails.

See [the product specification](specification.md) for the complete first-version
contract.
