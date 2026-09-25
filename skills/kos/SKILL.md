---
name: kos
description: Use when the user invokes /kos or /kos-fix as the scheduler for one built-in KOS task driven by authoritative server state.
---

# KOS Scheduler

Act only as the user-facing scheduler. Load `kos-cli` for every CLI operation.
Do not access Rails, SQLite, the REST API, task worktrees, Git, or task Markdown.

At command start, generate one cryptographically unpredictable owner ID such as
`kos-session-` followed by 32 lowercase hexadecimal digits. Keep it only in the
current scheduler session and pass it as one argument to exact claim or resume
operations. Never read `KOS_OWNER_ID`, derive an owner from a PID, task, request,
timestamp, or project, or reuse an owner from another command. A request-bound
fix uses this same owner for `task create-or-get`.

## Select Or Create

For `/kos`, reject nonblank arguments before any KOS call. Discover the project
through `kos-cli`, offer resumable `development` tasks by title, status, and
current step, or claim the next available development task with the generated
owner. Never create one.

For `/kos-fix`, require a nonblank UTF-8 problem, discover the exact project,
and invoke `task create-or-get` once with that project, kind `fix`, the generated
owner, and the complete exact request through standard input. If the transport
response is ambiguous, retry that identical operation once: the server-derived
creation key makes the retry safe without local recovery files. Require one
complete task response and retain only its positive ASCII-decimal ID.

Read authoritative context before dispatch. A newly created active task already
has this scheduler's owner. For an active task owned by an earlier invocation,
first require confirmation that its prior command process stopped, then exact
resume with the fresh owner and `--takeover-confirmed`. For `blocked`, show the
persisted reason and treat explicit reinvocation of the same request as
confirmation to recheck it, then exactly resume. For `needs_human`, show the
question and stop; never use the repeated problem text as its answer.

Before claiming new work, offer matching resumable work without exposing an
internal ID as a user choice. Repeat a persisted `needs_human` question before
resume. Show a persisted `blocked` reason and resume only after it is resolved.
Require confirmation before taking over an active task whose prior process has
stopped. Use `kos-cli` observation rules for every ambiguous selection, claim,
or resume response. `create-or-get` alone permits one direct identical retry
after a transport failure because it is server-idempotent by the exact request.

## Schedule

Once selection, creation, or resume yields a positive ASCII-decimal task ID,
discard all dispatch context except that ID. Repeat this loop:

1. Read authoritative task context through `kos-cli`.
2. If server status is `completed`, stop successfully.
3. If server status is `needs_human`, show the persisted server question and
   stop for the user's answer.
4. If server status is `blocked`, show the persisted server reason and stop.
5. Require server status `active`, then choose the profile from the exact
   `current_step` map below.
6. At `publish`, treat a built-in context without the current `review_invalid`
   outcome as an immutable pre-verification snapshot. Dispatch `kos-publish`
   only so it can persist the required migration block; never treat it as
   publication-capable.
7. Launch exactly one fresh foreground child. Its complete prompt is the task
   ID's decimal digits and nothing else.
8. Await the child, ignore all textual output and claimed outcome, then return
   to step 1 and reread authoritative state.

Built-in exact-step dispatch:

| Current step | Profile |
| --- | --- |
| `diagnose` | `kos-diagnose` |
| `plan` | `kos-plan` |
| `implement` | `kos-implement` |
| `document` | `kos-document` |
| `brief` | `kos-brief` |
| `review` | `kos-review` |
| `publish` | `kos-publish` |
| `verify` | `kos-verify` |

An exact built-in step always uses its exact profile regardless of model tier.
An unknown custom step may use `kos-step-standard` or `kos-step-advanced` only
according to the authoritative tier. Never route an unknown step by guessing.

The child prompt must not contain a description, workflow, outcome names, model
tier, path, project ID, diff, Git fact, artifact, question, answer, owner, or
claim version. Do not read or validate Markdown, inspect Git, parse child
results, infer an outcome, call `report-attempt`, or maintain step receipts,
pending submissions, manifests, or files under `tasks/<id>/`. Server state is
the only scheduler result.
