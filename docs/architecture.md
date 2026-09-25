# Architecture Rules

These rules describe the implemented PLAN-022 state-oriented architecture.

## Boundaries

- Rails owns authoritative persistent state, validation, fencing, accepted
  artifacts, pause and answer bindings, and transactional transitions.
- The CLI is a thin authenticated HTTP client. It never reads SQLite directly
  and does not contain an agent runtime or broker.
- A slash-command orchestrator is only a scheduler: select or create, claim or
  resume, read context, dispatch one exact profile by task ID, and reread context.
- A fresh step agent owns one step: focused context reads, predecessor evidence,
  worktree operations, checks, artifact production, outcome choice, and reporting.
- The filesystem owns task worktrees. It does not own request-bound creation
  recovery, accepted step artifacts, or human answers.
- Git owns commits and SHA values. Only the publication profile may mutate Git
  history or a remote.
- Product behavior lives in repository `specs/`; technical contracts live in
  `docs/`; accepted execution evidence lives in KOS task state.

## Design Rules

- Add mechanisms only for an end-to-end scenario and keep API projections focused.
- Enforce state invariants at the server boundary and within transactions, with
  database constraints where practical.
- Treat used workflow definitions as immutable values and keep concrete model
  identifiers in OpenCode profiles rather than workflow or task state.
- Derive machine-local worktree paths; never persist them as domain state.
- Keep external side effects outside Rails transactions and recover ambiguity by
  observing authoritative task, Git, remote, or child-graph state before retry.
- Never create a task commit before publication; never complete at publication.
- Store only the last accepted artifact per step, not attempts, pending reports,
  receipts, or a universal arbitrary state object.
- Never use local artifact fallback, dual reads, or automatic import of legacy files.

## Components

### Rails State Core

The bearer-authenticated JSON API and SQLite database own projects, workflows,
task types, tasks, dependencies, and transitions. `GET /up` remains public.
Rails validates workflow shape but has no semantic knowledge of planning,
diagnosis, checks, documentation, review, publication, verification, or OKF.

The five domain tables remain `projects`, `workflows`, `task_types`, `tasks`,
and `task_dependencies`. PLAN-022 adds execution context to `tasks`, not a new
artifact or attempt table. `accepted_artifacts` is a JSON map keyed by step ID;
each value contains `outcome`, complete `markdown`, `accepted_claim_version`,
and `reconstructed`. Pause state uses `pause_message`, `pause_step`, and
`pause_claim_version`; answer state uses `human_answer`, `human_answer_step`, and
`human_answer_claim_version`.
Request-bound tasks may also store an immutable nullable `creation_key`. A
partial unique index on project, task type, and non-null key is the final
duplicate-creation boundary; ordinary tasks remain null and unaffected.

Each report transaction validates the artifact first, resolves the workflow
action, validates a required pause message, copies and updates the accepted map,
and performs one fenced update requiring active status, owner, claim version,
current step, and unexpired lease. The update stores the artifact, applies the
transition, increments `claim_version`, and sets or clears pause and answer state.
No accepted artifact can exist without its corresponding accepted transition.
Built-in completion is additionally constrained to `verify`, regardless of an
immutable snapshot's action. Brief publication takes a SQLite write lock before
observing children, so materialization and reporting serialize; `published`
requires children, while a materialized graph forbids publication rewinds.

The artifact limit is 1 MiB by UTF-8 bytes. Artifacts must be nonempty valid
UTF-8 strings. KOS stores their exact Markdown but does not parse template
meaning. Repeating a step replaces that key; no attempt history is retained.

### CLI Transport

The packaged `kos` executable is stateless and preserves server response bodies.
Agents use only the administrator-configured absolute `KOS_CLI_PATH`. Top-level
and per-command help are the authoritative syntax reference. The shared
`kos-cli` skill protects credentials, supplies each value as a separate
argument, checks only response fields needed for the current decision, and
observes authoritative state before retrying an ambiguous mutation. Rails owns
response projections and lifecycle invariants; the CLI validates local options,
configuration, and input, then preserves server bodies.

