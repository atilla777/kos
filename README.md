# KOS

KOS is a small task state and coordination service for AI agents. This
repository contains the Rails state service, its authenticated JSON API, the
five core domain tables and models, an idempotent built-in task catalog,
workflow validation, task graph invariants, atomic task lifecycle operations, a thin HTTP command-line client, and
distributable OpenCode orchestration, workflow-step, Git, and OKF
product-specification skills.
Persisted tasks retain their project and workflow and are cancelled rather than
physically deleted. Isolated integration scenarios verify restart and
lost-response recovery, parallel worktrees, moved-base review repetition, and
interrupted publication without duplicate commits.
A single real OpenCode `/kos` invocation has been validated end to end.

## Prerequisites

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3 and its development headers

Install Bundler if it is not already available:

```sh
gem install bundler --version 4.0.20
```

Set a non-empty API bearer token before running KOS outside the test
environment:

```sh
export KOS_API_TOKEN="$(openssl rand -hex 32)"
```

Keep this value secret. Future application endpoints inherit bearer-token
authentication from `ApplicationController`; send the token as
`Authorization: Bearer <token>`. The readiness endpoint `GET /up` remains
public.

By default, development and production SQLite files live under
`$XDG_DATA_HOME/kos`, or `~/.local/share/kos` when `XDG_DATA_HOME` is unset.
Set `KOS_DATA_HOME` to override that directory. It must be on a local disk, not
in a synchronized or network-mounted directory. `KOS_DATA_HOME` must be an
absolute path outside the checkout; relative `XDG_DATA_HOME` values are ignored
as required by the XDG specification. Tests always use `tmp/test.sqlite3` and
ignore these data-directory variables.

Task ownership leases last six hours by default. Set `KOS_LEASE_SECONDS` to a
positive integer to use another duration.

## Deploy With An Agent

An installation agent should perform this complete procedure from one fixed Git
tag. The Rails service, installed CLI gem, command, skills, and agent profiles
must all come from that same revision.

Fetch the selected release and install the server dependencies:

```sh
git fetch --tags
git checkout <release-tag>
bin/setup --skip-server
```

Build and install the CLI with standard RubyGems commands. Build outside the
checkout so the package is not mistaken for project state:

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
kos --version
kos --help
```

Resolve and retain the absolute installed executable path. The orchestrator
does not fall back to an ambient executable:

```sh
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
```

Install the OpenCode integration globally from the same checkout:

```sh
mkdir -p ~/.config/opencode/commands ~/.config/opencode/agents ~/.config/opencode/skills
rm -f ~/.config/opencode/agents/kos-step.md
cp .opencode/commands/kos.md ~/.config/opencode/commands/kos.md
cp .opencode/agents/kos-*.md ~/.config/opencode/agents/
cp -R skills/kos skills/kos-step skills/kos-git skills/okf ~/.config/opencode/skills/
```

The shipped model mapping is:

```text
standard = openai/gpt-5.4-mini
advanced = openai/gpt-5.6-sol
```

An administrator may change the concrete `model:` values in the installed
agent profiles while preserving their standard or advanced role. Run
`opencode models` first and use complete `provider/model-id` values. When
`KOS_DATA_HOME` or `XDG_DATA_HOME` changes the default data path, replace the
review profile's two `~/.local/share/kos/tasks/*/` edit permissions with the
absolute configured `<kos-data-home>/tasks/*/` paths; keep every other edit
denied.

Configure the service, prepare its database, and start Rails:

```sh
export KOS_API_TOKEN="$(openssl rand -hex 32)"
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails db:prepare
bin/rails server
```

Database preparation automatically installs the built-in `brief`,
`development`, and `fix` task types and their canonical workflows. Use the
administrative CLI commands below only to register the project and any custom
workflows or task types. Custom task types require a stable `--key`; the three
built-in keys are reserved. Then expose the trusted installation context to the
OpenCode process:

```sh
export KOS_PROJECT_ID="<registered-project-id>"
export KOS_PROJECT_REMOTE_URL="<registered-project-remote-url>"
export KOS_PROJECT_DEFAULT_BRANCH="<registered-default-branch>"
export KOS_TASK_TYPE_ID="<registered-task-type-id>"
```

Restart OpenCode after installation or model changes, verify `GET /up`, and run
one real `/kos` task before treating the installation as ready.

To update KOS, stop the service and active orchestrators, check out the new tag,
repeat `gem build` and `gem install`, update the copied OpenCode files from that
tag, run `bin/rails db:prepare` and `bin/rails db:seed`, and restart Rails and
OpenCode. The idempotent seed installs new canonical workflow revisions and
repoints only built-in task types; existing tasks keep their snapshotted
workflow. Never mix the CLI or skills from different KOS revisions.

When developing KOS, prepare the empty test database explicitly:

```sh
RAILS_ENV=test bin/rails db:prepare
```

## Run

Start the API server:

```sh
bin/rails server
```

The readiness endpoint is available at `http://127.0.0.1:3000/up`.

