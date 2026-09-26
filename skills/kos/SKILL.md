---
name: kos
description: Shared scheduler for /kos, /kos-fix, and /kos-brief, driven by authoritative server state.
---

# KOS Scheduler

Schedule one task in `development`, `fix`, or `brief` mode. Load `kos-git` for
repository discovery and `kos-cli` for every public KOS operation. During
scheduling, do not access Rails, SQLite, the REST API, a task worktree, or task
Markdown.

Run `kos session-id` once to obtain this command's fresh canonical owner. Never
ask a model to generate randomness, read `KOS_OWNER_ID`, or reuse an owner.

## Select

Discover the invoking repository's canonical identity through `kos-git`, then
require its exact registered project through `kos-cli`.

- `development`: offer matching resumable work; otherwise use `task claim-next`
  for the `development` type. Never create a task.
- `fix` or `brief`: use `task create-or-get` with the mode, project, owner, and
  complete exact `$ARGUMENTS` expansion through standard input. Preserve every
  request byte; do not trim, infer argv, or interpret or unescape delimiters.

Read authoritative context. Keep a completed or cancelled task terminal; otherwise use the
public claim or resume operations when needed to make the chosen task active for
this owner. Present persisted pause information and require the corresponding
human answer, confirmed resolution, or confirmed stopped-owner takeover before
resuming. Follow `kos-cli` whenever a mutation's result is ambiguous. Retain
only the resulting positive decimal task ID.

## Schedule

Repeat:

1. Read `task context` for the task ID.
2. Stop successfully on `completed` or `cancelled`. On `needs_human` or `blocked`, show the
   persisted question or reason and stop.
3. Require `active` and inspect only the authoritative current step's
   `execution_mode` and `model_tier` for execution selection.
4. For `main`, load `kos-step` and execute exactly one step in this command
   agent. The step phase may read the task, evidence, and repository only as
   allowed by its authoritative workflow instruction.
5. For `subagent`, launch one fresh foreground `kos-step-standard` or
   `kos-step-advanced` child selected only by `model_tier`; its complete prompt
   is only the positive decimal task ID. Ignore its text and claimed result.
6. After either path, leave the step phase and reread context.

Never infer execution behavior from a step ID or task type. During scheduling,
never add context to a child prompt, inspect artifacts or Git, interpret child
output, report a step, mutate a graph, or keep local recovery state.
Authoritative server state is the scheduler result.
