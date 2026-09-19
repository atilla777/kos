# KOS

KOS is a small task state and coordination service for AI agents. This
repository contains the Rails state service, its authenticated JSON API, the
five core domain tables and models, workflow validation, task graph invariants,
atomic task lifecycle operations, a thin HTTP command-line client, and
distributable OpenCode orchestration, workflow-step, and Git skills.
Persisted tasks retain their project and workflow and are cancelled rather than
physically deleted. Isolated integration scenarios verify restart and
lost-response recovery, parallel worktrees, moved-base review repetition, and
interrupted publication without duplicate commits.
A real OpenCode `/kos` flow has been validated end to end.

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

## Setup

From a fresh checkout, install dependencies and prepare the local database:

```sh
bin/setup --skip-server
```

Prepare the empty test database explicitly:

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
GET   /tasks/:id
PATCH /tasks/:id
POST  /tasks/claim-next
POST  /tasks/:id/resume
POST  /tasks/:id/report-attempt
POST  /tasks/:id/cancel
```

Request fields are top-level JSON properties. Task responses contain `task`,
`workflow`, and `step` objects so an agent receives the stored state and the
current instruction in one response. `claim-next` returns `204 No Content` when
no task is available. Known failures use a stable `error` code with status
`400`, `404`, `409`, or `422` as appropriate.

For example:

```sh
curl --request POST http://127.0.0.1:3000/projects \
  --header "Authorization: Bearer $KOS_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"name":"KOS","remote_url":"https://example.test/kos.git","default_branch":"main"}'
```

## CLI

`bin/kos` uses `http://127.0.0.1:3000` by default. Set `KOS_API_URL` to use a
different HTTP(S) base URL. Every request requires `KOS_API_TOKEN`:

```sh
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_API_TOKEN="your-server-token"
export KOS_CLI_PATH="$(pwd)/bin/kos"
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
bin/kos --help
```

The CLI exposes every current API operation:

```text
kos project create
kos workflow create
kos task-type create
kos task-type update ID
kos task create
kos task update ID
kos task show ID
kos task claim-next
kos task resume ID
kos task report-attempt ID
kos task cancel ID
```

Use command help for exact options. Workflow definitions are read with
`--definition-file FILE`. Task descriptions are read with
`--description-file FILE`; pass `-` as the file to read from standard input.
Repeat `--blocker-id ID` to provide multiple blockers. On task updates,
`--clear-parent` and `--clear-blockers` explicitly remove those relationships.

For example:

```sh
bin/kos task create \
  --project-id 1 \
  --task-type-id 1 \
  --title "Document the CLI" \
  --description-file task.md

bin/kos task claim-next --project-id 1 --owner-id opencode-session-1
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
- `.opencode/agents/`, the owning orchestrator plus isolated ordinary-step,
  read-only-review, and publication agent profiles;
- `skills/kos/SKILL.md`, the lease-owning workflow orchestrator;
- `skills/kos-step/SKILL.md`, the isolated one-step executor;
- `skills/kos-git/SKILL.md`, the worktree and publication protocol.

This checkout's `opencode.json` makes the canonical skill directory
discoverable. For a global installation, copy the command to
`~/.config/opencode/commands/kos.md`, the agent files to
`~/.config/opencode/agents/`, and each skill directory to
`~/.config/opencode/skills/`. Restart OpenCode after installing or changing
commands, agents, skills, or configuration because a running session does not
reload them.

The orchestrator uses only the public `kos` CLI for server state. It writes the
current step artifact atomically to
`<kos-data-home>/tasks/<task-id>/<step-id>.md` before reporting an outcome and
recovers a lost report response by reading authoritative task state. The step
executor cannot mutate KOS state or write artifacts, runs exactly one workflow
step, and makes review independent and read-only.

The Git skill operates through standard Git commands and does not add Git
behavior to Rails or the CLI.

The skill derives each worktree from the same data-home rules as KOS:

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
