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

The first operational MVP supports OpenCode 1.18.26 and installs skills under `.opencode/skills/`; the Claude-compatible target is deferred. No other OpenCode version is compatible until it passes the complete executable adapter contract. Before installation, KOS validates skill discovery, non-interactive JSON invocation, foreground subagent launch, context/result transport, and working-directory semantics. Missing required capability or a different runtime version is an installation error.

OpenCode orchestration is invoked through the production `kos-opencode` process adapter, non-interactively with JSON events and the reserved task worktree as its explicit working directory. The adapter verifies OpenCode 1.18.26 and samples `kos runtime-config get` once before starting the orchestration. A foreground Task tool call launches each `kos-workflow-step` child and blocks until its current turn ends. The adapter obtains the opaque child session identifier from the runtime-generated completed Task wrapper, cross-checks it against event metadata when consuming process events, and retains it only as runtime routing state. An installed OpenCode plugin guard retains the same identifier per parent session and rejects any continuation Task call before execution when its model-generated `task_id` differs. The identifier never comes from the nested child-generated JSON. Parent and child sessions use the same task-worktree working directory.

Child text contains exactly one JSON document and no prose. It validates as either `workflow.json#/$defs/effect_request` or `workflow.json#/$defs/result_manifest`. The adapter combines the validated turn with the child session identifier as defined by `schemas/runtime/v1/opencode.json`. After an effect request, the orchestrator completes the durable effect protocol and continues the exact retained child session with a schema-valid effect result. The resumed child then returns another effect request or its final manifest. A malformed runtime wrapper, mixed output, invalid schema, changed child session, unexpected turn, or identity, digest, and operation mismatch fails closed.

Workflow orchestration and subagent restrictions are defined once in [Workflow Execution](workflow-execution.md), retrospective lifecycle and privacy in [KOS Retrospective](retrospective.md), and Git mutation ownership in [Repository Isolation](repository-isolation.md).

## CLI Protocol

All CLI commands are non-interactive and support `--json`. The CLI calls the versioned Rails JSON REST API under `/api/v1`; agents and skills never call that API directly. Structured input, API payloads, and stdout use versioned schemas. Stderr is diagnostics only. [CLI Protocol Version 1](cli-protocol.md) defines the exact command and transport contract.

The protocol exposes stable machine-readable error categories including validation, authentication, authorization, conflicts, lost leases, missing resources, transient failures, and internal failures. Mutating commands carry an idempotency key; existing-task mutations carry expected lock version, and operations owned by an active attempt carry its fencing token. Only transient errors receive bounded retry with jitter. After validation, conflict, or lost-lease errors, the agent rereads state and does not blindly retry the business operation.

The minimum capability includes catalog reads, task creation, attempt claim/renew/reconcile, idempotent finalization of a complete attempt-bound step context, worktree reservation/confirmation, artifact registration, and atomic step completion. Step completion verifies the stored input-context digest, lease, expected version, dependencies, and artifact contract, records artifacts, and advances workflow status in one transaction. Runtime adapters never access SQLite directly.

The runtime adapter must support synchronous typed repository-effect request/results within one workflow-step session so the generic executor can finalize evidence against observed Git state without invoking Git itself. OpenCode implements this round trip by resuming the retained foreground Task child session; the orchestrator never accepts a child session identifier from nested child-generated content.

The local `kos-repository` executable has a separate closed JSON adapter contract under `schemas/repository/v1/`. It performs technical repository operations but does not call the state API or make workflow decisions. Runtime skills validate current KOS state and construct those adapter requests; installation and runtime-specific invocation remain governed by the target adapter contract.

When the sampled installation setting enables retrospective, the runtime adapter invokes it only after graceful primary completion and explicit acknowledgement. The plugin derives child eligibility from the runtime-observed initial Task route with `subagent_type: "kos-workflow-step"`, never from model arguments or child output. After durable primary handling, the orchestrator calls `child_retrospective` with only `child_session_id`; the call itself is the acknowledgement signal, and the plugin constructs the trusted eligibility and acknowledgement fields before synchronously continuing the retained idle child. It is never an automatic idle hook. A root retrospective is a second external `opencode --pure run --session` prompt issued by `kos-opencode` after the primary process exits because a plugin cannot synchronously prompt its currently executing root session. Before primary execution, the launcher accepts zero or exactly one root `opencode.json` or `opencode.jsonc`, snapshots its bytes when present, and revalidates the exact ten-file managed inventory, canonical order and source paths, capability and source-bundle digests, repository worktree ownership, every installed digest, and hardcoded release digests for the retrospective profile, skill, and plugin. Staged pre-manifest capability verification is accepted only when all ten installed bytes match the hardcoded release bundle. Any post-primary drift, configuration ambiguity, custom `OPENCODE_CONFIG`, or bounded primary-capture exhaustion suppresses the second process. The second process starts with an empty inherited environment, a launcher-controlled empty `XDG_CONFIG_HOME`, and an explicit OS, XDG-data, OpenCode-runtime, and selected-known-provider allowlist. `OPENCODE_CONFIG`, `OPENCODE_CONFIG_CONTENT`, and `OPENCODE_CONFIG_DIR` are not retained, so custom overrides and unrelated KOS, Git, SSH, cloud, and provider credentials are absent while required session data remains available. Both paths enforce a fixed 30-second budget including provider latency, recursion suppression, same-session dialogue access, primary byte and status preservation, and closed separate delivery. Abrupt process loss may skip retrospective but cannot weaken workflow recovery.

`kos-opencode` reserves primary stdout and stderr for the primary OpenCode process. If `KOS_RETROSPECTIVE_FD` names a writable regular-file descriptor of at least 3, the adapter writes at most one newline-delimited root retrospective delivery there. A valid delivery distinguishes `outcome: "result"`, whose nested skill result may be `no_action`, from `outcome: "no_result"` caused by timeout, cancellation, provider failure, malformed output, transport failure, duplication, or the five-result limit. The parent retains at most five sanitized child results in receipt order and only in current orchestration memory. Before either delivery, runtime validation deterministically rejects schema violations and obvious secret, environment-assignment, private-path, or verbatim-dialogue leakage. This structural backstop does not claim semantic detection of every sensitive disclosure; uncertain model sanitization remains fail-closed as `no_action`.

Installation planning, copy manifests, drift handling, and staged capability verification are defined by [Initialization](initialization.md) and [ADR-0009](../decisions/0009-runtime-bundle-installation.md). The installed OpenCode bundle contains the six canonical skills, the session guard, and restrictive orchestrator, workflow-step, and retrospective agent profiles as derived ordinary copies rather than runtime links to the canonical source checkout. Because the retrospective profile has no skill-tool authority, it embeds the complete procedure and closed result instructions. Complete retrospective capability and that embedded procedure are verified for every installation even when the setting is disabled. A changed bundle or capability digest is a managed upgrade requiring a newly approved plan and explicit force authorization.

The OpenCode adapter transport uses `schemas/runtime/v1/opencode.json`. The closed sanitized retrospective result uses `schemas/runtime/v1/retrospective.json`. Both are runtime transport rather than CLI/API persistence documents.
