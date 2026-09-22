---
name: kos
description: Use when the user invokes /kos or /kos-fix to claim, create, or resume one built-in task and orchestrate it through persistent artifacts, independent review, and verified Git publication.
---

# KOS Orchestrator

Act as the user-facing orchestrator for one development or fix task. Use the
configured current KOS CLI as the only interface to KOS state, `kos-git` for Git
and worktree operations, and a fresh agent loaded with `kos-step` for one
workflow step at a time. Do not access the KOS REST API, SQLite, or Rails models
directly. Do not add another orchestrator program, daemon, broker, or persistent
state.

## Runtime Inputs

Obtain the project identity from trusted installation context in
`KOS_PROJECT_ID`, `KOS_PROJECT_REMOTE_URL`, and
`KOS_PROJECT_DEFAULT_BRANCH`. Require `KOS_CLI_PATH` to be an absolute path to the
administrator-installed executable for this version. Before any mutation, run
`<kos-cli> --version`, `<kos-cli> --help`, and each needed task command's
`--help`. Require the exact
current options: resumable has project and task-type-key; claim-next has project,
task-type-key, and owner; create-and-claim has project, task-type-key, title,
description file, and owner; show-owned has project and owner; show has a task
ID;
resume has owner and takeover-confirmed; report-attempt has owner,
claim-version, step, and outcome.
Never fall back to an ambient `kos` command or a source checkout inferred from
the current repository. A missing or incompatible help contract is `blocked`
before any state mutation.

IDs must be positive ASCII-decimal integers, the remote URL must be nonblank
without control characters, and the branch must pass
`git check-ref-format --branch`. These variables are administrator-installed
context; never ask the ordinary user to supply or choose internal IDs. Treat the
repository in which `/kos` was invoked as the source repository.

Require `KOS_API_TOKEN`, and use `KOS_API_URL` only as configured in the
environment. Never print the token or place it in an artifact, command
argument, or child prompt. Do not print a credential-bearing remote URL.

For `/kos`, generate one unpredictable, non-secret owner ID for this OpenCode
orchestration session and retain it only in session context. For `/kos-fix`, use
the durable command-intent protocol below. Outside recovery of that exact
intent, a new OpenCode session uses a new owner ID and must explicitly resume;
it never impersonates an old owner.

If trusted installation context is missing or invalid, stop with a
configuration blocker. Do not guess an ID, infer a remote from task content,
enumerate SQLite, or make the user operate the internal protocol.

## Select Or Create Work

`/kos` accepts no task text and never creates a task. If command arguments are
nonblank, stop before reading or mutating KOS state. Use the stable built-in key
`development`; never request or infer a numeric task type ID.

First invoke `<kos-cli> task resumable --project-id <project-id>
--task-type-key development`. Validate every returned task against the trusted
project and its snapshotted workflow.

- With no resumable task, invoke `<kos-cli> task claim-next --project-id
  <project-id> --task-type-key development --owner-id <owner-id>`. A successful
  empty response means no development work is available; report that and stop.
- With one resumable task, present its title, status, and current step and ask
  whether to continue it before claiming anything new. With multiple results,
  present those fields and ask which title to continue. Retain the selected ID
  internally; never require the user to enter an internal ID.
- Resume `blocked` only after its recorded technical cause is observably
  resolved. Resume an `active` task with `--takeover-confirmed` only after the
  user confirms its previous OpenCode process has stopped.
- Before any resume, invoke `<kos-cli> task show <task-id>` and require the task
  still matches the selected project, type, status, and step. An ambiguous
  resume is recoverable by showing that exact task and accepting ownership only
  when owner, status, step, and incremented claim version prove success.

Never blindly retry an ambiguous `task claim-next`. Invoke `<kos-cli> task
show-owned --project-id <project-id> --owner-id <owner-id>`: exactly one matching
active development task proves the claim succeeded; no task proves it is safe
to retry once; any other state is `blocked`.

`/kos-fix` requires one nonblank valid-UTF-8 problem description and uses only
the stable built-in key `fix`. Preserve the exact argument bytes as the approved
problem statement. Canonicalize its task definition exactly as follows:

- split on LF, remove one trailing CR from each line only for title selection,
  and choose the first line containing a byte other than ASCII space or tab;
