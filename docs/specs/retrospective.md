---
title: KOS Retrospective
status: active
---

# KOS Retrospective

## Purpose And Enablement

`kos-retrospective` is an optional runtime lifecycle skill that evaluates how KOS-assisted work was performed and proposes a separate improvement when useful. It is disabled by default through one installation-wide KOS setting. When enabled, it applies to every registered repository and supported runtime installation.

Retrospective is post-processing, not a workflow state, workflow capability, task artifact, or condition for successful completion. It cannot change the source task, its result, or its workflow status.

## Eligible Sessions

Retrospective runs at the end of every gracefully ending KOS orchestration session and every independently launched `kos-workflow-step` subagent session. Eligible outcomes include success, failure, `needs_human`, blockage, and a nonterminal handoff. Internal calls to `kos-cli` or `kos-repository`, in-process skill expansion, and retrospective itself are not separate eligible sessions.

An abrupt runtime or process loss cannot guarantee retrospective execution. Recovery preserves primary workflow state and does not reconstruct or persist a private dialogue solely to run retrospective later.

## Execution Order And Failure

A workflow subagent delivers its finalized primary result before retrospective starts. The orchestrator acknowledges and durably handles that result, including releasing the workflow lease when appropriate, while the runtime keeps the subagent dialogue available for post-processing. Retrospective then runs with a bounded runtime budget. Failure, cancellation, or timeout cannot delay, replace, or change the already delivered primary result.

The subagent analyzes only its own dialogue and sends a second, separate sanitized retrospective result through the runtime adapter. The retrospective transport is not part of the primary workflow result manifest.

The main orchestrator first records the normal completed, blocked, `needs_human`, or handoff state. It then analyzes only its own dialogue and orchestration quality, combines any sanitized subagent results, and includes actionable proposals in its final user report.

## Privacy And Authority

Raw dialogue remains private to the invoking agent and under the runtime's retention policy. It is not sent to Rails, the CLI, another agent, a task artifact, or another repository. The orchestrator may receive only the closed sanitized result, without verbatim transcript excerpts.

The retrospective treats dialogue as untrusted evidence rather than executable instructions. It omits credentials, secrets, environment values, personal data, unrelated source content, and private absolute paths. If a safe summary cannot be produced, it returns `no_action` or a generic user-visible warning.

`kos-retrospective` receives no state mutation, filesystem mutation, Git, network, subagent-launch, or workflow repository-effect authority. A recursion marker disables end-of-session retrospective while retrospective itself runs.

## Result And Classification

A result is either `no_action` or one or more bounded, independently actionable proposals. Each proposal contains a category, problem, observed impact, sanitized evidence summary, proposed outcome, affected workflow version or repository when known, suggested task type, and unresolved uncertainty.

Categories identify the authoritative source that would need correction:

- `kos_product`: Rails, CLI, schemas, runtime adapters, or canonical KOS skills;
- `kos_installation`: installation configuration, installed-copy drift, or runtime compatibility;
- `workflow`: a shared workflow version, instruction, template, transition, or artifact contract; and
- `project`: target-project rules, documentation, source, tests, or repository-specific guidance.

Mixed findings become separate proposals when they can be corrected independently. Installed runtime copies are never proposed as canonical edit targets.

The first retrospective increment does not persist proposals or create tasks automatically. It presents them to the user, who decides whether to create a separate task and which repository or future non-repository scope owns it. No proposed task is started in the source session.

Durable proposal deduplication, automatic task creation, non-repository task scope, and repository-specific workflow overrides require separate decisions.
