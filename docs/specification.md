# KOS Product Specification

Status: normative for the first version.

This document transfers the agreed KOS requirements into the repository. The
implementation order is tracked separately; requirements in later sections do
not imply that they are already implemented.

## Purpose

KOS is a small task state and coordination system for AI agents. It preserves
projects, tasks and descriptions, parent and blocking dependencies, the chosen
workflow, current step and status, and temporary ownership between sessions.

KOS does not perform substantive work for an agent. Agents clarify
requirements, change code, select checks, review changes, operate Git, and
diagnose failures according to skill instructions.

The first version proved one real path:

```text
create task -> develop -> check -> independent review -> publish -> completed status
```

The next version keeps that foundation and provides three built-in scenarios:

```text
/kos-brief <request> -> specify product behavior -> publish specs -> create work
/kos                 -> plan -> implement and check -> document -> review -> publish
/kos-fix <problem>   -> diagnose -> plan -> implement and check -> document -> review -> publish
```

These are product scenarios, not a general-purpose workflow language. The
implementation order is tracked separately; describing a target contract here
does not claim that a later-plan capability is already implemented.

## System Boundary

The first version runs on one execution host containing Rails, SQLite, the KOS
CLI, OpenCode and skills, KOS data, and task worktrees. Different tasks may run
in parallel in separate worktrees. Moving an unfinished active task to another
host is unsupported.

The user entry points are `/kos-brief <request>`, `/kos-fix <problem>`, and
`/kos` without arguments. Users do not manually manage task type or workflow
IDs, claim versions, leases, internal API calls, worktree paths, or internal
step outcomes.

A first installation creates an empty database and idempotently installs the
built-in `brief`, `development`, and `fix` task types and their workflows.
Projects remain installation-specific administrative data. Custom workflows
and task types remain supported.

## Responsibilities

KOS is responsible for:

- storing projects, workflows, task types, tasks, and dependencies;
- making used workflows immutable;
- selecting the next available task of a requested type or claiming a specific
  available task;
- exclusive ownership by one orchestrator;
- ownership expiry and rejection of stale owners;
- validating the current step and reported outcome;
- atomically moving to the next step or status;
- allowing work to continue after process interruption.

KOS is not responsible for judging requirements or code, selecting files or
checks, running OpenCode or Git, interpreting Markdown artifacts, proving a
review belongs to a SHA, or storing Git history.

Agents and skills are responsible for task clarification, step execution,
artifact management, worktree checks, uncommitted changes, project checks,
independent review, base-branch synchronization, commit creation during
publication only, safe push, and diagnosis of external command results.

## Components

The Rails server is the transactional state core. It exposes a REST API backed
by SQLite and never starts OpenCode, Git, or project checks.

The `kos` CLI is the agents' only programmatic interface to Rails. It sends
requests and emits structured responses. It never accesses SQLite directly and
does not contain a runtime broker.

The CLI is packaged as a Ruby gem from this repository. Deployments build and
install it with standard RubyGems commands from the same Git revision as the
installed OpenCode integration.

The slash-command skills are the user entry points and orchestrators. `/kos`
claims the next available development task. `/kos-fix` and `/kos-brief` create
and claim the exact task derived from their argument. They ask KOS for the
current step, invoke the authority appropriate to that step, report the
outcome, and continue until completion, a human question, or a technical stop.
There is no separate orchestrator program.

The generic step executor receives the task description, current step,
instruction, artifact template, model tier, worktree path, artifact directory,
and exact artifact path. It runs only that step, writes a new current Markdown
artifact at the supplied path, and returns one allowed outcome.

The brief scenario is the exception to ordinary one-shot step execution. Its
`brief` step runs in the main conversational agent so material questions and
answers remain available while the product specification and child-task plan
are developed. Independent review and publication still use isolated agents.

The `okf` skill is the only shared procedure for reading or changing product
specifications under a task worktree's `specs/` directory. It does not store
specifications in KOS or turn Rails into a documentation parser.

