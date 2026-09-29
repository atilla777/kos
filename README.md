# KOS

KOS is a local task tracker for AI agents. The Rails JSON API and `kos` Ruby CLI provide projects, task groups, dependencies, lease-protected work, versioned Markdown artifacts, and server-owned workflow steps.

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

The API is under `/api/v1`. Successful responses use a `data` object; errors use an `error` object with a stable `code` and `message`. Project, task-group, task, and workflow lists default to 50 records, accept at most 100, and return `pagination.next_after_id` for continuation. Group, workflow, and task operations require the canonical repository key in `project`; creating a group or workflow atomically creates a missing project, while reads never do. A task must reference an existing workflow in its project. Group progress is computed from its tasks, and nonempty groups cannot be deleted.

## CLI Installation

Build and install the gem from the repository:

```bash
cd cli
gem build kos-cli.gemspec
gem install ./kos-cli-0.1.0.gem
```

The CLI uses `http://127.0.0.1:3000` by default. Set `KOS_API_URL` or pass `--url URL` before the resource name to select another local endpoint. Set `KOS_PROJECT` or pass `--project REPOSITORY` to select a project explicitly. Claim operations require a stable session identity through `KOS_SESSION_ID` or `--session SESSION`. Protected writes accept the server-issued claim through `KOS_CLAIM_ID` or `--claim CLAIM`; avoid exposing claim values in logs or shared shell history. Command-line options override environment variables.

## OpenCode Integration

The integration ships three skills (`kos-setup`, `kos-orchestrator`, `kos-executor`) and three agent profiles (`kos-orchestrator`, `kos-standard`, `kos-advanced`). From the KOS checkout, after installing the server and CLI as above:

```bash
ruby script/install-opencode
opencode models openai
opencode agent list
```

The installer copies only KOS files to `~/.config/opencode/` (or `$XDG_CONFIG_HOME/opencode/`), preserving other global settings. It stops before copying if a destination differs; resolve that file explicitly before rerunning. To refresh after updating KOS, review and remove or relocate only the previous KOS copies first. OpenCode loads configuration at startup: **quit and restart OpenCode** after installing or updating agents or skills. Confirm `openai/gpt-6-luna` and `openai/gpt-6-sol` are available from your OpenAI provider and that all three agents appear in `opencode agent list`.

In the target Git repository, select the `kos-orchestrator` primary agent and ask it to work on the next KOS task. Before claiming work, set a stable `KOS_SESSION_ID` unique to this OpenCode session (for example, its OpenCode session ID). Use `KOS_PROJECT` if the Git `origin` cannot identify the project; use `KOS_API_URL` for a nondefault loopback port. Do not reuse a session ID for independent concurrent agents. An active claim belongs to the whole task; pass it to the executor privately, without logging it. The orchestrator reads compact routes and delegates `standard` steps to Luna, `advanced` steps to Sol, while running `main` steps itself (under the Sol profile). The executor independently calls `kos task step show TASK_ID` and writes results under the delegated claim; the orchestrator verifies and explicitly advances or completes. The workflow author chooses the tier for each step: focused documentation or simple development may be `standard`, while work needing more judgment may be `advanced`. Project instructions govern any publication by the main agent.

If work takes longer than the 30-minute lease, the orchestrator explicitly renews it. On a conflict or ambiguous write, inspect the current route or artifact before retrying. OpenCode profiles provide instructions, not server-side validation of the model, instruction quality, tests, or Git state. See [the user scenarios](docs/knowledge/features/opencode-integration.md) for normal and recovery flows.

## Basic Workflow

With the server running, enter any Git repository whose `origin` is a supported SSH or HTTPS URL. Create a `workflow.json` definition:

```json
{
  "name": "Small feature",
  "steps": [
    {
      "name": "Implement",
      "instructions": "Implement and verify the change. Write a test report.",
      "executor": "subagent",
      "model_tier": "standard",
      "inputs": [],
      "outputs": ["test_report"]
    }
  ]
}
```

The following complete cycle relies on automatic project discovery and uses Ruby only to extract values from JSON:

