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

The first version must prove one real path:

```text
create task -> develop -> check -> independent review -> publish -> complete
```

No general-purpose mechanism is added before this path works end to end in
OpenCode.

## System Boundary

The first version runs on one execution host containing Rails, SQLite, the KOS
CLI, OpenCode and skills, KOS data, and task worktrees. Different tasks may run
in parallel in separate worktrees. Moving an unfinished active task to another
host is unsupported.

The user's single entry point is `/kos`, with optional free-form text. Users do
not manually manage workflow IDs, claim versions, leases, internal API calls,
worktree paths, or internal step outcomes.

A first installation creates an empty database. Projects, workflows, task
types, and tasks are added through administrative operations.

## Responsibilities

KOS is responsible for:

- storing projects, workflows, task types, tasks, and dependencies;
- making used workflows immutable;
- selecting the next available task;
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

The `/kos` skill is the user entry point and orchestrator. It discusses and
creates or selects a task, claims it, asks KOS for the current step, invokes a
step executor, reports the outcome, and continues until publication, a human
question, or a technical stop. There is no separate orchestrator program.

The generic step executor receives the task description, current step,
instruction, artifact template, model tier, worktree path, artifact directory,
and exact artifact path. It runs only that step, atomically writes the current
Markdown artifact, and returns one allowed outcome.

The Git skill creates and verifies worktrees, observes actual Git state,
preserves uncommitted changes, updates from the default branch, commits only at
publication, pushes without force, and observes the remote result before
retrying an ambiguous operation.

## Data Model

The first version has exactly five domain tables:

| Table | Required purpose and fields |
| --- | --- |
| `projects` | `id`, `name`, `remote_url`, `default_branch`, timestamps |
| `workflows` | `id`, `name`, `definition_json`, `created_at` |
| `task_types` | `id`, `name`, `workflow_id`, timestamps |
| `tasks` | `id`, `project_id`, `task_type_id`, `workflow_id`, optional `parent_id`, `title`, `description_markdown`, `status`, `current_step`, `owner_id`, `claim_version`, `lease_expires_at`, timestamps |
| `task_dependencies` | Blocking relationships between tasks |

A project does not store local paths, custom worktree paths, or allowed task
types. Tools derive local paths at runtime.

Each workflow row is one complete immutable revision. Once a task uses it, its
JSON cannot change. A change creates a new workflow row; no separate version
number is needed.

Task types are global. A new task copies the type's current `workflow_id` into
the task, so later type changes do not affect existing tasks.

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
cancelled task remain unavailable. Before cancelling during publication, `/kos`
must observe local and remote Git state: an already published change is
reported as published, while ambiguity produces `blocked`.

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

The step executor atomically replaces an artifact through a temporary file and
rename before returning its outcome. The orchestrator verifies the exact
artifact and proves its file identity changed during the attempt before
reporting the outcome to KOS. It must never advance database state before the
artifact is complete.

Worktree paths are derived, not stored. The Git skill creates a worktree from
the repository where `/kos` was invoked and verifies that its remote matches
the project's `remote_url`. Unknown, mismatched, or ambiguous worktrees are not
deleted automatically; the task becomes `blocked`.

## Development, Review, And Publication

Development changes the task worktree without creating a commit. Its result is
the worktree, current diff, and `develop.md`.

Checks inspect the current uncommitted worktree. The agent chooses commands
from project rules; KOS neither stores nor interprets their results.

Review is performed by another agent against the current diff and related
files. It is read-only for the task worktree but writes its external
`review.md`. Requested changes return to development, checks, and review. KOS
does not bind review to a SHA.

The first commit is created during publication. Publication must:

1. Verify the project, worktree, and diff.
2. Fetch the current remote default branch.
3. If the base moved, safely update the worktree and return `base_moved` so
   checks and review repeat.
4. Otherwise stage only task files and create one commit containing the task
   number in its message.
5. Push without force and observe the remote result.
6. The publication step writes `publish.md` and returns `published`.

KOS does not store the commit SHA. If publication is interrupted, the next
session observes Git first. It does not duplicate an already remote commit,
continues a verified local commit without making another, or moves a local
commit back to uncommitted changes on a changed base before repeating checks
and review. Ambiguous state produces `blocked`.

## CLI Contract

The normal agent protocol consists of:

```text
kos task create
kos task claim-next
kos task show <task-id>
kos task resume
kos task report-attempt
```

`create` accepts project, type, title, Markdown description, optional parent,
and optional blockers, then stores the type's current workflow ID.

`claim-next` atomically selects a pending task with no incomplete blocker and
returns its description, workflow, current instruction, artifact template, and
claim. Paused and active tasks require explicit resume.

`show` reads status, step, ownership, description, workflow, and current
instruction without changing ownership. `resume` replaces ownership and keeps
the current step. `report-attempt` sends only the execution identity and
outcome, not Markdown, SHA, checkpoint, or universal state.

Administrative operations may register projects, workflows, and task types;
update unclaimed descriptions and dependencies; and cancel tasks.

## First-Version Acceptance

The first version is complete only when tests or a real scenario prove:

1. Projects are registered without local paths.
2. Used workflows are immutable and tasks retain a concrete workflow ID.
3. Two sessions cannot hold one valid claim, and stale claim versions fail.
4. Incomplete blockers prevent claims and dependency cycles are rejected.
5. Invalid workflow transitions fail; pauses preserve the current step.
6. Rails restart preserves task state and OpenCode restart resumes from files.
7. Separate tasks retain uncommitted changes in separate worktrees.
8. No commit exists before publication; review is independent and read-only.
9. A moved base causes checks and review to repeat.
10. Publication creates one commit, pushes, and verifies the remote result.
11. One real `/kos` invocation completes the entire flow without manual
    internal commands.
12. Interruption around commit and push recovers by observing Git without a
    duplicate commit.

## Explicit Exclusions

The first version excludes cross-host active-task migration, a web UI, multiple
AI runtimes, a runtime broker, server-started OpenCode, heartbeat, random claim
tokens, checkpoints, universal task state, full attempt history, artifact
tables or graphs, gates, evaluators, candidate/base SHA state, review-to-commit
binding, pre-publication commits, universal result schemas, condition
languages, parallel steps within one task, automatic conflict resolution,
force-push, automatic deletion of unknown worktrees, mandatory retrospectives,
Langfuse on the critical path, imports, and production-release machinery before
the core flow is proven.

The governing constraint is that KOS must remain a strict external memory and
simple coordinator, not become a general-purpose workflow engine.