## API

All application endpoints accept JSON and require the configured bearer token.
`GET /up` is the only public endpoint.

```text
POST  /projects
POST  /workflows
POST  /task_types
PATCH /task_types/:id
POST  /tasks
POST  /tasks/create-and-claim
GET   /tasks/:id
PATCH /tasks/:id
GET   /tasks/show-owned
GET   /tasks/resumable
POST  /tasks/claim-next
POST  /tasks/:id/claim
POST  /tasks/:id/resume
POST  /tasks/:id/report-attempt
POST  /tasks/:id/cancel
POST  /tasks/:id/validate-children
POST  /tasks/:id/materialize-children
GET   /tasks/:id/children
```

Request fields are top-level JSON properties. Task responses contain `task`,
`workflow`, and `step` objects so an agent receives the stored state and the
current instruction in one response. `claim-next` returns `204 No Content` when
no task is available, and `show-owned` does the same when its owner has no task
in the requested project. Task creation accepts exactly one of a stable
`task_type_key` or an administrative numeric `task_type_id`. Known failures use a stable `error` code with status
`400`, `404`, `409`, or `422` as appropriate.

For example:

```sh
curl --request POST http://127.0.0.1:3000/projects \
  --header "Authorization: Bearer $KOS_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"name":"KOS","remote_url":"https://example.test/kos.git","default_branch":"main"}'
```

## CLI

The installed `kos` executable uses `http://127.0.0.1:3000` by default. Set `KOS_API_URL` to use a
different HTTP(S) base URL. Every request requires `KOS_API_TOKEN`:

```sh
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_API_TOKEN="your-server-token"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
```

The `/kos` OpenCode orchestrator also requires administrator-installed project
context. `KOS_PROJECT_ID`, `KOS_PROJECT_REMOTE_URL`, and
`KOS_PROJECT_DEFAULT_BRANCH` identify the registered project without asking an
ordinary user to manage internal IDs. Set `KOS_TASK_TYPE_ID` when `/kos` may
create tasks. These values must match the records registered through the
administrative CLI.
`KOS_CLI_PATH` must be the absolute path to this version's installed CLI; the
orchestrator validates its command inventory and never falls back to an
unqualified `kos` executable.

Display the available resources and actions:

```sh
kos --version
kos --help
```

The CLI exposes every current API operation:

```text
kos project create
kos workflow create
kos task-type create
kos task-type update ID
kos task create
kos task create-and-claim
kos task update ID
kos task show ID
kos task show-owned
kos task claim-next
kos task claim ID
kos task resumable
kos task resume ID
kos task report-attempt ID
kos task cancel ID
kos task validate-children ID
kos task materialize-children ID
kos task children ID
```