```bash
WORKFLOW_ID=$(kos workflow create --file workflow.json | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("data", "workflow", "id")')

TASK_ID=$(kos task create \
  --workflow-id "$WORKFLOW_ID" \
  --kind feature \
  --title "Add a health check" \
  --description "Implement and test the health check." | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("data", "task", "id")')

CLAIM_ID=$(kos --session agent-1 task claim-next --route | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read).dig("data", "task", "claim_id")')

kos task step show "$TASK_ID"

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

kos --project github.com/owner/repository workflow create --file workflow.json
kos --project github.com/owner/repository workflow list --limit 50
kos --project github.com/owner/repository workflow show 1
kos --project github.com/owner/repository workflow delete 1

kos --project github.com/owner/repository task create \
  --workflow-id 1 \
  --kind feature \
  --title "Add task CRUD" \
  --description "Implement the task endpoints and CLI commands." \
  --group-id 1 \
  --blocked-by-ids 10,11
kos --project github.com/owner/repository task list --limit 50
kos --project github.com/owner/repository task ready --kind feature --group-id 1
kos --project github.com/owner/repository --session agent-1 task claim-next --kind feature --group-id 1
kos --project github.com/owner/repository --session agent-1 task claim-next --route
kos --project github.com/owner/repository --session agent-1 task claim 1
kos --project github.com/owner/repository --session agent-1 task claim 1 --route
kos --project github.com/owner/repository --session agent-1 task current
kos --project github.com/owner/repository --session agent-1 task current --route
kos --project github.com/owner/repository task step show 1
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task advance 1 --expected-step 0
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

Without `--project`, repository-sensitive commands derive the canonical project key from the current Git repository's `origin`. GitHub SSH and HTTPS remotes such as `git@github.com:owner/repository.git` and `https://github.com/owner/repository.git` resolve to `github.com/owner/repository`. Unsupported or absent remotes require explicit `--project`. New tasks start in `planned` at step `0` of their workflow; ordinary create and update commands cannot set status, claim, lease, or step fields. A claim lasts 30 minutes. `claim-next` atomically selects work on the server and returns the session's existing active task before selecting another; `current` reads that task without extending its lease. `renew` extends only a current lease, while `release` and `complete` atomically preserve an optional summary and clear ownership. `complete` requires the final step; `advance` moves to the next step only with the active claim and matching `--expected-step`. At `lease_expires_at <= now`, the old claim loses all write access. `reopen` is explicit and is rejected after dependent work has started or completed.

By default, `task show`, `task current`, and successful `claim`/`claim-next` responses contain the same detailed context: the task and its artifacts, optional group, immediate blockers, blocker artifacts with explicit source metadata, dependent tasks, and computed availability reasons. With `--route`, claim/current return only compact step routing metadata and the owner's `claim_id`, without documents. `task step show ID` returns the instruction, expected outputs, and matching input artifacts with source and version; missing inputs are explicit. Workflow definitions cannot be edited, and deleting an in-use workflow is rejected. Context collections default to 50 records and accept at most 100 through `--context-limit`; an incomplete collection has `pagination.<collection>.complete: false`, its continuation flag in `after_parameter`, and its cursor in `next_after_id`. The CLI supports `--artifact-after-id`, `--blocked-by-after-id`, `--dependency-artifact-after-id`, and `--blocks-after-id` on all four context-returning commands.

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
ruby script/test_install_opencode.rb
```

Run `script/acceptance` from the repository root. It builds and installs the gem into an isolated temporary gem home, starts a temporary Rails/SQLite server, exercises automatic Git project discovery and the main task cycle through the installed `kos` executable, and verifies online backup and offline restore. `bin/ci` runs this acceptance test together with style, security, server tests, CLI tests, and the gem build. The complete mapping from specification section 15 to automated checks is in [`docs/acceptance.md`](docs/acceptance.md).

## Backup And Restore

The workflow migration removes tasks and their artifacts from databases created by the earlier local MVP, because those tasks have no assigned workflow or current step. Back up any records you need before running `bin/rails db:prepare` after upgrading. Projects and groups remain.

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