The Git skill creates and verifies worktrees, observes actual Git state,
preserves uncommitted changes, updates from the default branch, commits only at
publication, pushes without force, and observes the remote result before
retrying an ambiguous operation.

## Data Model

The first version has exactly five domain tables:

| Table | Required purpose and fields |
| --- | --- |
| `projects` | `id`, `name`, unique canonical `repository_identity`, `remote_url`, `default_branch`, timestamps |
| `workflows` | `id`, `name`, `definition_json`, `created_at` |
| `task_types` | `id`, stable machine `key`, `name`, `workflow_id`, timestamps |
| `tasks` | `id`, `project_id`, `task_type_id`, `workflow_id`, optional `parent_id`, `title`, `description_markdown`, `status`, `current_step`, `owner_id`, `claim_version`, `lease_expires_at`, timestamps |
| `task_dependencies` | Blocking relationships between tasks |

A project does not store local paths, custom worktree paths, or allowed task
types. Tools derive local paths at runtime.

Each workflow row is one complete immutable revision. Once a task uses it, its
JSON cannot change. A change creates a new workflow row; no separate version
number is needed.

Task types are global. Their machine key is stable and unique; display names may
change without changing command behavior. The reserved built-in keys are
`brief`, `development`, and `fix`. A new task copies the type's current
`workflow_id` into the task, so later type changes do not affect existing
tasks.

Bootstrap compares each canonical built-in workflow definition with the
current revision. It reuses an identical revision, creates a new immutable row
when the definition changed, and repoints only the built-in task type. It never
rewrites workflows already snapshotted by tasks and never replaces custom
types.

The migration that introduces keys assigns every existing task type a stable,
non-reserved custom key derived from its ID; it never infers built-in identity
from a display name. Bootstrap then creates the three reserved built-ins.
Administrative creation cannot use a reserved key, and a collision or partially
migrated row stops bootstrap without repointing or deleting existing data.

A pending task description and dependencies may be edited before its first
claim. After the first claim, its description is fixed; a substantial goal
change requires cancellation and a new task. Tasks have no universal state,
last-result, checkpoint, SHA, check-result, review-result, or publication-result
field.

Parents must belong to the same project and cannot form a cycle. Blocking
dependencies must belong to the same project, cannot refer to the task itself,
and cannot form direct or indirect cycles. A task is unavailable until all its
blocking dependencies are completed.

## Workflow

A workflow is one JSON document containing an ordered `steps` array. Every step
has a unique ID, name, instruction, artifact template, model tier, and outcome
map. A task's initial `current_step` is the first step ID. The model tier is
`standard` or `advanced`; it selects an installation-defined OpenCode agent
profile without persisting a concrete provider or model in KOS. New workflows
require it. Persisted legacy definitions without it are projected as
`advanced` so immutable workflows remain runnable.

Every outcome defines exactly one action:

- `next_step` naming an existing step;
- `pause` equal to `needs_human` or `blocked`;
- `complete_task: true`.

KOS validates a non-empty step list, unique IDs, the existence of current and
next steps, allowed outcomes, and exactly one valid action per outcome. It does
not compute readiness, assess artifact content, or execute conditions.

Workflow definitions do not contain artifact graphs, gates, result
generations, SHA links, separate step tables, executable code, arbitrary
expressions, or parallel steps within one task.

## Built-In Workflows

The built-in definitions use the existing generic step and outcome mechanism.
They do not give Rails knowledge of planning, checks, documentation, review, or
publication. Custom workflows remain valid, including a custom step whose ID is
`check`; only the built-in workflows omit that separate transition.

The development workflow is:

| Step | Successful or corrective transition |
| --- | --- |
| `plan` | `planned` -> `implement` |
| `implement` | `implemented` -> `document` |
| `document` | `documented` -> `review` |
| `review` | `approved` -> `publish`; `changes_requested` -> `implement`; `redesign_required` -> `plan` |
| `publish` | `published` -> complete task; `base_moved` -> `implement` |

