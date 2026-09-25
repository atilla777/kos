# Required-Check Live Acceptance

Date: 2026-09-25

## Public Protocol

The packaged CLI and a running Rails server used an isolated gem home, data
home, SQLite database, and project registration. Development task 1 and fix task
2 each reached `implement`; an `implemented` report with
`required_checks=failed` returned `invalid_transition`, left the same claim and
step active, and created no publish artifact. Each task then accepted a
replacement report with `required_checks=passed`, exposed that assertion through
`task artifact` and `task context`, and completed through review, publication,
and verification.

## Live Models

OpenCode 1.18.26 used the integration and CLI gem installed from the task 010
worktree against isolated KOS state. `/kos` task 3 ran with only the isolated
gem home available. Its implementation agent attempted `bin/check`, observed
missing locked dependencies, reported `blocked` with
`required_checks=failed`, and stopped at `implement`; review, publication, and
verification did not run.

`/kos-fix` task 4 diagnosed the same unprovisioned environment, provisioned the
locked bundle outside the worktree, ran `bin/check` successfully, and stored
`required_checks=passed`. It reached publication but correctly blocked because
the environment-only result had no repository change to commit. No live-model
task published or pushed. Raw event streams and server logs remain only in the
temporary isolated acceptance area.

## Evidence

- `development-rejection.json` and `fix-rejection.json` preserve the server
  rejection returned through the packaged CLI.
- `development-implementation.json` and `fix-implementation.json` preserve the
  successful replacement implementation artifacts.
- `model-development-context.json` and `model-development-implementation.json`
  preserve the failed-check stop from real `/kos` execution.
- `model-fix-context.json` and `model-fix-implementation.json` preserve the
  successful-check result and non-publication stop from real `/kos-fix`
  execution.