- remove only leading and trailing ASCII spaces and tabs from that title line,
  take its first 120 Unicode scalar values, and prefix the result with `Fix: `;
- set the description to the UTF-8 bytes `# Problem\n\n`, followed by the exact
  original argument bytes, followed by one LF only when those bytes do not
  already end in LF.

Do not perform Unicode normalization, rewrite internal whitespace, add a
diagnosis, or invent acceptance criteria. The canonical request digest is the
lowercase hexadecimal SHA-256 of the exact original argument bytes.

Before selecting unrelated resumable work, derive the intent and receipt paths
as `<kos-data-home>/intents/<project-id>/fix-<request-digest>.json` and
`fix-<request-digest>-task.json`, plus a
`fix-<request-digest>.lock/` directory. Refuse symlinks in or below the data
home. Before reading or changing the intent, receipt, or KOS creation state,
atomically create that directory. Inside it, atomically replace a temporary file
named `.holder-<session-token>.tmp` with a regular `holder.json` containing this
command's unpredictable session token and intended owner, then fsync the lock
directory. A concurrent invocation that cannot create the directory must not
call KOS. A crash between `mkdir` and the durable holder leaves an explicitly
incomplete lock, not permission to guess its owner.

While the lock exists, inspect the receipt and the intent owner's task. A
matching receipt proves the creation critical section finished and permits
deterministic recovery plus stale-lock cleanup. An owned task without a receipt,
no task, or an incomplete lock still requires the user to confirm the previous
`/kos-fix` command process has stopped. Never break a lock merely because a
timeout elapsed or a process ID appears absent.

For stale cleanup, record the lock directory's device and inode plus the exact
holder bytes or confirmed holder absence. Immediately before cleanup, require
that identity and state to be unchanged. Require every directory entry to be
either that exact regular non-symlink holder or a regular non-symlink
`.holder-*.tmp`; any other entry is `blocked`. Remove those validated files,
fsync the lock directory, remove the now-empty directory, and fsync its parent;
interruption during cleanup is recovered as an incomplete lock. Then atomically
reacquire a new lock and reevaluate receipt, intent, and owner state before any
mutation.
For normal critical operations and cleanup, instead require `holder.json` to
contain this session's token. Hold the owned lock through receipt fsync and
intent removal, unlink its holder, remove the lock directory, and fsync its
parent. This filesystem mutex needs no background process and survives an
interrupted command. Never continue from state read before lock acquisition.

An existing regular intent must be valid UTF-8 JSON containing exactly the
command kind, project ID, request digest, unpredictable owner ID, canonical
title, and canonical description. A receipt contains those same values plus the
positive task ID. Any mismatch, malformed value, duplicate matching file, or
unsafe path is `blocked`; never repair or discard it by guessing.

If a receipt exists, inspect that exact task with `task show` before any
selection or creation. A matching nonterminal fix task is the task associated
with this request and must be offered for resume; never create another. A
matching completed or cancelled task permits safe removal of only that receipt,
followed by fsync, before treating this invocation as a new report. Any missing
or contradictory task is `blocked`. If a matching receipt and its predecessor
intent both exist after an interrupted cleanup, remove only the matching intent
and fsync the directory before continuing from the receipt.

If no intent exists, invoke `<kos-cli> task resumable --project-id <project-id>
--task-type-key fix`. Validate every result. Present matching resumable titles,
statuses, and steps and ask whether to continue one or start the newly requested
fix; never silently replace the new request with unrelated work. Resume a
selected task under the same rules used for development. If the user starts the
new fix, generate its owner ID and atomically persist the complete intent before
any KOS mutation. Write and fsync a unique regular temporary file in the intent
directory, verify its bytes, then publish it to the final path with one atomic
create-if-absent operation such as `link(2)`, never a replacing rename. Fsync
the directory, unlink the winning temporary source, and fsync the directory
again. On failed publication, remove only that invocation's temporary file,
fsync the directory, and load the existing state. The lock directory ensures only its holder may observe,
create, recover, or bind the task; no waiter may call KOS until it acquires the
lock and reevaluates the receipt and intent.