`plan` is advanced and read-only. `implement` and `document` are standard.
`implement` owns code changes and must run all project-required tests, lint,
formatting checks, builds, and type checks in the same attempt; an ordinary
failed check is work to fix, not a workflow transition. `document` updates
affected product specifications through `okf`, or records why behavior did not
change. `review` is advanced, independent, and read-only. `publish` is standard
and is the only step allowed to commit or push. Returning from `base_moved`
repeats implementation checks, documentation, and review.

The fix workflow is:

| Step | Successful or corrective transition |
| --- | --- |
| `diagnose` | `diagnosed` -> `plan` |
| `plan` | `planned` -> `implement` |
| `implement` | `implemented` -> `document` |
| `document` | `documented` -> `review` |
| `review` | `approved` -> `publish`; `changes_requested` -> `implement`; `redesign_required` -> `plan` |
| `publish` | `published` -> complete task; `base_moved` -> `implement` |

`diagnose` and `plan` are advanced and read-only; `implement` and `document` are
standard; `review` is advanced; and `publish` is standard. Diagnosis reproduces
the symptom, records evidence, and identifies the root cause before planning.
The plan requires a regression check that fails for the original defect.
Ambiguous expected behavior or a problem that cannot be reproduced pauses as
`needs_human` with a precise question; infrastructure failure pauses as
`blocked`.

The brief workflow is:

| Step | Successful or corrective transition |
| --- | --- |
| `brief` | `specified` -> `review` |
| `review` | `approved` -> `publish`; `changes_requested` -> `brief` |
| `publish` | `published` -> complete task; `base_moved` -> `brief`; `graph_invalid` -> `brief` |

The advanced main conversational agent performs `brief` using `okf`; `review`
is advanced and `publish` is standard. Briefing resolves goals,
actors, current and desired behavior, rules, errors, edge cases, security,
compatibility, migration, observability, non-goals, and acceptance criteria,
and proposes either one development task or a minimal acyclic graph. Material
uncertainty pauses as `needs_human`; clear requirements continue without a
mandatory approval pause. Another agent reviews both the specification and the
proposed task graph without changing the worktree.

Before publication, the orchestrator submits the reviewed graph to the same
server validation used by materialization, without creating children. The
response includes a digest of the canonical validated definition; the
orchestrator retains it outside Rails and refuses to materialize different
bytes. A `graph_invalid` rejection returns to `brief`, then repeats review. The
brief publication agent publishes only a reviewed `specs/` change whose graph
passed that validation. After the remote result is confirmed, the main
orchestrator atomically materializes the complete child graph. Every child is a
development task with the brief as parent and blocker, and may also depend on
sibling tasks.
Only after the graph is observed to match the proposal may the orchestrator
report `published` and complete the brief. A post-publication conflict that
cannot be reconciled with the validated proposal is technical `blocked`, never
permission to edit an already reviewed graph at `publish`. Thus children cannot
become available before publication, and an interrupted graph mutation is
recovered by observation rather than by blind creation. There is no executable
`complete` or `materialize` step.

Every built-in step also permits `needs_human` and `blocked`, which pause and
preserve that step. These common pause outcomes are omitted from the tables for
readability. `completed` is a task status reached by a `complete_task` outcome,
never a workflow step.

## Status And Ownership

Allowed statuses are `pending`, `active`, `needs_human`, `blocked`, `completed`,
and `cancelled`. `current_step` always names the step to run now or retry after
resume. A `needs_human` or `blocked` result preserves the current step.

Claiming a task atomically verifies status, completed dependencies, and the
absence of another valid owner; stores `owner_id`; increments `claim_version`;
sets `lease_expires_at` from server time; sets `active`; and returns the task,
workflow, step, and claim data.

