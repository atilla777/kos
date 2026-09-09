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
| `kos-okf` | Creation, update, and validation of OKF documentation |
| `kos-requirements` | Capability for eliciting and refining requirements |
| `kos-development` | Capability for implementation, tests, linters, and local checks |
| `kos-review` | Capability for reviewing requirements, diffs, architecture, and test results |
| `kos-publish` | Capability for publishing a reviewed commit |
| `kos-workflow-step` | Common subagent executor for pinned Markdown step instructions |
| `kos-orchestrate` | Main-session workflow coordination |
| `kos-repository` | Technical Git, worktree, and remote operations without workflow decisions |
| `kos-retrospective` | Agent-dialogue analysis and follow-up improvement proposals |
| `kos-initialize` | Target-project templates and runtime-specific skill installation |

The quick-fix MVP includes only skills needed for its vertical slice. Feature, initiative, second-runtime, and retrospective capabilities remain deferred as stated in [Product Boundary](product-boundary.md).

## Runtime Copies And Adapter Contract

Runtime copies are materialized installations, never canonical sources. Supported target layouts are:

```text
.opencode/skills/<skill-name>/SKILL.md
.claude/skills/<skill-name>/SKILL.md
```

The first operational MVP supports one selected target; the second is deferred. Before installing a target, KOS validates its adapter contract for skill discovery, non-interactive invocation, subagent launch, context/result transport, and working-directory semantics. Missing required capability is an installation error.

Workflow orchestration and subagent restrictions are defined once in [Workflow Execution](workflow-execution.md), and Git mutation ownership is defined in [Repository Isolation](repository-isolation.md).

## CLI Protocol

All CLI commands are non-interactive and support `--json`. The CLI calls the versioned Rails JSON REST API under `/api/v1`; agents and skills never call that API directly. Structured input, API payloads, and stdout use versioned schemas. Stderr is diagnostics only. [CLI Protocol Version 1](cli-protocol.md) defines the exact command and transport contract.

The protocol exposes stable machine-readable error categories including validation, authentication, authorization, conflicts, lost leases, missing resources, transient failures, and internal failures. Mutating commands carry an idempotency key; existing-task mutations carry expected lock version, and operations owned by an active attempt carry its fencing token. Only transient errors receive bounded retry with jitter. After validation, conflict, or lost-lease errors, the agent rereads state and does not blindly retry the business operation.

The minimum capability includes task creation, attempt claim/renew/reconcile, idempotent finalization of a complete attempt-bound step context, worktree reservation/confirmation, artifact registration, and atomic step completion. Step completion verifies the stored input-context digest, lease, expected version, dependencies, and artifact contract, records artifacts, and advances workflow status in one transaction. Runtime adapters never require direct access to KOS snapshot storage.

Detailed runtime adapter behavior and installation UX belong to later runtime-integration work.