The focused step operations are:

- `task context`, containing task execution identity, registered project,
  exact current step, artifact index, pause/answer projection, and status;
- `task artifact`, containing one accepted artifact; and
- `task report-attempt`, atomically accepting one
  artifact and transition.

`context` deliberately omits accepted Markdown from its artifact index. A step
agent separately requests only the artifacts it needs. Standard input is the
preferred source for structured content wherever command help supports it; task
content is never interpolated into shell syntax or stored as local protocol
state.

### Schedulers

`skills/kos` contains the shared scheduler for development, fix, and brief
tasks; `skills/kos-brief` is the brief command's thin entry adapter. The shared
scheduler may discover a project, offer resumable tasks, request a safe claim or
resume, and display persisted pause information.
Each command session generates a fresh unpredictable owner for claim or resume;
`KOS_OWNER_ID` is not configuration. Request-bound creation uses that owner in
the focused server-idempotent `task create-or-get` operation.

For each active iteration the scheduler reads `task context`, maps the exact
current built-in step to one focused profile, dispatches a fresh foreground
child whose entire prompt is the decimal task ID, ignores all returned text, and
rereads context. It never reads the task description for dispatch, workflow
Markdown, accepted artifacts, local artifacts, Git diff/status/HEAD, checks,
child outcomes, graph proposals, receipts, or pending submissions. It never
calls `report-attempt` or performs brief graph operations.

Request-bound creation is one CLI and server operation. The scheduler supplies
the project, kind, fresh owner, and exact request. The server derives the
canonical title and description plus a scoped key from the request's SHA-256
digest, then uses the database unique index as the duplicate boundary. An
identical retry returns the existing task in any lifecycle state and never
reclaims or mutates it. No intent, lock, receipt, or legacy namespace is read or
written.

### Step Agents

Every step profile loads `kos-step` and receives exactly one positive task ID.
The shared guidance tells it to read authoritative context and relevant accepted
evidence, obtain its worktree through `kos-git`, execute one step, and report its
own result. Role profiles stay concise: they define substantive responsibility,
expected result, and essential read-only, mutation, or publication boundaries
rather than repeating transport and fencing mechanics.

The server transaction validates the active owner, claim version, current step,
outcome, artifact, and pause message and is the acceptance boundary. On an
ambiguous response the agent observes authoritative state through `kos-cli`.
The child returns only a non-authoritative confirmation and never performs a
second step.

### Git And Worktrees

`kos-git` accepts only a task ID, gets the registered project and authority from
context, and derives `<kos-data-home>/worktrees/<project-id>/<task-id>`. It
requires a verified detached worktree for the registered repository and remote,
preserves staged, unstaged, and untracked work, and refuses unknown or unsafe
paths and active Git operations rather than deleting or repairing them.

Repository discovery requires one `origin` fetch URL and one push URL. Supported
HTTPS, `ssh://git@...`, and relative scp-style `git@host:...` forms normalize to
one lower-cased-host `host/namespace/repository` identity. Credentials, ports,
queries, fragments, local paths, ambiguous slashes, non-`git` SSH users, and
fetch/push identity mismatches are rejected before mutation. `kos-cli` performs
an exact registration lookup. There is no `KOS_PROJECT_*` configuration.

## Profiles And Roles

The slash commands run in OpenCode's primary `build` agent and load scheduler
skills. The `.opencode/agents/kos-*` files below select role, model, reasoning
effort, and prompt for fresh step subagents.

The exact built-in dispatch map is:

| Step | Profile | Model role | Worktree and operation authority |
| --- | --- | --- | --- |
| `diagnose` | `kos-diagnose` | advanced | read-only KOS/Git; reproduction from an exported tree with an isolated empty environment |
| `plan` | `kos-plan` | advanced | read-only |
| `implement` | `kos-implement` | standard | edit and run checks; no commit or push |
| `document` | `kos-document` | standard | edit and use `okf`; no commit or push |
| `brief` | `kos-brief` | advanced | edit authorized specification/graph work; no commit or push |
| `review` | `kos-review` | advanced | independent and read-only |
| `publish` | `kos-publish` | standard | sole base-update, stage, commit, push, graph-validation, and materialization authority |
| `verify` | `kos-verify` | advanced | fresh independent read-only remote and result verification |