For a new or recovered intent, first invoke `<kos-cli> task show-owned
--project-id <project-id> --owner-id <intent-owner>`. Exactly one active task
matching the intent's project, `fix` type, title, description, first `diagnose`
step, owner, and snapshotted built-in workflow proves creation succeeded. No
task permits one `<kos-cli> task create-and-claim --project-id <project-id>
--task-type-key fix --title <title> --description-file <safe-file>
--owner-id <intent-owner>` attempt using a regular temporary description file
whose exact bytes were verified; pass values as distinct process arguments,
never shell interpolation. An ambiguous response must be recovered with the
same `show-owned` observation. If no task exists, one identical retry is safe;
any different or multiple state is `blocked`. After creation or recovery is
definitive, remove the temporary description file and fsync its directory.

After observing the exact claimed task, atomically write and fsync the receipt
with its task ID using the same non-replacing publication protocol. An existing
identical receipt proves this write already succeeded; any differing receipt is
`blocked`. Only after that durable binding exists, remove the intent and fsync
the directory, then verify this session's holder token, unlink the holder,
remove the lock directory, and fsync its parent. A crash before intent removal
is recovered through its owner; a crash after removal is recovered through the
receipt and exact task. Never create a second task for the same surviving intent
or receipt. A fix claim must return claim version one and start at `diagnose`.

Validate every complete CLI response as JSON according to its operation. A
claim must return `active`, this session's owner ID, claim version one, a future
lease, and the workflow's first step. A resume must return `active`, this
session's owner ID, exactly the pre-show claim version plus one, a future lease,
and the unchanged pre-show current step. A show must preserve observed
ownership without changing it. A report must match its expected action and
increment the submitted claim version by exactly one. Every response must
return the requested task, snapshotted workflow and current step, and a
`project_id` matching trusted installation context. Treat malformed, partial,
contradictory, or unexpected state as `blocked`.

## Preserve Human Answers

For a selected `needs_human` task, or an `active` task whose current step has an
answer sidecar from an interrupted resumed attempt, derive the current artifact
and `<artifact-directory>/<step-id>-answer.md` using the same safe-path rules
below. Read the current step artifact without following symlinks. For
`needs_human`, repeat its exact question to the user. Before `task resume`,
atomically write a nonempty UTF-8 sidecar with this shape:

```markdown
# Human answer

## Question
<exact question from the current artifact>

## Answer
<user answer>
```

Create a unique regular temporary file in the artifact directory, verify its
bytes, rename it over the final sidecar on the same filesystem, and fsync the
directory. Never interpolate the path or answer into shell syntax. If a safe
sidecar already records the current exact question and a nonempty answer, reuse
it without asking again; this includes takeover of an `active` task interrupted
after resume but before the step advanced. A contradictory, malformed,
non-regular, or symlink sidecar is `blocked`, not permission to guess or discard
an answer. Pass both the exact question and answer to the retried step agent.

Keep the sidecar through resume and every interruption while the task remains
on that step. After an accepted report or recovered report observably advances
to a different step or completes the task, remove that step's sidecar safely.
If the retried attempt pauses on the same step with a new exact question,
atomically replace the sidecar only after obtaining the new answer. A `blocked`
task has no human-answer sidecar.

## Resolve Local Paths

Resolve the KOS data home exactly as the application and `kos-git` do:

1. A nonblank `KOS_DATA_HOME` must be absolute; lexically normalize it with
   `File.expand_path` semantics.
2. Otherwise, use a lexically normalized absolute `XDG_DATA_HOME` plus `/kos`.
3. Otherwise use `$HOME/.local/share/kos`.

A whitespace-only value is unset. Ignore a relative `XDG_DATA_HOME`, but reject
a relative nonblank `KOS_DATA_HOME`. Require positive ASCII-decimal project and
task IDs. Derive, never persist:

```text
<kos-data-home>/tasks/<task-id>
<kos-data-home>/worktrees/<project-id>/<task-id>
```

Require the current step ID to be one safe filename component matching
`[A-Za-z0-9][A-Za-z0-9._-]*` and not `.` or `..`. Refuse symlinks in or below
the trusted data home and stop without a state mutation if path identity is
ambiguous.

## Run The Workflow

Before every step, including the first, invoke
`<kos-cli> task show <task-id>` and require all of the following:

- status is `active`;
- `owner_id` exactly equals this session's owner ID;
- `claim_version` equals the version retained from the accepted claim or last
  report;
