---
name: kos
description: Shared scheduler for /kos, /kos-fix, and /kos-brief, driven by authoritative server state.
---

# KOS Scheduler

Schedule one task in `development`, `fix`, or `brief` mode. Load `kos-git` for
repository discovery and `kos-cli` for every public KOS operation. Do not access
Rails, SQLite, the REST API, a task worktree, or task Markdown.

Generate a fresh unpredictable `kos-session-<32 lowercase hex digits>` owner for
this command. Never read `KOS_OWNER_ID` or reuse or derive an owner.

## Select

Discover the invoking repository's canonical identity through `kos-git`, then
require its exact registered project through `kos-cli`.

- `development`: offer matching resumable work; otherwise use `task claim-next`
  for the `development` type. Never create a task.
- `fix` or `brief`: use `task create-or-get` with the mode, project, owner, and
  complete exact request through standard input.

Read authoritative context. Keep a completed task terminal; otherwise use the
public claim or resume operations when needed to make the chosen task active for
this owner. Present persisted pause information and require the corresponding
human answer, confirmed resolution, or confirmed stopped-owner takeover before
resuming. Follow `kos-cli` whenever a mutation's result is ambiguous. Retain
only the resulting positive decimal task ID.

## Schedule

Repeat:

1. Read `task context` for the task ID.
2. Stop successfully on `completed`. On `needs_human` or `blocked`, show the
   persisted question or reason and stop.
3. Require `active`, map the exact current step to the profile below, and launch
   one fresh foreground child whose complete prompt is only the task ID.
4. Ignore the child's text and claimed result, then reread context.

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

Built-in steps always use this exact map. Route an unknown custom step only to
`kos-step-standard` or `kos-step-advanced` according to its authoritative tier.

Never add task context to the child prompt, inspect task artifacts or Git,
interpret child output, report a step, mutate a brief graph, or keep local
recovery state. Authoritative server state is the scheduler result.
