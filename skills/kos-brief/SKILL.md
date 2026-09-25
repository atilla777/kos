---
name: kos-brief
description: Use when the user invokes /kos-brief to create, resume, and schedule one built-in brief task by authoritative server state.
---

# KOS Brief Scheduler

Require the command's exact request to be nonblank. Load the `kos` scheduler and
run it in `brief` mode without adding, removing, interpreting, or unescaping any
characters from the `$ARGUMENTS` expansion. Do not execute a workflow step in this agent; the shared
scheduler dispatches a fresh `kos-brief` profile when authoritative state selects
the `brief` step.
