# KOS

KOS is a local task tracker for AI agents. The Rails JSON API and `kos` Ruby CLI provide projects, task groups, dependencies, lease-protected work, versioned Markdown artifacts, and server-owned workflow steps.

Approved required user-facing behavior is specified by domain in the [OKF knowledge bundle](docs/knowledge/index.md); code and tests show actual behavior. The agreed MVP scope and baseline contract are in [the MVP specification](docs/mvp-specification.md). Contributions follow the mandatory plan → implement and test → review → check normative documentation → publish to `main` cycle in [AGENTS.md](AGENTS.md). This is a development process, not an automated KOS feature.

## For an agent: install KOS from this repository

If the human gave you only this repository URL, use the following route rather than assuming KOS is already running. Ask for missing consequential decisions in the human's language, one at a time in ordinary chat; a wizard may group questions only when it presents them sequentially. Give the context and a recommendation with a short reason in parentheses for each question, without guessing missing facts. When offering alternatives, number them `1.`, `2.`, ... and ask for a one-digit reply per question. Use plain, understandable language without unnecessary jargon or loanwords in questions, progress updates, blockers and final reports.

1. Check [requirements](#requirements), identify the KOS checkout (clone this repository if needed), the existing CLI on `PATH`, the loopback server and the persistent database in that checkout. Never treat an existing database as disposable test data. For a first installation follow [Server Setup](#server-setup); for an existing installation follow [Updating an existing installation](#updating-an-existing-installation). Do not run `db:prepare` over existing data. Migration of a persistent database and stop/restart of its server require **two separate explicit permissions**, after reviewing the effects and verifying a backup for migration.
2. With a compatible schema, run the seed and verify the shared Brief, Execution and Fix definitions. Install and check the [CLI](#cli-installation), then install and check the [OpenCode integration](#opencode-integration) with `ruby script/install-opencode`. Confirm the CLI used by the agent matches this checkout, the server is reachable only on loopback, shared workflows are visible, and the two executor profiles and required models are available. Report each component's actual result. Ask the human to quit and restart OpenCode to load new skills and commands; that is separate from restarting Rails.
3. Global installation does **not** select a project. For a selected target project, use the [short onboarding route](integrations/opencode/skills/kos-project-onboarding/SKILL.md#short-route) and its [recovery details](integrations/opencode/skills/kos-project-onboarding/SKILL.md#details-and-recovery). Check the account and access on its chosen repository host, real Git `origin`, publication destination and access boundary; reuse an existing verified checkout. Agree separately to prepare a missing repository and to publish its initial commit, then verify the published base before creating or claiming shared Brief v6. Approval of Brief requirements and plan comes later and separately. Add KOS guidance only to **that project's** `AGENTS.md` without overwriting its rules. If no project is selected, finish machine setup and report that onboarding remains. Do not edit other projects or a global AGENTS.md.
4. For subsequent task work, the main agent loads `kos-orchestrator` on an actual KOS request (or the human uses `/kos`). It calls `kos session new` once per independent conversation and reuses the ID; the human need not provide `KOS_SESSION_ID`. Continue recoverable work without routine pauses, verify publication before task completion, and report the user-visible result and next task or precise blocker.

## Requirements

- Docker with Compose and mise for the local Rails server
- Ruby 3.4.10 and Bundler 4.0.20 for the CLI and local development checks
- SQLite 3 for inspecting and backing up the persistent database

Check the installed tools with `ruby --version`, `bundle --version`, and `sqlite3 --version`. If you use mise and `bundle` reports that no version is set for its shim despite Bundler 4.0.20 being installed, run `mise use -g bundler@4.0.20` and check `bundle --version` again. On other Ruby installations, install the required Bundler version with `gem install bundler -v 4.0.20`.

## Server Setup

Get the source and enter the repository (or use your existing checkout):

```bash
git clone https://github.com/atilla777/kos.git
cd kos
```

For a **new installation with no existing development database**, initialize the bind-mounted SQLite store and install the shared workflows:

```bash
KOS_UID=$(id -u) KOS_GID=$(id -g) docker compose run --build --rm kos bin/rails db:prepare
KOS_UID=$(id -u) KOS_GID=$(id -g) docker compose run --rm kos bin/rails db:seed
mise run kos
```

To run `mise run kos` from other projects under your home directory, add this task to `~/mise.toml`, replacing the example path with the absolute path to your KOS checkout (keep any existing tasks in that file):

```toml
[tasks.kos]
description = "Run the local KOS API in Docker until Ctrl+C"
dir = "/absolute/path/to/kos"
run = "KOS_UID=$(id -u) KOS_GID=$(id -g) docker compose up --build --force-recreate"
```

The repository's `.mise.toml` also provides the task when running from the checkout. The home task sets the Compose working directory to the KOS checkout regardless of which project under your home directory you start it from. `mise run kos` builds the image and runs Compose **in the foreground**. Keep that terminal open while using KOS; Ctrl+C stops the container. It does not start automatically at login. Docker must be available to your user. For local Rails development and `bin/ci`, install host dependencies separately with `bundle config set --local path vendor/bundle`, `bundle install`, and `bundle check`.

If the CLI reports `connection_error` with a refusal at `http://127.0.0.1:3137`, check that the existing local server is running; start it with `mise run kos` in a terminal. Do not initialize or replace the SQLite database to resolve a connection refusal. Timeouts, malformed responses and custom API URLs do not receive this start hint; inspect the actual error and configured address instead.

For an **existing installation**, inspect `storage/development.sqlite3` before running `db:prepare`, upgrading, or restoring anything. The file is persistent, not disposable test data. For example, from the repository root:

```bash
sqlite3 'file:storage/development.sqlite3?mode=ro' '.tables'
sqlite3 'file:storage/development.sqlite3?mode=ro' 'SELECT version FROM schema_migrations ORDER BY version;'
sqlite3 'file:storage/development.sqlite3?mode=ro' 'SELECT COUNT(*) FROM projects;'
```

If the file contains data, preserve it before any migration: review the pending migrations and [make an online backup](#backup-and-restore). In particular, upgrading a database from before the workflow migration can remove its earlier tasks and artifacts. Do not run `db:prepare` on that database until you have reviewed the effect and backed up what you need. For an up-to-date database, start the server without a migration. If the file is missing, use the new-installation instructions above. Never use the test database as the persistent store.

With a compatible existing database, `KOS_UID=$(id -u) KOS_GID=$(id -g) docker compose run --rm kos bin/rails db:seed` installs missing shared workflow definitions and is idempotent when definitions match. It installs current v6 editions alongside used v1/v2/v3/v4/v5 editions without changing assigned tasks, and removes only unused prior editions. It may replace a **current unused** shared definition with changed steps; if a differing current definition is already used by a task, the seed stops without changing any definitions. Run it only after checking the database and, when needed, obtaining separate approval for migration and restart as described below.

The later global-workflow migration preserves existing project workflows, tasks, dependencies, and artifacts. It switches Rails schema dumps to `db/structure.sql` so SQLite ownership triggers also survive a fresh database load. The new migration still requires the existing-installation backup and separate migration/restart approvals described below.

### Ready-to-use workflows

`bin/rails db:seed` installs the current shared definitions **KOS Brief v6**, **KOS Execution v6**, and **KOS Fix v6** for every project. List them with `kos --project github.com/owner/repository workflow list`, then supply the chosen current workflow's ID to `kos task create --workflow-id ID`. Do not silently choose an older edition if v6 is missing. Creating a task with an available shared workflow atomically registers a missing project; reads do not. A task type (`kind`) does not select a workflow automatically. Current definitions are derived by `db/seeds.rb` from the unchanged `config/workflows/*-v3.json`; earlier definitions remain for reference. Used old definitions remain in the database for existing tasks, unused old ones are removed, and a differing used current definition causes a safe stop. Existing tasks keep their assigned steps.

Brief is a conversation with the **main agent**: discuss and obtain human agreement on high-level decisions and plan before creating artifacts, a group, or tasks. After agreement it saves `requirements`, `specification`, `implementation_plan`, and `planning_report`, creates one or more planned Execution tasks (and for an epic, a group) with explicit dependencies on Brief, then completes. Each execution task refines its own design. Execution and Fix proceed without unnecessary pauses: advanced planning, advanced implementation/testing, an independent advanced review repeated until findings are resolved, standard documentation, and standard publication. Fix begins with a diagnosis based on its description, without needing a Brief. Publication belongs to the assigned step under the target project's rules; its executor verifies the destination and writes `publication_report`, then the main agent independently verifies it before calling `complete`. See [ready workflow scenarios](docs/knowledge/features/ready-workflows.md).

Brief v6 publishes an approved **normative specification** in the target repository before completing and unblocking Execution v6. Earlier tasks retain their assigned editions. Each KOS project keeps its required user-facing behavior as domain-organized OKF v0.2 concepts in `docs/` or a project-selected subdirectory of `docs/`. The documents say what should be true independently of implementation status; code and tests show what actually works, and KOS tasks/results track progress. Before writing Brief results, the main agent separates approved behavior from proposals, unanswered questions and technical choices, clarifies publication and access boundaries, and seeks explicit approval of both required behavior and the high-level plan. The project document contains full approved scenarios; KOS preserves a compact self-contained snapshot with source path, verifiable revision, boundaries and open questions. The agent loads `kos-project-docs`, records concrete documentation review findings or their absence, verifies publication at the project-defined destination and saves the reference in `publication_report`. People or agents may prepare specifications outside KOS, but new or changed requirements require explicit human agreement in every case. Meaningful requirements, criteria, decisions and consecutively numbered questions may be linked across tasks with IDs based on the project and Brief task ID (for example `shop-task-42/AC-01`). Execution and Fix planning preserve their own question numbering and map criteria to checks. Independent review classifies findings as high, medium or low; high and medium findings must be fixed and re-reviewed. There is no automatic artifact-to-file sync.

New Execution/Fix v6 reports identify the Git base and uncommitted change set checked before and after corrections, preserve a concise self-contained account of previous evidence and findings when overwritten, and record changed files, affected reruns, results and the reason full CI was or was not repeated. A previous `lock_version` is not a readable history. For untrusted-input findings check applicable neighboring forms and a subsequent valid request. An independent reviewer inspects the complete resulting diff after high/medium corrections; an unchanged full CI need not be rerun solely to review it. Before publication verify that earlier evidence still covers the final files and follow any mandatory project checks. To display one template without printing all step inputs into an agent tool result, filter the JSON locally: `kos --project KEY task step show ID | jq -r '.data.step.templates.test_report'` (requires `jq`; substitute the output key). This still downloads the full packet from the server.

For a Brief's approved task breakdown, `kos --session SESSION --claim-fingerprint HASH task plan create BRIEF_ID --key KEY --file tasks.json --expected-step N` creates all dependent tasks together. The file is a JSON array; for example `[{"name":"api","kind":"feature","title":"Build API","description":"Deliver API.","workflow_id":18},{"name":"client","kind":"feature","title":"Build client","description":"Deliver client.","workflow_id":18,"blocked_by":["api"]}]`. Use real verified workflow IDs, not these example values. An optional `task_group_id` refers to an existing group. Every created task also depends on the Brief. Only one plan is accepted per Brief: the same key and content return the same IDs, while a changed request conflicts. If the response is lost, `kos task plan show BRIEF_ID KEY` reads the saved map without a claim. Creating or repeating a plan requires the active Brief claim and the same step; record the criteria-to-task map separately in `planning_report`. The ordinary `task create` remains available.

The container publishes the API only on `http://127.0.0.1:3137`. Its internal listener is reachable through Docker, but Compose binds the host port to loopback only. The persistent database remains `storage/development.sqlite3` on the host; the whole `storage/` directory is mounted so SQLite WAL/SHM files remain with it. Keep the database out of images and never run a host Rails server against it at the same time. In another terminal, check the listener and API:

```bash
ss -ltn '( sport = :3137 )'  # 127.0.0.1:3137 only
curl --noproxy '*' -i http://127.0.0.1:3137/api/v1/projects
```

An empty `projects` array with HTTP 200 is a healthy server, not an automatically registered KOS development project. Reads do not create projects; register a project explicitly or create its first workflow before expecting `kos task ready` to return work.

### Switching from the former user service

If `kos.service` is still active, verify which checkout and database it uses, inspect the database and create a verified online backup before changing it. After the container image and existing schema are checked, obtain explicit permission to stop and disable the old service, then run `systemctl --user disable --now kos.service` before using `mise run kos` against its database. Do not let both servers write to the same SQLite store. A stopped container can be removed with `docker compose down` without deleting the host database; do not pass `-v` or delete `storage/`.

The API is under `/api/v1`. Successful responses use a `data` object; errors use an `error` object with a stable `code` and `message`. Project, task-group, task, and workflow lists default to 50 records, accept at most 100, and return `pagination.next_after_id` for continuation. Project-scoped operations require the canonical repository key in `project`; creating a group or project workflow atomically creates a missing project, while reads never do. A global workflow is created with `global: true` and no `project`, and is visible in any project's workflow list. A task must reference either a global workflow or a workflow of its own project. Group progress is computed from its tasks, and nonempty groups cannot be deleted.

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

The CLI uses `http://127.0.0.1:3137` by default. Set `KOS_API_URL` or pass `--url URL` before the resource name to select another local endpoint. Set `KOS_PROJECT` or pass `--project REPOSITORY` to select a project explicitly. `kos session new` prints `{ "data": { "session_id": "..." } }` locally, without Git or a server; obtain one ID for each independent working conversation and reuse it through `--session SESSION` or `KOS_SESSION_ID` for all its claim/current calls. Existing callers can continue supplying their own ID. Protected writes accept the server-issued claim through `KOS_CLAIM_ID` or `--claim CLAIM`; avoid exposing claim values in logs or shared shell history. Command-line options override environment variables.

## OpenCode Integration

The integration ships eight skills (`kos-setup`, `kos-orchestrator`, `kos-executor`, `kos-git`, `kos-github-cli`, `kos-project-docs`, `kos-project-onboarding`, `kos-task-worktree`), two subagent profiles (`kos-standard`, `kos-advanced`), and five global commands (`/kos-init` for setup/checks, `/kos-update` for a safe update, `/kos` for general task work, `/kos-brief` to start or resume a Brief, and `/kos-fix` to start or resume a Fix). The three task commands are optional shortcuts to the existing orchestrator in Build and accept additional instructions after the command name. From the KOS checkout, after installing the server and CLI as above:

```bash
ruby script/install-opencode
opencode models openai
opencode agent list
```

The installer copies only KOS files to `~/.config/opencode/` (or `$XDG_CONFIG_HOME/opencode/`), preserving other global settings. On update, it replaces a file only if its contents match a version of that file in the checkout's Git history. A modified file, symlink, or unknown version stops the whole preflight before copying; inspect the conflict and resolve it explicitly instead of deleting your changes. To check the installed files without changing them, run `ruby script/install-opencode --check` from the intended checkout. A missing or differing file means the installation needs inspection and possibly a safe update; matching files do not establish what an already-running OpenCode session loaded. The old `agent/kos-orchestrator.md` profile and earlier standalone `project-onboarding.md` and `task-worktree.md` files are not removed automatically; the new skills do not read them. OpenCode loads configuration at startup: **quit and restart OpenCode** after installing or updating commands, agents or skills, even when `--check` passes. Confirm `openai/gpt-6-luna` and `openai/gpt-6-sol` are available from your OpenAI provider, both executor agents appear in `opencode agent list`, and `opencode debug skill` in a fresh process lists `kos-orchestrator`, `kos-executor`, `kos-git`, `kos-github-cli`, `kos-project-docs`, `kos-project-onboarding` and `kos-task-worktree`. In the new Build session, `/kos`, `/kos-brief` and `/kos-fix` load `kos-orchestrator`; the `kos-executor` skill is available to delegated executors. A shell's `opencode agent list` does not reload an already-running interactive session. The `kos-setup` skill also onboards an explicitly selected target project by updating **its** `AGENTS.md` according to [project onboarding](integrations/opencode/skills/kos-project-onboarding/SKILL.md); installing global files does not change arbitrary project repositories.

For an explicit Git request, load `kos-git`; for an explicit GitHub request involving PRs, checks or other GitHub operations, load `kos-github-cli`. A normal request to edit code does not itself call for these skills. They provide common check → action → verify examples and direct the agent to the installed `git help` / `git <command> --help` or `gh help` / `gh <command> --help` for other commands. They respect the active project's instructions and the user's publication request; the project determines whether publication uses a local merge or a PR. The KOS orchestrator loads [the task worktree skill](integrations/opencode/skills/kos-task-worktree/SKILL.md) for explicitly identified development tasks; no Git commands are added to the KOS server or CLI.

For an approved normative specification or a documentation-check step, explicitly name `kos-project-docs` in workflow instructions, as the shared workflows do. The main agent or executor reads the step packet and loads the skill; a person may also request specification work outside KOS. Keep domain concepts and navigation in an OKF v0.2 bundle inside `docs/`; default to `docs/` itself or use a selected subdirectory such as `docs/knowledge/`. Brief publishes the approved norm before unblocking work. Execution and Fix planning inspect it and obtain explicit human approval for any new or changed requirement before implementing that change. At the documentation step, check affected concepts; if the norm is unchanged, report which were inspected and why no edit is needed. Separate documentation of actual implementation is not required. Resolve conflicting or prohibitive project rules with the human. Project files are reviewed and published according to the target project's rules; KOS artifacts remain separate.

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

Once the schema is compatible (after an approved migration if needed), run `KOS_UID=$(id -u) KOS_GID=$(id -g) docker compose run --build --rm kos bin/rails db:seed` and verify the shared definitions; do not run it against an old schema. After an approved restart with `mise run kos`, verify loopback binding, the API response, installed CLI, and OpenCode in a new session. An update is complete only when all intended components pass these checks. If a step fails, state the last successful step and safe next action; do not report success based on a successful fetch or file copy alone.

## Working with OpenCode

In the target Git repository, ask the main agent naturally to discuss a Brief, create a KOS task or resume KOS work. It loads `kos-orchestrator` for an actual KOS request; mentioning KOS in passing does not authorize a claim. In Plan, it may discuss and agree on a Brief and read data without writing. After agreement, switch to Build for claims, artifacts, tasks or other writes, preserving the agreed decisions. In Build, `/kos` is the general shortcut; `/kos-brief describe the goal` starts or resumes a Brief and `/kos-fix describe the bug` starts or resumes a Fix without requiring a preceding Brief. Both pass the trailing text to the orchestrator and obey its agreement and recovery rules. The agent calls `kos session new` once for a new working conversation, keeps the returned ID in its conversation context and supplies it via `--session SESSION` for subsequent commands. On continuation of the **same** conversation it reuses that ID, checks `current --fingerprint` against the project, task and step, and does not claim again. No manual `KOS_SESSION_ID` or skill name is required from the user. Use `--project` if Git `origin` cannot identify the project; use `KOS_API_URL` for a nondefault loopback port. Independent concurrent agents must not share an ID.

In a **new** conversation resuming earlier work, inspect the intended task with `task list` / `task show ID` and disambiguate if needed. A live lease can be recovered with its previous `session_id` only after the human explicitly confirms the previous agent is stopped; check `current --fingerprint`, project, task, step, lease and existing worktree before continuing. Without that confirmation wait for expiry or release from the old conversation. After expiry, generate a new ID and reclaim the available task, obtaining a new fingerprint while preserving the step, artifacts and verified worktree. If it was completed or another owner now holds it, do not write with the old fingerprint. KOS cannot prove an agent stopped modifying files. On an ambiguous network result or conflict, inspect `current`, task and artifacts before retrying.

An active claim belongs to the whole task: use `kos --session SESSION task current --fingerprint` or `kos --session SESSION task claim-next --fingerprint` to obtain a compact route without printing the claim. Delegate only its fingerprint, task ID, step position, project and session ID to the executor. The executor independently calls `kos task step show TASK_ID` and writes results using `kos --session SESSION --claim-fingerprint HASH task artifact put TASK_ID KEY --file PATH --expected-step N`; the CLI retrieves the actual token in memory and the server still validates it. The orchestrator verifies and explicitly advances or completes using the same fingerprint mode. The workflow author chooses the tier for each step: focused documentation or publication may be `standard`, while work needing more judgment may be `advanced`. For an explicitly assigned publication step, the executor follows the project's rules; the main agent verifies its result before completing the task.

For a development task, the orchestrator prepares or recovers a task worktree before changing files and gives its absolute path to the executor; both work there. Project rules govern naming and publication. Without naming rules, the branch and sibling worktree use the **target repository's** short name and task ID, e.g. `shop/task-42` and `shop-task-42` for task 42 in `shop`, never a fixed `kos` prefix. A failed publication or dirty checkout is retained for recovery. Only after confirmed publication according to that project's rules and a clean status is the worktree removed without force. See [the worktree skill](integrations/opencode/skills/kos-task-worktree/SKILL.md) and [user scenarios](docs/knowledge/features/opencode-integration.md).

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
kos session new
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
kos workflow create --global --file workflow.json
kos --project github.com/owner/repository workflow list --limit 50
kos --project github.com/owner/repository workflow list --brief
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
kos --project github.com/owner/repository task step show 1 --brief
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task advance 1 --expected-step 0
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task renew 1
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task update 1 --work-summary "Implementation in progress."
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task release 1 --work-summary "Paused safely."
kos --project github.com/owner/repository --claim "$KOS_CLAIM_ID" task complete 1 --work-summary "Implemented and verified."
kos --project github.com/owner/repository task reopen 1
kos --project github.com/owner/repository task show 1
kos --project github.com/owner/repository task show 1 --brief
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

Without `--project`, repository-sensitive commands derive the canonical project key from the current Git repository's `origin`. GitHub SSH and HTTPS remotes such as `git@github.com:owner/repository.git` and `https://github.com/owner/repository.git` resolve to `github.com/owner/repository`. Unsupported or absent remotes require explicit `--project`. New tasks start in `planned` at step `0` of their workflow; ordinary create and update commands cannot set status, claim, lease, or step fields. A new claim lasts one hour. `claim-next` atomically selects work on the server and returns the session's existing active task before selecting another; `current` reads that task without extending its lease. `renew` extends only a current lease for one hour from renewal, while `release` and `complete` atomically preserve an optional summary and clear ownership. Existing lease deadlines are not changed by a server update. `complete` requires the final step; `advance` moves to the next step only with the active claim and matching `--expected-step`. At `lease_expires_at <= now`, the old claim loses all write access. `reopen` is explicit and is rejected after dependent work has started or completed.

By default, `task show`, `task current`, and successful `claim`/`claim-next` responses contain the same detailed context: the task and its artifacts, optional group, immediate blockers, blocker artifacts with explicit source metadata, dependent tasks, and computed availability reasons. With `--route`, claim/current return only compact step routing metadata and the owner's `claim_id`, without documents. `task step show ID` returns the instruction, expected outputs, and matching input artifacts with source and version; missing inputs are explicit. Workflow definitions cannot be edited, and deleting an in-use workflow is rejected. Context collections default to 50 records and accept at most 100 through `--context-limit`; an incomplete collection has `pagination.<collection>.complete: false`, its continuation flag in `after_parameter`, and its cursor in `next_after_id`. The CLI supports `--artifact-after-id`, `--blocked-by-after-id`, `--dependency-artifact-after-id`, and `--blocks-after-id` on all four context-returning commands.

Opt-in `--brief` on `workflow list`, `task show ID`, and `task step show ID` asks the API for metadata without long workflow definitions or document contents; the step instruction stays visible. The list and task cursors still work, and every matching step input still includes its source and version or an explicit missing marker. `task artifact put ... --brief` confirms the ID, key and new version without repeating the submitted content; the normal response remains full. `kos --help`, `kos task artifact --help`, and `kos task artifact put 1 --help` return JSON help without Git, a server or required arguments.

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