Managed profiles intentionally contain no KOS-specific OpenCode permission
blocks. They are role and model selection, not a security boundary; tool approval
comes from the administrator's OpenCode configuration. Their prompts define the
expected procedure: read-only roles preserve the worktree, publish alone performs
Git publication and brief graph mutation, and generic custom-step roles do not
commit or push. Server authorization and lifecycle fencing remain authoritative,
with independent review and verification checking the resulting work.

## Backward Transitions

Focused agents validate predecessor evidence and use explicit correction routes:

- Development: `plan_invalid` to `plan`, `implementation_invalid` to
  `implement`, review `changes_requested` to `implement`, `redesign_required` to
  `plan`, publish `review_invalid` to `review`, `base_moved` to `implement`,
  verify `publication_missing` to `publish`, and `changes_invalid` to `implement`.
- Fix adds plan `diagnosis_invalid` to `diagnose`; all later routes match
  development.
- Brief uses review `changes_requested` to `brief`; publish `review_invalid` to
  `review`, `base_moved` or `graph_invalid` to `brief`; and verify
  `publication_missing` or `materialization_missing` to `publish`, and
  `brief_invalid` to `brief` only before an incompatible graph exists.

Every built-in step also supports fenced `needs_human` and `blocked` pauses.
Backward execution replaces only artifacts for steps actually rerun. Later
accepted artifacts remain visible as historical last-accepted evidence, so each
step validates the exact predecessors and current repository state it relies on.

## Publication And Verification

Publication validates accepted plan, implementation, documentation, and review
evidence. A brief also validates its accepted specification and graph. If the
remote base moved, the publisher preserves task work on the new base and reports
the explicit backward outcome without committing. Otherwise it stages only
validated paths, runs `git diff --cached --check`, creates one detached commit
with one `KOS-Task: <id>` trailer, pushes without force, fetches again regardless
of push output, and reports `published` only after remote observation. Brief
children are atomically materialized only after that observation.

`published` always transitions to `verify`. A fresh verify profile performs no
checkout, index update, commit, push, graph mutation, or worktree edit. It fetches
the remote independently, locates and inspects the task commit, and compares its
paths and patch with the task and accepted evidence. Brief verification also
compares the remote specification and server-observed graph. It does not trust
the publish artifact or local HEAD. Only `verified` completes the task.

## Recovery And Migration

Task state is the recovery record. Server or OpenCode restart reads current
context and accepted artifacts. A lost report response is resolved by observing
the claim version, current step, status, and accepted-artifact index. There is no
local `tasks/<id>/<step>.md`, answer sidecar, pre-dispatch unlink, inode identity,
rename/fsync rule, marker, attempt ID, report receipt, pending submission, or
dual-read compatibility path.

Resume is fenced by exact claim version and step. A `needs_human` answer is
stored against the pause's step and incremented pause version; context projects
it only for that exact binding. The binding survives another active takeover and
is cleared by the next accepted report.

The PLAN-022 migration adds the artifact, pause, and answer columns with an empty
artifact map. Existing unfinished tasks preserve IDs, projects, parents,
dependencies, task types, immutable workflow snapshots, definitions, status,
current step, ownership fields, and worktrees. A built-in snapshot without the
verification route is blocked before publication side effects; preserve its
work, cancel it, and recreate it from the current catalog. It is never imported,
dual-run, or repointed. Current snapshots may rerun their current step to
reconstruct missing evidence; legacy local files remain ignored. The isolated
migration test migrates up, verifies preservation and empty artifacts, migrates
down, verifies only new columns disappear, and rechecks IDs and relationships.

Scoped server creation keys recover request creation through an identical
create-or-get retry. Git publication and brief materialization ambiguity are
recovered from remote Git and complete server graph observations respectively,
never from local protocol files.

See [the system specification](specification.md), [testing rules](testing.md),
and [installation guide](installation.md).