`owner_id` is a non-secret orchestrator session identifier. `claim_version` is
a monotonically increasing, non-secret fencing number. Every execution
mutation supplies both. Requests from an expired or superseded owner fail.
One owner ID may identify at most one nonterminal task; a database constraint
supports that invariant where practical.

There is no heartbeat in the first version. A configurable, sufficiently long
lease is used. An explicit resume may replace an expired owner or, after the
caller confirms the old process stopped, an active owner. Resume increments
`claim_version`, records the new owner and lease, and keeps the current step.
Before each step, a skill verifies that its claim remains current.

Reporting an attempt includes task ID, owner ID, claim version, step, and
outcome. KOS verifies ownership, lease, claim version, current step, and allowed
outcome, then atomically advances the step, pauses without changing it, or
completes the task. Every accepted attempt increments `claim_version`, fencing
duplicate or delayed reports even when a workflow returns to the same step. A
pause or completion releases ownership.

After a lost response, the orchestrator reads the task. Stored status and step
show whether the transition occurred; repeating a stale transition produces a
clear conflict rather than a second transition. There are no checkpoints.

Cancellation is an explicit administrative operation. Cancelling an active
task increments `claim_version` and releases ownership. Dependents of a
cancelled task remain unavailable. Before cancelling during publication, the
orchestrator must observe local and remote Git state: an already published
change is reported as published, while ambiguity produces `blocked`.

## Local Data And Artifacts

Local execution data uses one configurable, preferably XDG-compliant root:

```text
$XDG_DATA_HOME/kos/tasks/<task-id>/
$XDG_DATA_HOME/kos/worktrees/<project-id>/<task-id>/
```

Each task stores the current Markdown artifact as `<step-id>.md`. Repeating a
step may replace that file; a complete attempt history is not required.
`needs_human` records the exact question, and `blocked` records the technical
cause and observed state. KOS neither parses nor registers these files.

Before resuming a `needs_human` task, the command atomically records the user's
answer in a separate `<step-id>-answer.md` sidecar. The retried authority
receives both question and answer. It replaces the step artifact only after the
attempt is complete; the answer sidecar remains sufficient to retry after
another process interruption and may be removed only after the task advances.

Before every attempt, the orchestrator inspects the exact derived step-artifact
path without following symbolic links. An absent path is ready. A regular file
is removed before dispatch so stale or unconfirmed bytes cannot satisfy the new
attempt. A symbolic link, directory, or other unexpected object is a technical
blocker and is not removed.

The executor writes the new `<step-id>.md` directly with an available filesystem
tool; it need not create a temporary file, rename, fsync, change file identity,
or carry an attempt identifier. After the executor returns a valid exact
outcome response, the orchestrator reads the exact path without following
symbolic links and requires a new regular non-symlink file whose bytes are
nonempty valid UTF-8, match the current template, and agree with that outcome.
Only then may it report the attempt to KOS. A failed executor, invalid or lost
response, absent or partial file, or failed content check leaves the task on the
same step without a report. A later retry removes any remaining regular
unconfirmed file before dispatch.

The orchestrator never infers an outcome from artifact content. After an
ambiguous report response, it retains the verified exact bytes and observes
task state. It may retry the identical report once only when the transition did
not occur and the artifact still has those exact bytes; an observed transition
is accepted, while unavailable or contradictory state stops without another
side effect.

This replaceable step-artifact protocol does not alter the atomic durability
requirements for human-answer sidecars, command intents and receipts, brief
graph authority files, or other long-lived recovery state.

Worktree paths are derived, not stored. Before task or local recovery mutation,
the Git and CLI skills cooperatively require one `origin` fetch URL and one push
URL, normalize equivalent HTTPS and SSH spellings to a canonical repository
identity, and look up that exact registered identity. Unknown, mismatched,
malformed, or ambiguous repositories and worktrees are not deleted or repaired
automatically; work stops as `blocked`.

## Product Specifications

