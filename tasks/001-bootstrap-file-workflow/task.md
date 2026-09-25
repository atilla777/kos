# Bootstrap The File Workflow

## Goal

Create a simple repository-local process for planning and tracking development
of KOS without using KOS itself.

## Scope

- Add one authoritative development roadmap.
- Add a directory with `task.md`, `plan.md`, and `status.md` for every agreed
  migration task.
- Define how an agent selects and completes the next task.
- Replace the self-hosted KOS development rules in `AGENTS.md` and
  `CONTRIBUTING.md`.

## Out Of Scope

- Product behavior, API, database, CLI, skill, command, or profile changes.
- A parser or schema for task Markdown.
- Synchronization between these files and the KOS server.

## Acceptance Criteria

- `tasks/roadmap.md` contains the agreed ordered migration plan.
- Every roadmap task has a stable scope, a plan, and a status file.
- A later session can identify and start the next available task by reading the
  repository files.
- Repository rules require checks, automatic commit and push, and remote
  verification for approved tasks.
- `bin/check` passes.
