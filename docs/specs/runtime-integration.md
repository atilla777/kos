---
title: KOS Runtime Integration
status: active
---

# KOS Runtime Integration

## Canonical Skills

The KOS repository's `skills/` directory is the sole canonical source for shipped skills. It has no `index.md`; each skill has its own directory and a `SKILL.md` with required YAML frontmatter.

The intended skill set and responsibilities are:

| Skill | Responsibility |
| --- | --- |
| `kos-cli` | Low-level safe use of the Ruby CLI for tasks, statuses, and artifacts |
| `kos-workflow-step` | Generic subagent executor for pinned Markdown step instructions |
| `kos-orchestrate` | Main-session workflow coordination |
| `kos-repository` | Technical Git, worktree, and remote operations without workflow decisions |
| `kos-retrospective` | Private end-of-session analysis and sanitized improvement proposals |
| `kos-initialize` | Repository registration and runtime-specific skill installation |

Planning, development, review, and publication behavior belongs to database-backed workflow instructions rather than separate runtime skills. The quick-fix MVP includes the generic executor, orchestrator, repository adapter, CLI guidance, initialization, and opt-in retrospective needed for its vertical slice. Feature, initiative, and a second runtime remain deferred as stated in [Product Boundary](product-boundary.md).

## Runtime Copies And Adapter Contract

Runtime copies are materialized installations, never canonical sources. Supported target layouts are:

```text
.opencode/skills/<skill-name>/SKILL.md
.claude/skills/<skill-name>/SKILL.md
```

The first operational MVP supports one selected target; the second is deferred. Before installing a target, KOS validates its adapter contract for skill discovery, non-interactive invocation, subagent launch, context/result transport, and working-directory semantics. Missing required capability is an installation error.

Workflow orchestration and subagent restrictions are defined once in [Workflow Execution](workflow-execution.md), retrospective lifecycle and privacy in [KOS Retrospective](retrospective.md), and Git mutation ownership in [Repository Isolation](repository-isolation.md).

## CLI Protocol

All CLI commands are non-interactive and support `--json`. The CLI calls the versioned Rails JSON REST API under `/api/v1`; agents and skills never call that API directly. Structured input, API payloads, and stdout use versioned schemas. Stderr is diagnostics only. [CLI Protocol Version 1](cli-protocol.md) defines the exact command and transport contract.

The protocol exposes stable machine-readable error categories including validation, authentication, authorization, conflicts, lost leases, missing resources, transient failures, and internal failures. Mutating commands carry an idempotency key; existing-task mutations carry expected lock version, and operations owned by an active attempt carry its fencing token. Only transient errors receive bounded retry with jitter. After validation, conflict, or lost-lease errors, the agent rereads state and does not blindly retry the business operation.

The minimum capability includes catalog reads, task creation, attempt claim/renew/reconcile, idempotent finalization of a complete attempt-bound step context, worktree reservation/confirmation, artifact registration, and atomic step completion. Step completion verifies the stored input-context digest, lease, expected version, dependencies, and artifact contract, records artifacts, and advances workflow status in one transaction. Runtime adapters never access SQLite directly.

The runtime adapter must support synchronous typed repository-effect request/results within one workflow-step session so the generic executor can finalize evidence against observed Git state without invoking Git itself.

The local `kos-repository` executable has a separate closed JSON adapter contract under `schemas/repository/v1/`. It performs technical repository operations but does not call the state API or make workflow decisions. Runtime skills validate current KOS state and construct those adapter requests; installation and runtime-specific invocation remain governed by the target adapter contract.

When retrospective is enabled installation-wide, the runtime adapter must support graceful end invocation, a bounded timeout, recursion suppression, private self-dialogue access, preservation of the primary result, and a second sanitized result delivery after the primary result is acknowledged. Lack of a graceful end hook or abrupt process loss may skip retrospective but cannot weaken workflow recovery.

Detailed runtime adapter behavior and installation UX belong to later runtime-integration work.

The closed sanitized retrospective result uses `schemas/runtime/v1/retrospective.json`. It is runtime transport, not a CLI/API persistence document, and is governed by [KOS Retrospective](retrospective.md).
