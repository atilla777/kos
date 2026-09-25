# KOS

KOS is a small state and coordination service for AI agents. This repository
contains a Rails/SQLite state core, authenticated JSON API, thin packaged CLI,
five domain tables, immutable workflows, fenced task lifecycle, canonical
repository discovery, built-in brief/development/fix workflows, isolated Git
worktrees, and distributable OpenCode commands, focused agents, and skills.

PLAN-022 uses state-oriented execution. KOS stores the last accepted Markdown
artifact for each reported step together with pause and human-answer bindings.
A scheduler dispatches only a task ID; each fresh step agent reads its own
authoritative context and predecessor evidence, performs one step, and atomically
reports its artifact and transition. Publication advances to fresh independent
verification, and only verification completes a built-in task.

## Prerequisites

- Ruby 3.4.10
- Bundler 4.0.20
- SQLite 3 and development headers
- Git
- OpenCode 1.18.26 or later

```sh
gem install bundler --version 4.0.20
export KOS_API_TOKEN="$(openssl rand -hex 32)"
```

Keep the token secret. Application endpoints require `Authorization: Bearer
<token>`; `GET /up` is public.

Development and production databases default to `$XDG_DATA_HOME/kos`, or
`~/.local/share/kos`. `KOS_DATA_HOME` may override it with an absolute local
path outside the checkout. Network or synchronized storage is unsupported.
Tests always use isolated temporary state. Ownership leases default to six
hours; `KOS_LEASE_SECONDS` accepts a positive override.

## Install

Use one fixed Git revision for Rails, the CLI gem, catalog, commands, profiles,
and skills:

```sh
git fetch --tags
git checkout <release-tag-or-commit>
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare

gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" --help

bin/install-opencode
```

Database preparation installs the `brief`, `development`, and `fix` task types
and workflows. It does not register a project. Start Rails and register each
repository explicitly:

```sh
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails server

"$KOS_CLI_PATH" health
"$KOS_CLI_PATH" project create \
  --name KOS \
  --remote-url https://github.com/atilla777/kos.git \
  --repository-identity github.com/atilla777/kos \
  --default-branch main
"$KOS_CLI_PATH" project show --repository-identity github.com/atilla777/kos
```

Commands derive canonical `host/namespace/repository` from the invoking
checkout's single `origin` fetch and push URLs, then require an exact registered
identity. Supported equivalent SSH and HTTPS forms normalize to the same value.
Missing, malformed, ambiguous, or mismatched origins block before mutation.
There are no `KOS_PROJECT_*` environment variables.

`bin/install-opencode` installs:

- commands `kos.md`, `kos-fix.md`, and `kos-brief.md`;
- focused agents `kos-diagnose`, `kos-plan`, `kos-implement`, `kos-document`,
  `kos-brief`, `kos-review`, `kos-publish`, and `kos-verify`;
- custom-step agents `kos-step-standard` and `kos-step-advanced`; and
- skills `kos`, `kos-brief`, `kos-cli`, `kos-step`, `kos-git`, and
  `okf`.

Standard agents use `openai/gpt-5.6-terra` with medium reasoning; advanced
agents use `openai/gpt-5.6-sol` with high reasoning. Administrators may change
complete provider/model IDs while preserving roles. Restart OpenCode after
installation or configuration changes; running sessions do not reload managed
files. See the [installation guide](docs/installation.md) for upgrades and the
full readiness procedure.

## Commands

- `/kos` accepts no task text, resumes or claims only `development` work, and
  never creates a task.
- `/kos-fix <problem>` recovers or creates and claims the exact `fix` request.
- `/kos-brief <request>` recovers or creates and claims the exact `brief`
  request. Briefing itself runs in a fresh focused agent, not the main scheduler.

Schedulers may select, create, claim, resume, read state, dispatch one current
step, and reread state. Each command session generates a fresh unpredictable
non-secret owner ID; there is no `KOS_OWNER_ID` configuration. After obtaining a
positive task ID schedulers retain only that ID. They do not read Markdown,
dispatch descriptions or prior artifacts, inspect Git or checks, parse child
text, report outcomes, or maintain pending submissions.