Use command help for exact options. Administrative task type creation requires
`--key KEY`; `brief`, `development`, and `fix` cannot be used for custom types.
Task creation accepts exactly one of `--task-type-key KEY` or
`--task-type-id ID`. `claim-next` optionally filters by one
`--task-type-key KEY`; `resumable` requires one.
Brief child graph commands read a JSON object containing `children` from
`--definition-file FILE`. Each child contains exactly `key`, `title`,
`description_markdown`, and `blocker_keys`. Validation returns a canonical
digest. Materialization requires that digest plus the current brief owner and
claim version; `children` returns the complete observed graph and a comparable
digest for lost-response recovery.
Workflow definitions are read with
`--definition-file FILE`. Task descriptions are read with
`--description-file FILE`; pass `-` as the file to read from standard input.
Repeat `--blocker-id ID` to provide multiple blockers. On task updates,
`--clear-parent` and `--clear-blockers` explicitly remove those relationships.

For example:

```sh
kos task create \
  --project-id 1 \
  --task-type-key development \
  --title "Document the CLI" \
  --description-file task.md

kos task claim-next --project-id 1 --task-type-key development --owner-id opencode-session-1
```

Server response bodies are written unchanged to stdout. A `204 No Content`
response succeeds without output. HTTP failures preserve the server body and
exit with status 1. CLI usage, configuration, and local-input failures are JSON
on stderr with status 2; transport failures use status 3. CLI-generated errors
never include the bearer token.

## Verify

Run the complete non-mutating verification suite:

```sh
bin/check
```

The underlying commands can also be run separately:

```sh
bin/format  # Apply automatic formatting fixes
bin/lint    # Check formatting and style
bin/test    # Run the test suite
```

## OpenCode Skills

The canonical OpenCode integration consists of:

- `.opencode/commands/kos.md`, the `/kos` entry point;
- `.opencode/agents/`, the isolated standard-step, advanced-step,
  worktree-read-only review, and publication agent profiles;
- `skills/kos/SKILL.md`, the lease-owning workflow orchestrator;
- `skills/kos-step/SKILL.md`, the isolated one-step executor;
- `skills/kos-git/SKILL.md`, the worktree and publication protocol;
- `skills/okf/SKILL.md`, the confined OKF v0.2 product-specification procedure.

This checkout's `opencode.json` makes the canonical skill directory
discoverable. For a global installation, copy the command to
`~/.config/opencode/commands/kos.md`, the isolated agent files to
`~/.config/opencode/agents/`, and each skill directory to
`~/.config/opencode/skills/`. Restart OpenCode after installing or changing
commands, agents, skills, or configuration because a running session does not
reload them.

The orchestrator uses only the public `kos` CLI for server state. A step
executor runs exactly one workflow step and atomically writes
`<kos-data-home>/tasks/<task-id>/<step-id>.md` before returning its outcome. The
orchestrator verifies that file before reporting the outcome and recovers a lost
report response by reading authoritative task state. The executor cannot mutate
KOS state. Review is independent and read-only for the worktree while still
writing its external artifact.

Every new workflow step declares `model_tier` as `standard` or `advanced`.
Ordinary steps use the matching profile; `review` is advanced and `publish` is
standard. Persisted legacy workflows without the field safely execute as
advanced.

The Git skill operates through standard Git commands and does not add Git
behavior to Rails or the CLI.

The OKF skill reads and changes only the supplied project worktree's `specs/`
bundle. It preserves unknown metadata and unrelated content, maintains links
and progressive-disclosure indexes, and keeps product behavior separate from
technical contracts and task artifacts. This repository's own bundle starts at
[`specs/index.md`](specs/index.md).

The Git skill derives each worktree from the same data-home rules as KOS:

```text
<kos-data-home>/worktrees/<project-id>/<task-id>
```

It keeps development, checks, and review uncommitted. During publication it
fetches the default branch, returns `base_moved` when checks and review must be
repeated, creates one task commit, pushes without force, and confirms the result
from observed remote state. Unexpected worktrees or ambiguous Git history are
preserved and reported as blocked rather than deleted or repaired.

## Documentation

- [Product specification](docs/specification.md)
- [Architecture rules](docs/architecture.md)
- [Testing rules](docs/testing.md)
- [Contribution rules](CONTRIBUTING.md)

Production deployment is intentionally outside the current project scope.
