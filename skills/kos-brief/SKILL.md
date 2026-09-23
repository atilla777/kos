---
name: kos-brief
description: Use when the user invokes /kos-brief to create, resume, and schedule one built-in brief task by authoritative server state.
---

# KOS Brief Scheduler

Act only as the user-facing scheduler. Load `kos-cli`; never execute a workflow
step in the main agent. In particular, `brief` is now performed by a fresh
`kos-brief` profile because every step authority receives the task ID alone.

## Create Or Resume

Require one nonblank UTF-8 request and use the stable `brief` task type key.
Preserve the existing durable request-intent, lock, and task-receipt protocol
until a positive task ID is known. It may retain the exact request, canonical
title and description, owner, and digest so an ambiguous `create-and-claim` can
be recovered through `kos-cli` without duplication. A receipt for a completed
brief remains the permanent binding for that exact request.

Offer matching resumable brief work before creating unrelated work. Repeat a
persisted `needs_human` question before resume, show a persisted `blocked`
reason, and require confirmation before active takeover. Selection, creation,
claim, resume, and ambiguous-response recovery use only `kos-cli`.

## Schedule

After obtaining the task ID, retain only its positive ASCII-decimal digits.
Repeatedly read authoritative task context and dispatch exactly one fresh child:

| Current step | Profile |
| --- | --- |
| `brief` | `kos-brief` |
| `review` | `kos-review` |
| `publish` | `kos-publish` |
| `verify` | `kos-verify` |

The child's complete prompt is only the task ID. It contains no request,
description, workflow, outcomes, tier, path, project ID, diff, Git state,
artifact, graph, owner, or claim version. Await the child, ignore its textual
response and claimed result, reread task context, and dispatch from the new
exact `current_step`.

Stop only when server status is `completed`, `needs_human`, or `blocked`. At a
pause, show the persisted server question or reason. The scheduler does not
read or validate Markdown or graph files, inspect Git, parse outcomes, report
attempts, validate or materialize children, or maintain step artifacts,
manifests, submission receipts, or pending submissions. Those operations belong
to the fresh step authority and server-fenced CLI protocol.
