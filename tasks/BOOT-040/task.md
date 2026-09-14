---
title: OpenCode Retrospective Lifecycle Transport
task: BOOT-040
created: 2026-09-14
---

# BOOT-040: OpenCode Retrospective Lifecycle Transport

## Goal

Implement the installation-wide opt-in retrospective lifecycle for OpenCode 1.18.26 while preserving the acknowledged primary result and returning a separate bounded sanitized result.

## User Outcome

A user can enable retrospective through the KOS CLI. New KOS OpenCode sessions then run private best-effort post-processing after graceful primary completion, without changing workflow state or the primary result; disabled sessions do not run retrospective.

## Context

KOS already persists a disabled-by-default installation setting, freezes that setting in workflow-step context, installs the canonical retrospective skill, and validates its closed result schema. The public runtime-configuration API and CLI, invocation transport, production lifecycle adapter, restrictive retrospective profile, timeout enforcement, second-result delivery, and executable OpenCode verification are not implemented. An executable OpenCode 1.18.26 probe established that an idle Task child can be synchronously continued after the parent receives its primary result, while synchronously prompting the currently running root session from its own plugin tool deadlocks. Root retrospective therefore requires an external process adapter to issue the second prompt after the primary process completes.

## Requirements

- BOOT-040-REQ-001: Implement authenticated global `runtime_config.get` and idempotent optimistic-locking `runtime_config.update` through the existing REST and Ruby CLI contracts; retrospective remains disabled by default.
- BOOT-040-REQ-002: Add closed version 1 invocation and OpenCode delivery contracts for runtime-supplied retrospective UUID, source, enablement, eligibility, recursion suppression, primary-result acknowledgement, timeout, and separate result or no-result outcome.
- BOOT-040-REQ-003: Add a production `kos-opencode` process adapter that samples runtime configuration when a new orchestration starts, invokes OpenCode 1.18.26 non-interactively in the explicit worktree, preserves the completed primary output, and only then issues a retrospective prompt in the same root session.
- BOOT-040-REQ-004: Extend the installed OpenCode plugin to retain child routing and synchronously continue only the retained idle workflow-step child after the parent has received and durably handled its primary result.
- BOOT-040-REQ-005: Generate retrospective UUIDs at the trusted runtime boundary, never from model output or an OpenCode routing identifier.
- BOOT-040-REQ-006: Enforce a fixed 30-second retrospective budget including provider latency. Failure, malformed output, cancellation, or timeout returns no retrospective result and cannot alter, replace, downgrade, or retry the primary result.
- BOOT-040-REQ-007: Run retrospective under a dedicated profile with no tools or mutation, filesystem, Git, network, state, or subagent authority; analyze only the same OpenCode session dialogue and never serialize raw dialogue into KOS transport.
- BOOT-040-REQ-008: Suppress disabled, ineligible, premature, duplicate, and recursive invocation. Retrospective itself never triggers another retrospective.
- BOOT-040-REQ-009: Keep at most five sanitized child results in current orchestration memory, in receipt order, without persistence or durable deduplication, and expose them to the orchestrator for its final report.
- BOOT-040-REQ-010: Require retrospective capability during every OpenCode installation verification even when retrospective is disabled. Existing installations require an explicitly approved managed upgrade when bundle or capability digests change.
- BOOT-040-REQ-011: Update canonical skills, specifications, architecture decisions, installation contracts, and user documentation without changing workflow semantics or adding automatic proposal persistence or task creation.
- BOOT-040-REQ-012: Add deterministic schema, API, CLI, adapter, plugin, timeout, privacy, installation, and real pinned-runtime coverage, including byte-preservation of primary results on every retrospective outcome.

## Scope

- Runtime-configuration API, serializer, application operation, routes, CLI binding, and tests.
- Retrospective invocation/result and OpenCode transport schemas.
- `kos-opencode`, OpenCode plugin lifecycle transport, Ruby transport validation, and restrictive retrospective profile.
- Deterministic provider and executable OpenCode capability verification.
- Canonical skill, installer bundle, specification, ADR, and user documentation updates.

## Non-Goals

- Proposal persistence, deduplication, automatic task creation, approval, scheduling, or execution.
- Retrospective recovery after abrupt runtime or process loss.
- Repository-specific settings or non-repository task scope.
- Claude Code, another runtime, or another OpenCode version.
- A general operating-system sandbox against same-user processes.
- Unrelated workflow, publication, worktree, repository-snapshot, or lease-keeper gaps.

## Related Specifications And ADRs

- [KOS Retrospective](../../docs/specs/retrospective.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Initialization](../../docs/specs/initialization.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)
- [ADR-0009](../../docs/decisions/0009-runtime-bundle-installation.md)

## Task-Local Decisions

- BOOT-040-DEC-001: Root retrospective is owned by an external `kos-opencode` adapter. A plugin never synchronously prompts its currently executing root session.
- BOOT-040-DEC-002: A child retrospective is an explicit post-acknowledgement plugin operation against the retained idle child session, not an automatic `session.idle` hook.
- BOOT-040-DEC-003: Runtime enablement is sampled once when an orchestration session starts. Workflow-step context retains its existing frozen setting; configuration changes affect new sessions.
- BOOT-040-DEC-004: The fixed version 1 retrospective timeout is 30 seconds. Timeout or transport failure is distinct from a schema-valid `no_action` result.
- BOOT-040-DEC-005: Complete retrospective support is part of unconditional OpenCode compatibility. The installed bundle gains one dedicated restrictive agent profile.
- BOOT-040-DEC-006: Child retrospective accumulation is bounded to five in-memory results in receipt order and ends with the orchestration process.

