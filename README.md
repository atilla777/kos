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
