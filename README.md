# KOS

KOS is a local task tracker for AI agents. This increment provides a Rails JSON API backed by SQLite and the `kos` Ruby CLI for projects, task groups, task dependencies, ready work, lease-protected task execution, and versioned Markdown artifacts.

Current user-facing behavior and scenarios are documented in the [OKF knowledge bundle](docs/knowledge/index.md). The agreed MVP scope and baseline contract are in [the MVP specification](docs/mvp-specification.md). Contributions follow the mandatory plan → implement and test → review → update user-facing documentation → publish to `main` cycle in [AGENTS.md](AGENTS.md). This is a development process, not an automated KOS feature.

## Requirements

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3

## Server Setup

Get the source and enter the repository:

```bash
git clone https://github.com/atilla777/kos.git
cd kos
```

```bash
gem install bundler -v 4.0.20
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails server
```

The server listens only on `http://127.0.0.1:3000`. Set `PORT` to change the port while retaining the loopback-only binding. The persistent development database is `storage/development.sqlite3`.

The API is under `/api/v1`. Successful responses use a `data` object; errors use an `error` object with a stable `code` and `message`. Project, task-group, and task lists default to 50 records, accept at most 100, and return `pagination.next_after_id` for continuation. Group and task operations require the canonical repository key in `project`; creating either atomically creates a missing project, while reads never do. Group progress is computed from its tasks, and nonempty groups cannot be deleted.

## CLI Installation

Build and install the gem from the repository:

```bash
cd cli
gem build kos-cli.gemspec
gem install ./kos-cli-0.1.0.gem
```

The CLI uses `http://127.0.0.1:3000` by default. Set `KOS_API_URL` or pass `--url URL` before the resource name to select another local endpoint. Set `KOS_PROJECT` or pass `--project REPOSITORY` to select a project explicitly. Claim operations require a stable session identity through `KOS_SESSION_ID` or `--session SESSION`. Protected writes accept the server-issued claim through `KOS_CLAIM_ID` or `--claim CLAIM`; avoid exposing claim values in logs or shared shell history. Command-line options override environment variables.

## Basic Workflow

With the server running, enter any Git repository whose `origin` is a supported SSH or HTTPS URL. The following complete cycle relies on automatic project discovery and uses Ruby only to extract values from JSON:

```bash
TASK_ID=$(kos task create \
  --kind feature \
  --title "Add a health check" \
  --description "Implement and test the health check." | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("data", "task", "id")')

CLAIM_ID=$(kos --session agent-1 task claim-next | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("data", "task", "claim_id")')

printf '# Test report\n\nAll checks passed.\n' | \
  kos --claim "$CLAIM_ID" task artifact put "$TASK_ID" test_report --file -

kos --claim "$CLAIM_ID" task complete "$TASK_ID" \
  --work-summary "Implemented and verified."

kos task ready
```

The final output no longer includes the completed task. If Git or `origin` is unavailable, pass `--project github.com/owner/repository` explicitly.

## Command Reference

```bash
kos --project github.com/owner/repository project create --name "Repository"
kos project list --limit 50
kos --project github.com/owner/repository project show
kos project show 1
kos project update 1 --name "New name"
kos project delete 1

kos --project github.com/owner/repository group create \
  --kind epic \
  --title "Task management" \
  --description "Deliver task management capabilities."
kos --project github.com/owner/repository group list --limit 50
kos --project github.com/owner/repository group show 1
kos --project github.com/owner/repository group update 1 --title "Task workflows"
kos --project github.com/owner/repository group delete 1

kos --project github.com/owner/repository task create \
  --kind feature \
  --title "Add task CRUD" \
  --description "Implement the task endpoints and CLI commands." \
  --group-id 1 \
  --blocked-by-ids 10,11
kos --project github.com/owner/repository task list --limit 50
kos --project github.com/owner/repository task ready --kind feature --group-id 1
kos --project github.com/owner/repository --session agent-1 task claim-next --kind feature --group-id 1
kos --project github.com/owner/repository --session agent-1 task claim 1
kos --project github.com/owner/repository --session agent-1 task current
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task renew 1
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task update 1 --work-summary "Implementation in progress."
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task release 1 --work-summary "Paused safely."
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task complete 1 --work-summary "Implemented and verified."
kos --project github.com/owner/repository task reopen 1
kos --project github.com/owner/repository task show 1
kos --project github.com/owner/repository task update 1 --blocked-by-ids ""
kos --project github.com/owner/repository task update 1 --no-group
kos --project github.com/owner/repository task delete 1

kos --project github.com/owner/repository task artifact list 1
kos --project github.com/owner/repository task artifact get 1 specification
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" \
  task artifact put 1 specification --file specification.md
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" \
  task artifact put 1 specification --file - --version 0
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" \
  task artifact delete 1 specification --version 1
```

