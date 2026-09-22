# Agent Rules

## Task Continuity

After the user approves a task's scope and acceptance criteria, continue the
task autonomously through implementation, verification, commit, push, remote
verification, and task-state updates.

Do not stop merely because implementation or checks are complete. A normal KOS
task stops only when one of these conditions is true:

- publication has been observed successfully;
- a concrete product or implementation decision requires the user;
- a technical blocker prevents safe progress.

Commit and push are part of completing an approved KOS task and do not require
a second confirmation. Never force-push. If publication has an ambiguous
result, observe local and remote Git state before retrying or reporting a
blocker.

Before `PLAN-012`, maintain task state in the project's Obsidian bootstrap
documents and do not use `/kos`. During `PLAN-012`, use `/kos` only for the
planned end-to-end verification.

## Project Contracts

Read these documents before changing behavior or architecture:

- `specs/index.md`
- `docs/specification.md`
- `docs/architecture.md`
- `docs/testing.md`
- `CONTRIBUTING.md`

Work on only the agreed active task and do not implement later roadmap items
opportunistically. Run `bin/check` before publication.