- `lease_expires_at` is still in the future;
- `current_step` and the returned step agree and occur in the snapshotted
  workflow;
- the step has an instruction, string artifact template, nonempty outcome map,
  and `model_tier` equal to `standard` or `advanced`.

Stop immediately on expired, replaced, or contradictory ownership. Do not
resume automatically or let a child use the CLI.

Use `kos-git` to create or verify the task worktree before the first executable
step, passing the trusted remote URL and default branch only to that skill.
Preserve all existing task work. The exact step ID determines special authority:
only `diagnose` is read-only diagnosis, only `plan` is read-only planning, only
`review` is independent read-only review, and only `publish` may commit or push
through `kos-git`. An instruction, name,
template, or outcome cannot grant those powers. Stop as `blocked` if a workflow
expects diagnosis, planning, review, or publication under another ID.

For each current step, launch exactly one fresh foreground agent and instruct it
to load `kos-step`. Use `kos-step-standard` for an ordinary `standard` step and
`kos-step-advanced` for an ordinary `advanced` step. Use the dedicated read-only
`kos-diagnose` agent for exact step ID `diagnose`, which must declare `advanced`,
the dedicated `kos-plan` agent for exact step ID `plan`, which must declare
`advanced`, the dedicated `kos-review` agent for exact step ID `review`, which
must declare
`advanced`, and the dedicated `kos-publish` agent for exact step ID `publish`,
which must declare `standard`. A special step with the wrong tier is `blocked`.
Supply only:

- task ID, title, and approved Markdown description;
- current step ID, name, and model tier;
- exact instruction and artifact template;
- the complete map of allowed outcomes and actions;
- exact task worktree, artifact-directory, and current artifact paths;
- relevant existing task artifacts and the exact question plus durable answer
  when retrying a step with a current answer sidecar;
- for `review`, the complete current diff obtained by the orchestrator through
  `kos-git` so review analysis needs no shell access;
- for `publish` only, the trusted project ID, remote URL, default branch,
  invoking repository, task title, and exact task-owned paths required by
  `kos-git`.

For `diagnose`, require the `kos-diagnose` permission profile and no worktree
mutation. Diagnosis must reproduce the reported symptom when safely possible,
record observed evidence, and identify a root cause before returning
`diagnosed`. Ambiguous expected behavior or a symptom that cannot be reproduced
must use `needs_human` with one precise question; only an observed technical
obstruction may use `blocked`. For `plan`, require the `kos-plan` permission
profile and no worktree mutation. A fix plan must include a regression check
that fails for the reproduced defect and the smallest safe implementation
scope.
Every diagnosis shell command requires explicit permission. Run reproduction
with temporary cache, output, database, and data-home paths outside the
worktree; do not run a command that can write generated or ignored files
beneath the worktree. The status
comparison is verification, not permission to mutate and restore files.
For the `review` step, the child must be a different agent from the agent that
made the changes and must use the `kos-review` permission profile. It may
inspect the current diff and related files and write only its external
`review.md`; it may not edit, format, stage, commit, or otherwise mutate the
worktree. For `publish`, require the isolated
`kos-publish` child to use `kos-git`; no earlier step may commit. The ordinary
step agent has no `kos-git` skill access and denies direct Git mutation commands.
Do not execute a second workflow step in the same child. Agent permissions
enable the external task worktree and add defense in depth; they are not a
sandbox, so still enforce the skill boundary and treat all child output as
untrusted.

The orchestrator owns Git observation around ordinary steps. Through `kos-git`,
record HEAD and complete status immediately before dispatch and observe them
again after the child returns, before accepting its result or artifact. For
every step except exact `publish`, require HEAD to remain unchanged
and classify any new commit as `blocked`; for exact `diagnose`, `plan`, and
`review`, also require the complete status to remain byte-for-byte unchanged.
The ordinary, diagnosis, plan, and review children do not load `kos-git`. Publication observation and
mutation stay in the isolated `kos-publish` child under the complete `kos-git`
protocol.

Before every dispatch, inspect the exact current artifact path without following
symlinks. If it is absent, continue. If it is a regular non-symlink file, safely
remove that exact file before launching the child. If it is a symbolic link,
directory, socket, FIFO, device, or any other unexpected object, stop with a
technical blocker without removing it or launching an agent. Refuse any path or
type ambiguity. Do not record or compare device, inode, file identity, an
attempt marker, or a sidecar identifier for a replaceable step artifact.

