# Contributing

## Workflow

1. Read `tasks/roadmap.md` and the active task's `task.md`, `plan.md`, and
   `status.md`.
2. Read the product specification, architecture rules, testing rules, and
   installation contract before changing behavior or boundaries.
3. Work on one agreed task with explicit scope and acceptance criteria.
4. Make the smallest change that satisfies the current task.
5. Update tests, relevant documentation, and the task status.
6. Run `bin/check` before publication.
7. Commit the completed task, push without force, and verify the remote result.

KOS repository development uses the Markdown records under `tasks/`; it does
not use KOS itself for task coordination. These files are development records,
not server state or a public KOS task format.

After scope approval, continue through implementation, verification, task-file
updates, commit, push, and remote observation unless a product decision or
technical blocker requires the user.

## Change Rules

- Do not implement later roadmap items opportunistically or add compatibility
  paths without a concrete persisted or shipped requirement.
- Do not commit secrets, local SQLite files, logs, temporary files, creation
  state, or worktrees.
- Preserve existing persisted KOS data unless the active task explicitly
  includes a migration.
- Keep mechanical guarantees in deterministic code rather than detailed agent
  instructions whenever practical.
- Keep skills focused on role, input, result, and essential safety boundaries;
  do not encode HTTP, filesystem, locking, or Git algorithms in prose.
- Keep user-facing commands and normative documents in English unless a task
  explicitly establishes another convention.

## Review

Review prioritizes correctness, behavioral regressions, data safety, recovery,
security, operational simplicity, and missing tests. Treat unnecessary process,
agent instructions, and configuration as maintainability risks.