Without `--project`, repository-sensitive commands derive the canonical project key from the current Git repository's `origin`. GitHub SSH and HTTPS remotes such as `git@github.com:owner/repository.git` and `https://github.com/owner/repository.git` resolve to `github.com/owner/repository`. Unsupported or absent remotes require explicit `--project`. New tasks start in `planned`; ordinary create and update commands cannot set status or claim and lease fields. A claim lasts 30 minutes. `claim-next` atomically selects work on the server and returns the session's existing active task before selecting another; `current` reads that task without extending its lease. `renew` extends only a current lease, while `release` and `complete` atomically preserve an optional summary and clear ownership. At `lease_expires_at <= now`, the old claim loses all write access. `reopen` is explicit and is rejected after dependent work has started or completed.

`task show`, `task current`, and successful `claim`/`claim-next` responses contain the same detailed context: the task and its artifacts, optional group, immediate blockers, blocker artifacts with explicit source metadata, dependent tasks, and computed availability reasons. Only owner responses include `claim_id`. Context collections default to 50 records and accept at most 100 through `--context-limit`; an incomplete collection has `pagination.<collection>.complete: false`, its continuation flag in `after_parameter`, and its cursor in `next_after_id`. The CLI supports `--artifact-after-id`, `--blocked-by-after-id`, `--dependency-artifact-after-id`, and `--blocks-after-id` on all four context-returning commands.

Artifact reads do not require a claim. Creating, updating, and deleting an artifact require the task's active claim. A `put` without `--version` sends `lock_version: null` and creates only an absent key; updating requires the version returned by `artifact get` through `--version N`. Deletion also requires the current version. A stale expectation returns `artifact_version_conflict` without overwriting or deleting the newer document. Use `--file -` to read UTF-8 Markdown from stdin. Release, lease expiry, and reclaim preserve artifacts; completed-task artifacts remain readable but cannot be changed.

JSON success and error results are written to stdout; separate diagnostics use stderr. Exit codes are `0` for success, `1` for a non-conflict API error, `2` for invalid input or project discovery failure, `3` for a connection error, `4` for an API conflict, and `5` when a mutating request may have completed without a valid response reaching the CLI. The latter returns `ambiguous_result` and a verification command; inspect server state before retrying. The CLI never retries mutating requests automatically. HTTP connection, read, and write timeouts are 5, 15, and 15 seconds respectively. Error output redacts the configured claim and URL credentials.

SQLite write contention waits for at most five seconds. If the database remains locked, the API returns `503` with `database_busy` and leaves the attempted transaction unapplied; clients may retry only after checking current server state.

## Verification

```bash
bin/rails test
ruby -Icli/lib:cli/test cli/test/repository_test.rb
ruby -Icli/lib:cli/test cli/test/command_test.rb
ruby -Icli/lib:cli/test cli/test/client_test.rb
(cd cli && gem build kos-cli.gemspec --output /tmp/kos-cli.gem)
script/acceptance
```

Run `script/acceptance` from the repository root. It builds and installs the gem into an isolated temporary gem home, starts a temporary Rails/SQLite server, exercises automatic Git project discovery and the main task cycle through the installed `kos` executable, and verifies online backup and offline restore. `bin/ci` runs this acceptance test together with style, security, server tests, CLI tests, and the gem build. The complete mapping from specification section 15 to automated checks is in [`docs/acceptance.md`](docs/acceptance.md).

## Backup And Restore

SQLite's online backup command creates a consistent backup while the server is running:

```bash
sqlite3 storage/development.sqlite3 ".backup '/path/to/kos-backup.sqlite3'"
```

Stop the Rails server before restoring, then run:

```bash
sqlite3 storage/development.sqlite3 ".restore '/path/to/kos-backup.sqlite3'"
bin/rails db:prepare
```

## Guarantee Boundaries

The local-only server has no authentication and must not be exposed on a network. A `done` status records the executor's assertion that the result is complete; it does not prove that tests or review ran, that an artifact is complete or high quality, that work reached `main`, or that an old agent stopped changing local files.

KOS protects its own records and rejects writes from stale claims. It cannot guarantee that an agent is still running or prevent filesystem and external-service actions after a lease expires. An ambiguous mutating network request must be checked before retrying.

Normal KOS commands only read Git's `origin` for project discovery. They do not create worktrees, switch branches, commit, push, merge, or call the GitHub API. The server does not require OpenCode, Redis, skills, MCP, a UI, or a workflow engine.