Step agents receive only the positive ID. They use focused context and artifact
reads, validate required predecessors, invoke `kos-git` by ID, execute one exact
step, reread the fence, and call `report-attempt` themselves. For fix and brief
creation, schedulers send the project, kind, owner, and exact request to
`task create-or-get`. The server derives the canonical definition and scoped
creation key, so one identical retry safely recovers a lost response without
local protocol files.

## Data Model

KOS retains exactly five domain tables:

| Table | Core fields |
| --- | --- |
| `projects` | ID, display name, unique `repository_identity`, remote URL, default branch, timestamps |
| `workflows` | ID, name, immutable JSON definition, creation time |
| `task_types` | ID, stable unique key, name, workflow ID, timestamps |
| `tasks` | IDs for project/type/workflow/optional parent; optional immutable creation key; title and description; status and current step; owner, claim version, lease; accepted-artifact map; pause message/step/version; human answer/step/version; timestamps |
| `task_dependencies` | Task and blocker relationships |

Tasks preserve their selected workflow revision. Pending unclaimed definitions
may be edited; claimed task definitions are fixed. KOS has no universal
arbitrary task-state field, checkpoint, attempt history, SHA fields, or artifact
graph. The accepted-artifact map stores only the latest accepted outcome,
Markdown, accepted claim version, and reconstruction flag for each step.

## API

All application routes except `GET /up` require the bearer token and use JSON:

```text
POST  /projects
GET   /projects?repository_identity=IDENTITY
PATCH /projects/:id
POST  /workflows
POST  /task_types
PATCH /task_types/:id
POST  /tasks
POST  /tasks/create-or-get
POST  /tasks/create-and-claim
GET   /tasks/:id
GET   /tasks/:id/context
GET   /tasks/:id/artifact?step=STEP
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

`context` returns these exact groups:

- `task`: `id`, `project_id`, `title`, `description_markdown`, `status`,
  `current_step`, `owner_id`, `claim_version`, `lease_expires_at`;
- `project`: `id`, `name`, `repository_identity`, `remote_url`, `default_branch`;
- `step`: `id`, `name`, `instruction`, `artifact_template`, `model_tier`,
  `allowed_outcomes`;
- `artifacts`: entries with `step`, `outcome`, `accepted_claim_version`, and
  `reconstructed`, without Markdown; and
- `pause`: null or `step`, `claim_version`, `message`, and exactly bound `answer`.

`artifact` returns exactly `outcome`, `markdown`, `accepted_claim_version`, and
`reconstructed` for one accepted step. Absence is an error, not empty evidence.

`report-attempt` accepts top-level `owner_id`, `claim_version`, `step`, `outcome`,
`artifact`, and optional `message`. Artifact Markdown must be nonempty valid
UTF-8 and at most 1 MiB. A pause requires a nonblank message. One transaction
checks the active unexpired fence and allowed action, replaces that step's
accepted artifact, increments the version, applies the transition, and updates
pause/answer state. A stale or invalid report changes nothing. The server also
refuses every built-in completion outside `verify`. A brief `published` report
requires an already materialized child graph under the same serialized
transaction boundary, and a materialized graph cannot coexist with a
publication rewind.

Task responses for broader lifecycle operations contain `task`, `workflow`, and
`step`. `claim-next` and `show-owned` return `204 No Content` when absent. Known
failures use stable JSON errors and HTTP `400`, `404`, `409`, or `422`.
`create-or-get` accepts a project, `fix` or `brief` kind, owner, and exact
request. It derives the canonical task and returns the existing keyed task for
an identical request without lifecycle mutation. `create-and-claim` optionally accepts `creation_key`. It returns the same exact
task for a matching scoped key without reclaiming or mutating lifecycle state;
reusing a key with a different immutable definition returns `409`.

## CLI

The CLI defaults to `http://127.0.0.1:3000`; configure it with:

```sh
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_API_TOKEN="your-server-token"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
```

The installed executable exposes every public API operation. Its top-level and
per-command help are the authoritative command and option reference:

```sh
"$KOS_CLI_PATH" --help
"$KOS_CLI_PATH" task report-attempt --help
```

Use stable built-in task-type keys in user commands. Resume and mutation
operations supply the exact persisted fence required by command help. Prefer
standard input for exact request, answer, artifact, description, workflow, and
child-graph content wherever help permits `-`; never interpolate structured
content into shell syntax. Brief validation returns a canonical digest, and
materialization uses that digest and the current fence.

