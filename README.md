# KOS

KOS is a local task tracker for AI agents. The Rails JSON API and `kos` Ruby CLI provide projects, task groups, dependencies, lease-protected work, versioned Markdown artifacts, and server-owned workflow steps.

Current user-facing behavior and scenarios are documented in the [OKF knowledge bundle](docs/knowledge/index.md). The agreed MVP scope and baseline contract are in [the MVP specification](docs/mvp-specification.md). Contributions follow the mandatory plan → implement and test → review → update user-facing documentation → publish to `main` cycle in [AGENTS.md](AGENTS.md). This is a development process, not an automated KOS feature.

## Requirements

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3

Check the installed tools with `ruby --version`, `bundle --version`, and `sqlite3 --version`. If you use mise and `bundle` reports that no version is set for its shim despite Bundler 4.0.20 being installed, run `mise use -g bundler@4.0.20` and check `bundle --version` again. On other Ruby installations, install the required Bundler version with `gem install bundler -v 4.0.20`.

## Server Setup

Get the source and enter the repository:

```bash
git clone https://github.com/atilla777/kos.git
cd kos
```

```bash
bundle config set --local path vendor/bundle
bundle install
bundle check
```

For a **new installation with no existing development database**, initialize it and start the server:

```bash
bin/rails db:prepare
bin/rails server -b 127.0.0.1 -p 3000
```

For an **existing installation**, inspect `storage/development.sqlite3` before running `db:prepare`, upgrading, or restoring anything. The file is persistent, not disposable test data. For example, from the repository root:

```bash
sqlite3 'file:storage/development.sqlite3?mode=ro' '.tables'
sqlite3 'file:storage/development.sqlite3?mode=ro' 'SELECT version FROM schema_migrations ORDER BY version;'
sqlite3 'file:storage/development.sqlite3?mode=ro' 'SELECT COUNT(*) FROM projects;'
```