Each participating project may contain an Open Knowledge Format v0.2 bundle at
`specs/`. It is the human-readable source of truth for observable product
behavior: goals, actors, user scenarios, rules, errors, edge cases, acceptance
criteria, and non-goals. It is not a task log, implementation plan, generated
report, or mirror of technical architecture.

The bundle uses Markdown concept files with YAML frontmatter, concept paths,
links, and an `index.md` for progressive disclosure. The minimal project type
is `Product Specification`; every concept has a nonempty `type`. An
implementation lifecycle status is not required because a specification may
describe intended behavior before implementation. Unknown metadata and
unrelated content must survive updates.

`docs/architecture.md` and `docs/testing.md` remain technical contracts.
Ephemeral plans, diagnoses, implementation summaries, and reviews remain task
artifacts outside the repository. A specification may link to technical
documentation or tasks, but those concerns are not duplicated into `specs/`.
KOS stores neither OKF files nor an implementation-status projection of them.

## Development, Review, And Publication

Implementation changes the task worktree without creating a commit. It also
runs the checks required by the project against the current uncommitted state.
The agent chooses those commands; KOS neither stores nor interprets their
results. There is no separate check transition in a built-in workflow.

Documentation follows implementation and precedes review. Product behavior
changes update `specs/` through `okf`; implementation-only work records why no
product specification changed. The resulting code, tests, and documentation
form one diff.

Review is performed by another agent against the current diff and related
files. It is read-only for the task worktree but writes its external
`review.md`. Requested changes return to implementation, then documentation and
review; a material design error returns to planning. KOS does not bind review
to a SHA.

The first commit is created during publication. Publication must:

1. Verify the project, worktree, and diff.
2. Fetch the current remote default branch.
3. If the base moved, safely update the worktree and return `base_moved` so
   implementation checks, documentation, and review repeat.
4. Otherwise stage only task files and create one commit containing the task
   number in its message.
5. Push without force and observe the remote result.
6. The publication step writes `publish.md` and returns `published`.

KOS does not store the commit SHA. If publication is interrupted, the next
session observes Git first. It does not duplicate an already remote commit,
continues a verified local commit without making another, or moves a local
commit back to uncommitted changes on a changed base before repeating the
post-plan workflow. Ambiguous state produces `blocked`.

## CLI Contract

The normal agent protocol consists of:

```text
kos task create
kos task create-and-claim
kos task claim-next
kos task claim <task-id>
kos task resumable
kos task show-owned
kos task show <task-id>
kos task resume
kos task report-attempt
```

`create` accepts project, a task type key or administrative numeric ID, title,
Markdown description, optional parent, and optional blockers, then stores the
type's current workflow ID. `create-and-claim` additionally accepts an owner and
atomically returns the newly created active task. User-facing commands use
built-in keys and never require `KOS_TASK_TYPE_ID`.

Before `create-and-claim`, `/kos-fix` and `/kos-brief` atomically persist a
local command intent containing the non-secret owner ID and request digest.
`show-owned` reads the one active task for that project and owner without
changing it. After a lost create response, the same or a restarted command
loads the intent and observes that task before any retry. No task means the
idempotent operation may be retried with the same owner and exact definition;
one exact task proves success; a different definition, owner collision, or
multiple result is a conflict. The server returns the existing exact task
instead of creating a duplicate when the first transaction committed. The
intent is removed only after the task identity is durable locally. Owner IDs
used for this operation must be unique per command intent.

`claim-next` may filter by one task type key and atomically selects a pending
task of that type with no incomplete blocker. `claim` atomically claims one
specified pending task with the same blocker, status, and ownership checks.
Both return the description, workflow, current instruction, artifact template,
and claim. Paused and active tasks require explicit resume.