Server bodies are written unchanged to stdout. HTTP errors exit 1; local usage,
configuration, and input errors are JSON on stderr and exit 2; transport errors
exit 3. `kos health` uses `KOS_API_URL` and the public `GET /up` endpoint without
requiring `KOS_API_TOKEN`. CLI-generated errors never expose the token.

## Workflow Authority

The exact built-in profile mapping is:

| Step | Profile | Authority |
| --- | --- | --- |
| `diagnose` | `kos-diagnose` | advanced, read-only |
| `plan` | `kos-plan` | advanced, read-only |
| `implement` | `kos-implement` | standard, edits and all required checks, no commit |
| `document` | `kos-document` | standard, edits and OKF, no commit |
| `brief` | `kos-brief` | advanced, authorized specification and graph edits, no commit |
| `review` | `kos-review` | advanced, independent read-only review |
| `publish` | `kos-publish` | standard, only commit/push and graph mutation authority |
| `verify` | `kos-verify` | advanced, fresh independent read-only verification |

Development routes invalid plans back to `plan`, invalid implementation evidence
to `implement`, review changes to `implement`, redesign to `plan`, invalid review
to `review`, moved base to `implement`, missing publication to `publish`, and
invalid published changes to `implement`. Fix additionally routes invalid
diagnosis back to `diagnose`. Brief routes requested changes, moved base, or
invalid graph to `brief`; invalid review to `review`; missing publication or
materialization to `publish`; and safely correctable invalid briefing to `brief`.

Every built-in step supports `needs_human` and `blocked`. `published` always
advances to `verify`; only `verified` completes. The verifier independently
reads remote Git and accepted evidence and does not trust publisher prose or
local HEAD.

Managed profiles select the role, model, reasoning effort, and focused prompt.
They contain no KOS-specific OpenCode permission policy and are not a security
boundary. Tool approval follows the administrator's OpenCode configuration;
server authorization and fencing remain the authoritative state boundary, while
review and verification detect violations of role-specific procedure.

## Recovery And Upgrade

Task context is authoritative after server, OpenCode, transport, or agent
interruption. There are no local `tasks/<id>/<step>.md` files, answer sidecars,
pre-dispatch artifact deletion, inode/rename/fsync protocol, attempt markers,
report receipts, pending submissions, or dual-read fallback. KOS stores accepted
artifacts; the filesystem stores only worktrees.

A lost report response is resolved by rereading context and its artifact index.
A changed fence and expected accepted entry prove success; an unchanged matching
fence permits one controlled retry; contradiction blocks. The scheduler does not
retain report bytes.

Upgraded unfinished tasks preserve IDs, relationships, selected workflow,
current lifecycle position, ownership, and worktree. Their accepted-artifact map
starts empty. An unfinished built-in task on a pre-verification workflow
snapshot cannot be advanced safely: preserve its work, cancel it, and recreate
it from the current built-in catalog. KOS does not import, dual-run, or repoint
that immutable snapshot. A current workflow snapshot may rerun its authoritative
current step to reconstruct missing accepted evidence. Old local artifacts are
never imported or read automatically.

Git worktrees are derived as:

```text
<kos-data-home>/worktrees/<project-id>/<task-id>
```

Publication alone may fetch/update the base, stage, commit, and push. It creates
one commit with exactly one `KOS-Task: <task-id>` trailer, pushes without force,
and observes remote history. A moved base preserves work and repeats the required
post-plan path. Interrupted commit/push recovery observes Git before retrying.

## Verify

```sh
bin/check
```

`bin/check` prepares isolated test state, lints, and runs deterministic unit,
request, CLI, migration, lifecycle, skill, Git, recovery, installation, and
scenario contract tests. `bin/test`, `bin/lint`, and mutating `bin/format` are
also available. This automated suite proves lifecycle and installed-asset
contracts, not live model slash-command execution. Real `/kos-brief`, `/kos`,
and `/kos-fix` model runs remain separate required release evidence with
isolated databases, data homes, repositories, remotes, worktrees, and
configuration; that evidence is not claimed complete here.

## Documentation

- [OKF product concept](specs/kos.md)
- [System specification](docs/specification.md)
- [Architecture rules](docs/architecture.md)
- [Testing rules](docs/testing.md)
- [Installation guide](docs/installation.md)
- [Contribution rules](CONTRIBUTING.md)