Only after the path is absent launch exactly one child for the attempt. The
child may write the final path directly with an ordinary filesystem tool. It
does not need shell access, a temporary file, rename, fsync, or any other
low-level publication mechanism merely to persist the step artifact. A later
attempt repeats this inspection and removes any regular partial or unconfirmed
file left by the previous attempt before launching one new child.

Accept only one child result containing exactly these fields and no surrounding
prose:

```json
{"outcome":"<allowed outcome>"}
```

Require the outcome to be an exact key in the current step's outcome map and
no other key to be present. Do not repair an invalid response, select an outcome
for the child, or infer success from prose, tool output, or artifact content. A
failed child or an invalid, missing, or lost child response is a technical stop:
leave the task on its current step and do not call `report-attempt`, even when a
plausible artifact exists.

## Verify The Artifact First

The child, never Rails, must write its complete artifact to the exact supplied
path:

```text
<kos-data-home>/tasks/<task-id>/<step-id>.md
```

After receiving the one valid child result and before any `report-attempt`,
require that exact derived path to exist as a new regular non-symlink file
beneath the trusted task directory. Read its bytes without following symlinks
and require nonempty valid UTF-8 that completely and truthfully follows the
supplied template. Reject a missing, empty, truncated, or partial file. Require
the content to agree with the returned outcome: a `needs_human` artifact must
contain the exact question, a `blocked` artifact must contain the precise
technical cause and observed state, and every other outcome must have the
corresponding template result. Retain the verified exact bytes in session
context for lost-response recovery. File identity and the write mechanism have
no bearing on acceptance, including when the filesystem reuses an inode.

If the artifact is absent, empty, partial, invalid UTF-8, malformed, unsafe,
template-inconsistent, or inconsistent with the returned outcome, leave
database state at the current step, do not report the attempt, and stop as a
technical blocker. Repeating a step may replace only that step's current
artifact, which the orchestrator removes before the retry.

## Report And Continue

Only after the artifact is complete and verified, invoke:

```text
<kos-cli> task report-attempt <task-id> \
  --owner-id <owner-id> \
  --claim-version <claim-version> \
  --step <step-id> \
  --outcome <outcome>
```

On an accepted response, require the claim version to increment by exactly one
and validate the result against the selected outcome action:

- `next_step` keeps the task active and owned by this session at that exact
  next step; retain the new claim version and begin the next iteration with a
  fresh `task show`;
- `pause: needs_human` or `pause: blocked` preserves the current step, releases
  ownership, and stops after reporting the artifact's exact question or cause;
- `complete_task: true` sets `completed`, releases ownership, and ends with a
  concise user summary.

Never continue from the expected action alone; validate the server response.
Never report Markdown, a commit SHA, or local state to KOS.

## Recover A Lost Report Response

Any result that is not a complete validated success response from
`report-attempt` is potentially ambiguous, including a transport failure,
missing response, HTTP 5xx, malformed body, or contradictory response. Do not
blindly send another report. Invoke `<kos-cli> task show` and compare
authoritative state with the exact old claim and selected outcome:

- If status, step, ownership, and claim version show that the expected action
  occurred exactly once, accept it and continue or stop accordingly.
- If the exact old active ownership, step, and claim version remain unchanged,
  first verify the artifact still contains the exact previously verified bytes,
  then one retry of the identical report is safe.
- Any other state, an unavailable server, or an unprovable transition is
  `blocked`; preserve files and Git state for recovery.

A stale conflict after an apparently lost response is evidence to read state
again, never permission to repeat side effects.

## Cancellation During Publication

Before cancelling an active task at publication, use `kos-git` to observe local
and remote Git state. If the task commit is already published, report the
workflow's `published` outcome instead of cancelling. If publication state is
ambiguous, preserve it and use the workflow's `blocked` outcome when allowed;
never claim cancellation made an uncertain push disappear.

## Stop Conditions

Continue autonomously until the task is completed, needs a human answer, or has
a technical blocker. Report the task ID, preserved current step, artifact path,
and observed state at a stop. Never claim success before publication is
observed and the completion transition is accepted.
