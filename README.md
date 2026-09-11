# KOS

KOS is a local workflow and state management system for AI-assisted software development. A central Rails API owns the SQLite state for multiple Git repositories, while agents interact with that state only through the `kos` CLI.

## Requirements

- [mise](https://mise.jdx.dev/) with project configuration trusted
- Git and SQLite

Ruby, the Rails bootstrap executable, and Lefthook are pinned in `mise.toml` and `mise.lock`. Application gems and Bundler are locked in `Gemfile.lock`.

## Setup

```sh
mise install
mise run setup
```

`bin/setup` installs gems, prepares the development database, installs Git hooks, and can be safely run again. Local databases and credentials are not committed.

## Development

Start the API on loopback only:

```sh
mise run server
```

By default the development database is `storage/development.sqlite3`. Set `KOS_DATABASE_PATH` to use another central state location. The test environment always uses its isolated test database.

A production process also requires `SECRET_KEY_BASE`; provide both secrets and state paths through the process environment, never committed files. Puma binds to `127.0.0.1` in every environment by default.

## CLI

Set `KOS_API_TOKEN` to the API bearer token. `KOS_API_URL` defaults to `http://127.0.0.1:3000`, and `KOS_API_TIMEOUT_SECONDS` defaults to `30`. Every command is non-interactive and requires `--json`:

```sh
bin/kos task-type list --limit 20 --json
bin/kos workflow get --workflow-version UUID --json
bin/kos task get --repository UUID --task KOS-000123 --json
bin/kos artifact list --repository UUID --task KOS-000123 --limit 20 --json
```

Workflow catalog mutations read only their command body from a JSON file or stdin and require an idempotency key:

```sh
bin/kos workflow-draft import --input draft-import.json --idempotency-key draft-import-1 --json
bin/kos workflow-draft validate --workflow quick-fix --json
bin/kos workflow publish --input publish.json --idempotency-key workflow-publish-1 --json
bin/kos workflow activate --input activate.json --idempotency-key workflow-activate-1 --json
bin/kos workflow export --workflow-version UUID --json
```

The import body contains `workflow_id`, the complete `definition`, and `expected_lock_version`. Publish contains `workflow_id` and `expected_lock_version`; activate contains `task_type`, `workflow_version_id`, and `expected_lock_version`. Use `--input -` to read the body from stdin.

Create a task from an input body containing `title` and `task_type: quick-fix`:

```sh
bin/kos task create --repository UUID --input task.json --idempotency-key task-create-1 --json
```

Claim and maintain workflow-step ownership with the attempt lifecycle commands. Each mutation reads its versioned body from `--input` and requires an idempotency key:

```sh
bin/kos attempt claim --repository UUID --input claim.json --idempotency-key attempt-claim-1 --json
bin/kos attempt renew --repository UUID --input renew.json --idempotency-key attempt-renew-1 --json
bin/kos attempt fail --repository UUID --input failed.json --idempotency-key attempt-fail-1 --json
bin/kos attempt needs-human --repository UUID --input needs-human.json --idempotency-key attempt-human-1 --json
bin/kos attempt reconcile --repository UUID --input reconcile.json --idempotency-key attempt-reconcile-1 --json
bin/kos step context --repository UUID --input context.json --idempotency-key step-context-1 --json
```

Claim requires the task number, owner ID, lease duration, and expected task lock version. Renew, fail, and needs-human require the active attempt ID, fencing token, and expected lock version. Reconcile is available after lease expiry and records the observed recovery state and evidence digest without asserting that an external effect succeeded.

`step context` requires the active attempt ID, fencing token, and expected task lock version. It atomically freezes and returns the pinned instruction, templates, artifact requirements, allowed repository effects, and execution metadata. A status requiring a worktree remains unavailable until its task-bound reservation is confirmed; publication context also remains unavailable until its durable publication intent has been prepared by the publication protocol.

Reserve, confirm, reconcile, and explicitly release task worktrees through the same mutation transport:

```sh
bin/kos worktree reserve --repository UUID --input reserve.json --idempotency-key worktree-reserve-1 --json
bin/kos worktree confirm --repository UUID --input confirm.json --idempotency-key worktree-confirm-1 --json
bin/kos worktree reconcile --repository UUID --input observation.json --idempotency-key worktree-reconcile-1 --json
bin/kos worktree release --repository UUID --input observation.json --idempotency-key worktree-release-1 --json
```

KOS reserves and fences state but does not create or remove a Git worktree. Confirmation and observations must come from the owning orchestrator after `kos-repository` verifies the persisted allocation. Cleanup first records a matching clean worktree as `release_pending`, then records its absence after external removal; dirty or mismatched worktrees remain reserved for explicit resolution.

The local repository adapter reads a closed version 1 request from a file or stdin and emits exactly one JSON result. Its request contains the registered repository snapshot, current reservation snapshot, and expected base or worktree HEAD:

```sh
bin/kos-repository materialize --input materialize.json --json
bin/kos-repository observe --input observation.json --json
bin/kos-repository remove --input removal.json --json
```

`materialize` accepts only a `reserved` reservation and creates its exact task branch and path from the expected base commit. `remove` accepts only `release_pending` and never removes a dirty, mismatched, or unproven worktree. The complete machine documents are defined by `schemas/repository/v1/adapter.json`; runtime skills and orchestration are installed separately.

The CLI writes one versioned JSON result to stdout and diagnostics to stderr.

## Checks

```sh
mise run test
mise run lint
mise run security
mise run zeitwerk
mise run check
```

See `AGENTS.md`, `docs/specs/`, `docs/rules/`, and `docs/decisions/` before changing application behavior or architecture.
