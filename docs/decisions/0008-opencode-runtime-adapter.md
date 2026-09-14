---
title: OpenCode Runtime Adapter
status: accepted
date: 2026-09-13
---

# ADR-0008: OpenCode Runtime Adapter

## Context

KOS needs one operational runtime before it can ship canonical orchestration and workflow-step skills. The runtime must discover project-local skills, run non-interactively in a reserved task worktree, isolate a workflow-step dialogue in a child session, and return a typed repository-effect result to that same child before accepting its final manifest.

OpenCode 1.18.26 exposes project-local skills, JSON event output, and a foreground `task` tool. A completed task call identifies its child session in a runtime-generated wrapper and event metadata, and another task call can continue that session. An executable probe also established that an idle child can be synchronously continued after its primary result, but a plugin tool deadlocks if it synchronously prompts its own currently executing root session. OpenCode does not make this transport a KOS state or security boundary, and child text remains untrusted model output.

## Decision

OpenCode 1.18.26 is the first and only initially supported runtime version. A later version is supported only after it passes the complete executable adapter contract; an untested semver range is not accepted.

KOS installs skills under `.opencode/skills/<skill-name>/SKILL.md`. An orchestration session runs non-interactively with JSON events and the reserved task worktree as its explicit working directory. It launches `kos-workflow-step` through a foreground task call so the parent waits for each child turn.

The adapter obtains the opaque child session identifier from the runtime-generated completed Task wrapper, not from the nested child-generated text. A process adapter also cross-checks that identifier against event metadata. An OpenCode plugin guard retains that identifier per parent session and rejects a continuation Task call before execution unless its `task_id` is the retained value. The child text must contain exactly one JSON document that validates as either a version 1 effect request or a final result manifest. After an effect request, the orchestrator validates and executes the existing durable effect protocol, then continues the retained child session with the complete version 1 effect result. A child session change, malformed wrapper, mixed prose, invalid JSON, invalid schema, unexpected turn, or identity and digest mismatch fails closed.

The executable contract is tested against the real pinned OpenCode binary in isolated home, configuration, data, cache, and state directories. A deterministic loopback model endpoint drives the tool sequence, so provider credentials, user configuration, network availability, and probabilistic model behavior are not part of compatibility verification.

The production `kos-opencode` process adapter samples the installation runtime configuration once at orchestration start and invokes the primary root session in the explicit worktree. When retrospective is enabled, it preserves the complete primary stream and exit status, waits for that process to finish, and then externally continues the same root session with a second prompt. A schema-valid retrospective delivery is written only to `KOS_RETROSPECTIVE_FD`; absence or failure of that descriptor cannot affect the primary result.

Child retrospective uses a separate explicit plugin tool rather than an idle hook. The plugin derives eligibility only from an initial runtime-observed Task route whose `subagent_type` is exactly `kos-workflow-step`. After the orchestrator has durably handled the child primary result, it calls `child_retrospective` with only the retained `child_session_id`; the call itself is the explicit acknowledgement signal, so model-supplied eligibility and acknowledgement booleans are neither requested nor trusted. The plugin may continue that retained idle child once and constructs the trusted invocation fields itself. Root and child paths generate a new retrospective UUID at their trusted runtime boundary, suppress recursion, keep raw dialogue in the same OpenCode session, and enforce a fixed 30-second budget including provider latency. Transport `no_result` is distinct from the valid retrospective result `no_action`. No more than five sanitized child results are retained in receipt order in current orchestration memory.

Before delivery, the runtime structurally validates the result and deterministically rejects obvious secret or credential forms, environment assignments, private absolute paths, and verbatim dialogue leakage. These checks are deliberately bounded: they backstop the model procedure's instruction to return `no_action` when sanitization is uncertain, but do not claim to infer arbitrary prose semantics or prove that every sensitive fact has been generalized.

## Consequences

- The initial compatibility claim is narrow but reproducible.
- Workflow policy and durable effect handling remain in KOS; OpenCode provides session routing and tool execution only.
- OpenCode child session identifiers remain ephemeral runtime routing data and are not persisted as task, attempt, or artifact identity.
- Runtime parsing must understand the pinned OpenCode task event and wrapper shape while keeping the nested KOS document schema-validated.
- The OpenCode adapter installation needs a plugin guard in addition to skills. Model-generated Task arguments remain untrusted and cannot continue a session without matching the guard's runtime-retained identifier.
- Retrospective capability is part of unconditional OpenCode compatibility even when retrospective is disabled. Bundle or capability digest changes require a newly approved managed installation plan and explicit force authorization.
- Root and child retrospective use different lifecycle adapters because synchronous self-prompting the active root would deadlock.
- Same-session routing limits deliberate dialogue transport, but structural validation is not a general semantic privacy or information-flow guarantee.

## Rejected Alternatives

### Trust a compatible-looking OpenCode version range

Minor runtime changes can alter event, task, permission, or session behavior. Declaring a range without executing the complete contract would make installation compatibility speculative.

### Return an effect request as the final workflow-step result

Starting a new child after the effect would lose the dialogue that produced the request and would let evidence be finalized outside the original workflow-step session.

### Let the workflow-step call KOS or `kos-repository` directly

That bypasses the lease-owning orchestrator, durable effect intent, fencing, allowlist, and reconciliation boundaries.

### Use an external provider in compatibility tests

Credentials, network behavior, cost, and nondeterministic model output would make the adapter contract unsuitable for the required project check.

### Prompt the active root from its plugin tool

The plugin tool would wait on the session that is waiting for the tool to return. The external process adapter issues the root's second prompt only after primary process completion.

### Trigger child retrospective from session idle

Idle does not establish that the parent accepted and durably handled the primary result. An explicit post-handling plugin call with only the retained child identity acts as acknowledgement, preserves ordering, and rejects premature or duplicate invocation.