## Acceptance Criteria

- BOOT-040-AC-001: `kos runtime-config get/update` satisfy the existing closed resource, authentication, stable error, optimistic locking, global idempotency, replay, and concurrency contracts.
- BOOT-040-AC-002: Disabled root and child sessions produce no retrospective model turn or result.
- BOOT-040-AC-003: Enabled root and child sessions deliver a separate schema-valid result only after the primary result is completed and acknowledged.
- BOOT-040-AC-004: Primary output remains byte-identical after retrospective success, `no_action`, malformed output, provider failure, cancellation, and timeout.
- BOOT-040-AC-005: Retrospective sees only its source session dialogue, receives no tools, and cannot recurse, launch a task, or invoke state, filesystem, Git, network, or repository effects.
- BOOT-040-AC-006: Missing, malformed, premature, duplicate, mismatched, or recursive lifecycle input fails closed without a retrospective result.
- BOOT-040-AC-007: Runtime-generated UUID, source, routing identity, enablement sample, acknowledgement, timeout, and result are closed and consistently bound.
- BOOT-040-AC-008: The staged and independently copied bundle passes the expanded executable contract against the real pinned OpenCode 1.18.26 binary.
- BOOT-040-AC-009: Existing workflow and repository transports remain compatible, and installer drift/update semantics reflect the new bundle and capability digests.
- BOOT-040-AC-010: Focused suites, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-040 active externally.
2. Implement runtime-configuration API, application behavior, serialization, CLI binding, and focused concurrency and contract coverage.
3. Add closed retrospective invocation and OpenCode delivery schemas and extend the Ruby transport state machine.
4. Implement `kos-opencode`, child plugin delivery, timeout and primary-preservation behavior, and the restrictive retrospective profile.
5. Update canonical skills and the managed installer bundle.
6. Extend the deterministic provider and real OpenCode executable compatibility contract across enabled, disabled, recursive, malformed, and timeout cases.
7. Update applicable specifications, ADRs, and user documentation.
8. Run focused suites, `mise run check`, and `git diff --check`; review the complete diff.
9. Record verification and implementation results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused runtime-config request, CLI, schema, transport, plugin, skill, initializer, and real OpenCode adapter specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-14:

- Focused runtime-configuration model, service, request, process-concurrency, CLI, and contract suites passed.
- Focused launcher, transport, plugin, canonical-skill, capability-verifier, initializer, hostile-configuration, manifest-integrity, truncation, cancellation, and real OpenCode 1.18.26 suites passed.
- Independent correctness and security reviews verified fixes for primary-result status preservation, runtime-supplied lifecycle gates, complete manifest validation, dialogue-bound sanitation, process and child timeout handling, environment isolation, runtime bundle integrity, hostile configuration overrides, duplicate and concurrent child routing, and installation capability truthfulness. No high- or medium-severity findings remained.
- Final `mise run check` passed with 723 examples and no failures, 189 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.

## Implementation Result

- Implemented authenticated `runtime_config.get` and globally idempotent optimistic-locking `runtime_config.update` through the version 1 REST API and Ruby CLI.
- Added closed retrospective invocation, no-result, and OpenCode delivery contracts plus one-shot transport validation bound to the retained workflow-step session.
- Added `kos-opencode`, which samples enablement once, preserves primary stdout, stderr, and exit status, and performs a separately bounded root retrospective only after graceful primary completion.
- Extended the OpenCode session guard with exact workflow-step eligibility, single-child routing, complete result-manifest validation, runtime-generated lifecycle identity, bounded same-session continuation, recursion and duplicate suppression, dialogue-bound sanitation, and in-memory result limits.
- Added a deny-all retrospective agent with the complete executable analysis and output procedure. The root retrospective runs through an isolated `--pure` process with exact managed-bundle integrity checks and an explicit environment allowlist.
- Expanded installation to the ten-file runtime bundle, required `kos-opencode`, preserved explicit upgrades from the previous nine-file manifest, and made retrospective root, child, disabled, recursive, failure, timeout, isolation, and primary-preservation behavior part of the executable OpenCode 1.18.26 capability contract.
- Updated canonical skills, user documentation, behavioral specifications, and ADRs to describe the operational two-phase transport without adding proposal persistence or workflow semantics.

## Risks

- OpenCode permissions restrict model-visible tools but are not an operating-system sandbox or a boundary against a hostile same-user process.
- Child acknowledgement is enforced by the adapter protocol but is not transactional with Rails state handling.
- Aborting a provider request may leave its remote completion ambiguous; the adapter discards late output and never feeds it into the primary result.
- Existing installed bundles become managed updates and require a new approved plan and explicit force authorization.
- Runtime leakage checks intentionally reject oversized dialogue or output rather than analyze an incomplete source.
- Root retrospective is skipped when project runtime configuration or managed KOS runtime bytes change during primary execution.