`resumable` returns only `active`, `needs_human`, or `blocked` tasks for one
project and built-in type without changing ownership; pending tasks remain the
exclusive concern of typed claim operations. A slash command first resumes the
task associated with its durable command intent. Without an intent, it may
present resumable titles and ask whether to continue one before selecting or
creating work, without requiring the user to enter an internal ID; a new fix or
brief request is never silently replaced by unrelated existing work. An active
task can be taken over only after confirmation that its former process stopped.
A `needs_human` task repeats its stored question and records the answer sidecar
before resume. A `blocked` task resumes only after its technical cause is
observably resolved.

`show` reads status, step, ownership, description, workflow, and current
instruction without changing ownership. `resume` replaces ownership and keeps
the current step. `report-attempt` sends only the execution identity and
outcome, not Markdown, SHA, checkpoint, or universal state.

Administrative operations may register projects, update or rename-transfer an
existing project in place, register workflows and task types, update unclaimed
descriptions and dependencies, and cancel tasks.

Brief graph materialization is one fenced, transactional operation. It accepts
the complete child definitions with local keys and sibling blockers plus the
retained expected digest. It requires the current brief owner and claim version
at the permitted publication point, canonicalizes and revalidates the graph,
and compares the digest before inserting any child. A mismatch rejects the
whole mutation. A read-only operation returns the complete immediate child
graph so a lost response can be recovered by exact comparison without duplicate
tasks. A read-only validation mode runs the same definition, cycle, project,
and duplication checks before review is considered publishable, but creates no
rows or durable validation state. It returns a digest of the canonical
definition. Successful materialization returns the same digest; the
orchestrator also requires the submitted bytes to match its retained reviewed
proposal.

## Acceptance

The built-in-scenario version is complete only when tests or real scenarios
prove the foundation and all of the following:

1. Projects are registered without local paths.
2. Used workflows are immutable and tasks retain a concrete workflow ID.
3. Two sessions cannot hold one valid claim, and stale claim versions fail.
4. Incomplete blockers prevent claims and dependency cycles are rejected.
5. Invalid workflow transitions fail; pauses preserve the current step.
6. Rails restart preserves task state and OpenCode restart resumes from files.
7. Separate tasks retain uncommitted changes in separate worktrees.
8. No commit exists before publication; planning, diagnosis, and review are
   read-only where required.
9. A moved base causes implementation checks, documentation, and review to
   repeat.
10. Publication creates one commit, pushes, and verifies the remote result.
11. A clean installation contains all three built-in task types and workflows
    without hand-written workflow JSON.
12. Interruption around commit and push recovers by observing Git without a
    duplicate commit.
13. `/kos` claims only development work, while `/kos-brief` and `/kos-fix`
    create and claim the exact requested built-in type without numeric IDs.
14. Product behavior is documented in a conformant `specs/` bundle before
    review, while technical contracts and task artifacts remain separate.
15. Brief publication precedes atomic child creation, and interrupted graph
    creation recovers without duplicates or prematurely available children.
16. Real invocations of all three commands complete their scenarios without
    manual internal commands or a separate built-in `check` transition.
17. Lost create responses and interrupted or paused commands resume through
    durable intent, ownership observation, and answer sidecars without duplicate
    tasks or user-entered internal IDs.

## Explicit Exclusions

The built-in-scenario version excludes cross-host active-task migration, a web
UI, multiple AI runtimes, a runtime broker, server-started OpenCode, heartbeat,
random claim tokens, checkpoints, universal task state, full attempt history,
artifact tables or graphs, gates, evaluators, candidate/base SHA state,
review-to-commit binding, pre-publication commits, universal result schemas,
condition languages, parallel steps within one task, automatic conflict
resolution, force-push, automatic deletion of unknown worktrees, mandatory
retrospectives, Langfuse on the critical path, a Rails OKF parser, an OKF status
registry, a site generator, arbitrary task-graph import, and production-release
machinery before the three core scenarios are proven.

The governing constraint is that KOS must remain a strict external memory and
simple coordinator, not become a general-purpose workflow engine.