If the file contains data, preserve it before any migration: review the pending migrations and [make an online backup](#backup-and-restore). In particular, upgrading a database from before the workflow migration can remove its earlier tasks and artifacts. Do not run `db:prepare` on that database until you have reviewed the effect and backed up what you need. For an up-to-date database, start the server without a migration. If the file is missing, use the new-installation instructions above. Never use the test database as the persistent store.

The server listens only on `http://127.0.0.1:3000`; `PORT` changes the port while retaining loopback-only binding. The persistent development database is `storage/development.sqlite3`. In another terminal, check the listener and API:

```bash
ss -ltn '( sport = :3000 )'  # 127.0.0.1:3000 only
curl --noproxy '*' -i http://127.0.0.1:3000/api/v1/projects
```

An empty `projects` array with HTTP 200 is a healthy server, not an automatically registered KOS development project. Reads do not create projects; register a project explicitly or create its first workflow before expecting `kos task ready` to return work.

### Optional daily startup with systemd (Linux + mise)

If you want the local server started at user login, create `~/.config/systemd/user/kos.service` with the **absolute path to your own checkout** in `WorkingDirectory`:

```ini
[Unit]
Description=KOS local Rails API

[Service]
Type=simple
WorkingDirectory=/absolute/path/to/kos
ExecStart=/usr/bin/mise exec bundler@4.0.20 -- bin/rails server -b 127.0.0.1 -p 3000
Restart=on-failure

[Install]
WantedBy=default.target
```

This example assumes `mise` is at `/usr/bin/mise` and Bundler and the Rails dependencies were installed as above; adjust the path if necessary (`command -v mise`). Start only one server on the port. After creating the unit, run `systemctl --user daemon-reload` and `systemctl --user enable --now kos.service`. Check `systemctl --user status kos.service` and the loopback/API commands above; stop it with `systemctl --user stop kos.service`. This user service starts with the user's systemd manager, ordinarily at login; boot-time startup without login is not implied. To use the manual server instead, stop the user service first.

The API is under `/api/v1`. Successful responses use a `data` object; errors use an `error` object with a stable `code` and `message`. Project, task-group, task, and workflow lists default to 50 records, accept at most 100, and return `pagination.next_after_id` for continuation. Group, workflow, and task operations require the canonical repository key in `project`; creating a group or workflow atomically creates a missing project, while reads never do. A task must reference an existing workflow in its project. Group progress is computed from its tasks, and nonempty groups cannot be deleted.

## CLI Installation

Build and install the gem from the repository into your user environment without writing the built gem into the checkout:

```bash
cd cli
gem build kos-cli.gemspec --output /tmp/kos-cli.gem
mkdir -p "$HOME/.local/bin"
gem install --user-install --bindir "$HOME/.local/bin" --no-document /tmp/kos-cli.gem
command -v kos
kos --help
```

Ensure `$HOME/.local/bin` is in your shell's `PATH` (including new OpenCode sessions); `command -v kos` should resolve to `$HOME/.local/bin/kos` rather than an older installation. If it does not, add that directory to your shell's startup configuration and open a new shell. Rebuild and reinstall after changing the CLI source. The gem version alone does not identify the checkout revision: reinstall with `--force` when updating, then compare installed files as described below. `kos project list --limit 50` checks the installed CLI against the running API without creating records.

The CLI uses `http://127.0.0.1:3000` by default. Set `KOS_API_URL` or pass `--url URL` before the resource name to select another local endpoint. Set `KOS_PROJECT` or pass `--project REPOSITORY` to select a project explicitly. Claim operations require a stable session identity through `KOS_SESSION_ID` or `--session SESSION`. Protected writes accept the server-issued claim through `KOS_CLAIM_ID` or `--claim CLAIM`; avoid exposing claim values in logs or shared shell history. Command-line options override environment variables.

## OpenCode Integration

The integration ships five skills (`kos-setup`, `kos-orchestrator`, `kos-executor`, `kos-git`, `kos-github-cli`), two subagent profiles (`kos-standard`, `kos-advanced`), and three global commands (`/kos-init` for setup/checks, `/kos-update` for a safe update, `/kos` for the existing orchestrator in Build). From the KOS checkout, after installing the server and CLI as above:

```bash
ruby script/install-opencode
opencode models openai
opencode agent list
```

The installer copies only KOS files to `~/.config/opencode/` (or `$XDG_CONFIG_HOME/opencode/`), preserving other global settings. On update, it replaces a file only if its contents match a version of that file in the checkout's Git history. A modified file, symlink, or unknown version stops the whole preflight before copying; inspect the conflict and resolve it explicitly instead of deleting your changes. The old `agent/kos-orchestrator.md` profile from an earlier version is not removed automatically; inspect and remove it yourself if present. OpenCode loads configuration at startup: **quit and restart OpenCode** after installing or updating commands, agents or skills. Confirm `openai/gpt-6-luna` and `openai/gpt-6-sol` are available from your OpenAI provider, both executor agents appear in `opencode agent list`, and `opencode debug skill` lists `kos-git` and `kos-github-cli`. In the new Build session, `/kos` loads `kos-orchestrator`; the `kos-executor` skill is available to delegated executors. A shell's `opencode agent list` does not reload an already-running interactive session.

For an explicit Git request, load `kos-git`; for an explicit GitHub request involving PRs, checks or other GitHub operations, load `kos-github-cli`. A normal request to edit code does not itself call for these skills. They provide common check → action → verify examples and direct the agent to the installed `git help` / `git <command> --help` or `gh help` / `gh <command> --help` for other commands. They respect the active project's instructions and the user's publication request; the project determines whether publication uses a local merge or a PR. They do not create task worktrees or add Git commands to the KOS server or CLI.

## Updating an existing installation

Use `/kos-update` in a current OpenCode session or follow these instructions with the agent. If the command is not installed yet, ask Build to load `kos-setup` and follow this section. `/kos-init` is for first installation and checks; it does not authorize migration of an existing database. Identify the existing KOS checkout and the service that uses it **before** changing files. Check for an existing `storage/development.sqlite3` and inspect its schema as in [Server Setup](#server-setup). Record the current checkout revision (`git rev-parse HEAD`), CLI executable (`command -v kos`), whether the loopback server is running, and how it is started. Never substitute a new checkout or a test database for the persistent store by accident.

### Fetch and install files

Confirm that `origin` is the intended GitHub KOS repository (`github.com/atilla777/kos`); do not print embedded credentials in remote URLs. Work on `main` only. Stop and ask the user to resolve any tracked or untracked changes, local commits, divergent history, unexpected origin, or different branch; do not stash, reset, switch branches, merge non-fast-forward, or overwrite files to make the update succeed. From the checkout:

```bash
git status --porcelain --untracked-files=all
git branch --show-current
git fetch origin main
git rev-list --count origin/main..HEAD
git merge-base --is-ancestor HEAD origin/main
git merge --ff-only origin/main
git rev-parse HEAD
bundle install
bundle check
```

The first command must be empty, the branch must be `main`, the count must be `0`, and `merge-base` must succeed **before** running `git merge --ff-only`. If fetch fails (network, authorization), stop without using stale `origin/main`. If dependency installation fails, report the resulting revision and fix the dependency issue before continuing; do not claim the update is finished. Do not run `bin/rails db:prepare` as part of updating files.

Build and install the CLI from this revision as in [CLI Installation](#cli-installation), using `gem install --user-install --bindir "$HOME/.local/bin" --no-document --force /tmp/kos-cli.gem` on update. Check `command -v kos` resolves to that user installation. The version string may not change across revisions; compare the installed gem's executable and library contents with the checkout instead of trusting its version alone:

```bash
ruby -rrubygems -e 's=Gem::Specification.find_by_name("kos-cli"); files=Dir["cli/{exe,lib}/**/*"].select { |f| File.file?(f) }; abort "CLI files differ" unless files.all? { |f| p=f.delete_prefix("cli/"); File.file?(File.join(s.full_gem_path,p)) && File.binread(f)==File.binread(File.join(s.full_gem_path,p)) }; puts "CLI matches checkout"'
ruby script/install-opencode
```

The comparison must run from the checkout root using the same Ruby environment as `kos`. After the OpenCode installer succeeds, compare its KOS destinations with the source and start a **new OpenCode session** to see the commands and agents. If installation stops on a conflicting destination, inspect its diff and preserve it until its owner decides how to resolve it; other destinations are not changed by that installer attempt. Check `kos project list --limit 50` against the server **only after** checking server/schema compatibility. A running server can still be on the old code even if the checkout and CLI are new; report that state explicitly.

### Database and server: two separate approvals

Inspect the existing database read-only and compare `schema_migrations` with `db/migrate/` before proposing any migration. Show the user which migrations are pending and their data effects (the workflow migration can remove earlier tasks and artifacts). If a migration is needed, create a uniquely named backup **outside the checkout** with SQLite's online `.backup` while the old server is still available; confirm the backup exists and returns `ok` from `PRAGMA integrity_check`, and check that the expected tables and record counts are present. A failed backup means stop. Present the migration plan and obtain explicit permission to migrate **this database**; an update request or permission to install files is not enough.

Separately, show how the currently running server would be stopped and started (manual process or user service) and obtain explicit permission to stop/restart **that server**. When a migration requires a stop, request both permissions before stopping it; then stop the server, migrate only the backed-up database with `bin/rails db:migrate`, and restart only under the separately approved plan. If either permission is refused, leave the database and running process alone and report which components are updated and which are not. If migration fails, do not restart against a possibly inconsistent schema; inspect the error and backup. Restore only after another explicit decision, with the server stopped; do not automatically restore and then rerun `db:prepare`.

After an approved restart, verify loopback binding, the API response, installed CLI, and OpenCode in a new session. An update is complete only when all intended components pass these checks. If a step fails, state the last successful step and safe next action; do not report success based on a successful fetch or file copy alone.

## Working with OpenCode

In the target Git repository, ask the current main agent in Build to load the `kos-orchestrator` skill and work on the next KOS task. Before claiming work, set a stable `KOS_SESSION_ID` unique to this OpenCode session (for example, its OpenCode session ID). Use `KOS_PROJECT` if the Git `origin` cannot identify the project; use `KOS_API_URL` for a nondefault loopback port. Do not reuse a session ID for independent concurrent agents. An active claim belongs to the whole task: use `kos task current --fingerprint` or `kos task claim-next --fingerprint` to obtain a compact route without printing the claim. Delegate only its fingerprint, task ID, step position, project and session ID to the executor. The executor independently calls `kos task step show TASK_ID` and writes results using `kos --session SESSION --claim-fingerprint HASH task artifact put TASK_ID KEY --file PATH --expected-step N`; the CLI retrieves the actual token in memory and the server still validates it. The orchestrator verifies and explicitly advances or completes using the same fingerprint mode. The workflow author chooses the tier for each step: focused documentation or simple development may be `standard`, while work needing more judgment may be `advanced`. Project instructions govern any publication by the main agent.

If work takes longer than the 30-minute lease, the orchestrator explicitly renews it. On a conflict or ambiguous write, inspect the current route or artifact before retrying. Normal CLI claim commands still expose the token to their caller; agents should use `--fingerprint` and avoid reading or printing full claims through tools. The fingerprint is not an access-control credential against untrusted local processes. OpenCode profiles provide instructions, not server-side validation of the model, instruction quality, tests, or Git state. See [the user scenarios](docs/knowledge/features/opencode-integration.md) for normal and recovery flows.

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
