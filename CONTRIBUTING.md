# Contributing

## Workflow

1. Work on one agreed task with explicit scope and acceptance criteria.
2. Read the product specification and architecture rules before changing a
   system boundary or invariant.
3. Make the smallest change that satisfies the current task.
4. Add or update tests for observable behavior.
5. Run `bin/check` before declaring the task complete.
6. Commit, push without force, and verify the remote result.
7. Keep documentation and task state synchronized with changed contracts.

After scope approval, continue through this entire workflow without requesting
another confirmation for normal commit or push operations. Stop before
publication only for a concrete question that requires the user or a technical
blocker that cannot be resolved safely.

## Change Rules

- Do not implement later roadmap items opportunistically.
- Do not add compatibility paths without a concrete shipped consumer or stored
  data that requires them.
- Do not commit secrets, local SQLite files, logs, temporary files, task
  artifacts, or worktrees.
- Do not bypass the public CLI with direct SQLite access in agent tooling.
- Do not create commits during future task execution before its publication
  step.
- Keep user-facing commands and normative documents in English unless a task
  explicitly establishes another convention.

## Review

Review prioritizes correctness, invariant preservation, behavioral regressions,
security, recovery behavior, and missing tests. A future KOS task review is
read-only and must be performed by an agent other than the implementing agent.
