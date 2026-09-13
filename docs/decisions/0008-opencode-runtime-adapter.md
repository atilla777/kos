---
title: OpenCode Runtime Adapter
status: accepted
date: 2026-09-13
---

# ADR-0008: OpenCode Runtime Adapter

## Context

KOS needs one operational runtime before it can ship canonical orchestration and workflow-step skills. The runtime must discover project-local skills, run non-interactively in a reserved task worktree, isolate a workflow-step dialogue in a child session, and return a typed repository-effect result to that same child before accepting its final manifest.

OpenCode 1.18.26 exposes project-local skills, JSON event output, and a foreground `task` tool. A completed task call identifies its child session in a runtime-generated wrapper and event metadata, and another task call can continue that session. OpenCode does not make this transport a KOS state or security boundary, and child text remains untrusted model output.

## Decision

OpenCode 1.18.26 is the first and only initially supported runtime version. A later version is supported only after it passes the complete executable adapter contract; an untested semver range is not accepted.

KOS installs skills under `.opencode/skills/<skill-name>/SKILL.md`. An orchestration session runs non-interactively with JSON events and the reserved task worktree as its explicit working directory. It launches `kos-workflow-step` through a foreground task call so the parent waits for each child turn.

The adapter obtains the opaque child session identifier from the runtime-generated completed Task wrapper, not from the nested child-generated text. A process adapter also cross-checks that identifier against event metadata. An OpenCode plugin guard retains that identifier per parent session and rejects a continuation Task call before execution unless its `task_id` is the retained value. The child text must contain exactly one JSON document that validates as either a version 1 effect request or a final result manifest. After an effect request, the orchestrator validates and executes the existing durable effect protocol, then continues the retained child session with the complete version 1 effect result. A child session change, malformed wrapper, mixed prose, invalid JSON, invalid schema, unexpected turn, or identity and digest mismatch fails closed.

The executable contract is tested against the real pinned OpenCode binary in isolated home, configuration, data, cache, and state directories. A deterministic loopback model endpoint drives the tool sequence, so provider credentials, user configuration, network availability, and probabilistic model behavior are not part of compatibility verification.

## Consequences

- The initial compatibility claim is narrow but reproducible.
- Workflow policy and durable effect handling remain in KOS; OpenCode provides session routing and tool execution only.
- OpenCode child session identifiers remain ephemeral runtime routing data and are not persisted as task, attempt, or artifact identity.
- Runtime parsing must understand the pinned OpenCode task event and wrapper shape while keeping the nested KOS document schema-validated.
- The OpenCode adapter installation needs a plugin guard in addition to skills. Model-generated Task arguments remain untrusted and cannot continue a session without matching the guard's runtime-retained identifier.
- Retrospective hooks and post-primary delivery require a separate adapter increment.

## Rejected Alternatives

### Trust a compatible-looking OpenCode version range

Minor runtime changes can alter event, task, permission, or session behavior. Declaring a range without executing the complete contract would make installation compatibility speculative.

### Return an effect request as the final workflow-step result

Starting a new child after the effect would lose the dialogue that produced the request and would let evidence be finalized outside the original workflow-step session.

### Let the workflow-step call KOS or `kos-repository` directly

That bypasses the lease-owning orchestrator, durable effect intent, fencing, allowlist, and reconciliation boundaries.

### Use an external provider in compatibility tests

Credentials, network behavior, cost, and nondeterministic model output would make the adapter contract unsuitable for the required project check.
