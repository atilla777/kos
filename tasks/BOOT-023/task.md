---
title: Immutable Workflow Step Context
task: BOOT-023
created: 2026-09-11
---

# BOOT-023: Immutable Workflow Step Context

## Goal

Implement `step.context` so an active attempt idempotently freezes and receives its complete versioned executable context with a canonical digest and verified workflow members.

## User Outcome

An orchestrator can obtain the exact pinned instruction, templates, artifact requirements, allowed effects, and execution metadata through the KOS CLI. KOS stores that input atomically and binds the eventual result manifest to it through a deterministic digest.

## Context

The draft CLI v1 schemas and command catalog already define `step.context`. Workflow attempts already persist immutable `input_context` and `input_context_digest`, while claim, lease, fencing, repository-scoped idempotency, and RFC 8785 canonical JSON are implemented. The application operation, API route, and CLI binding do not exist. Installation retrospective configuration and durable publication intents are not yet implemented.

## Requirements

- BOOT-023-REQ-001: `step.context` checks repository scope, path/body identity, expected task lock version, active attempt ownership, current workflow status, fencing token, and lease expiry before freezing context.
- BOOT-023-REQ-002: Context members come only from the task's pinned workflow version after complete definition validation and equality of its reconstructed canonical digest with the stored content digest.
- BOOT-023-REQ-003: A status requiring a worktree cannot freeze context until the task-bound reservation is confirmed; a confirmed reservation may have originated under an earlier attempt.
- BOOT-023-REQ-004: The current candidate, when present, is selected from the latest succeeded candidate-producing attempt by fencing token.
- BOOT-023-REQ-005: Installation configuration durably stores `retrospective_enabled` with a default of `false`, and context captures its current value.
- BOOT-023-REQ-006: KOS deterministically constructs the version 1 context and computes `input_context_digest` as SHA-256 over its RFC 8785 canonical JSON with only that digest field omitted.
- BOOT-023-REQ-007: Context and digest are stored atomically on the attempt before the exact stored document is returned and are immutable afterward.
- BOOT-023-REQ-008: Repository-scoped idempotency replays the original response before mutable ownership checks. A later key for the same active attempt returns the already frozen context without rebuilding it.
- BOOT-023-REQ-009: Invalid persisted workflow or frozen-context content is an internal invariant failure and never produces a partial executable context.
- BOOT-023-REQ-010: Until durable publication intent exists, a publication attempt returns `context_unavailable` rather than incomplete publication context.
- BOOT-023-REQ-011: API and CLI use the existing draft version 1 `step.context` request, response, status, and stable error contracts without changing its wire schema.

## Scope

- Minimal durable installation configuration containing `retrospective_enabled`.
- Verified context assembly, canonical digest, and atomic attempt persistence.
- Confirmed-worktree and current-candidate resolution from existing persistence.
- Authenticated REST route, thin controller action, and Ruby CLI binding for `step.context`.
- Service, persistence, request, CLI, contract, idempotency, and concurrency tests.
- Narrow specification and user documentation updates for the implemented command and deferred publication prerequisite.

## Non-Goals

- Publication prepare, adoption, reconciliation, or completion.
- Public runtime-configuration read or update commands.
- Worktree reservation, confirmation, adoption, or release operations.
- Repository effects, runtime skills, or changes to result-manifest completion semantics.
- Adding `execution_mode` to context, a protocol version, command, or stable error code.

## Related Specifications And ADRs

- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [KOS Retrospective](../../docs/specs/retrospective.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-023-DEC-001: Publication context remains unavailable until a separate task implements the durable publication resource required by the protocol.
- BOOT-023-DEC-002: Minimal runtime-configuration persistence is included, but its public API and CLI remain deferred.
- BOOT-023-DEC-003: A confirmed task-bound worktree is sufficient for context capture even when its recorded attempt differs; adoption is required later at the Git-effect boundary.
- BOOT-023-DEC-004: Context arrays use canonical workflow-definition ordering before digest calculation.
- BOOT-023-DEC-005: The existing version 1 schema remains unchanged; execution mode remains orchestration metadata available from the workflow resource.

## Acceptance Criteria

- BOOT-023-AC-001: CLI and API return a context conforming to `workflow.json#/$defs/context`, and the persisted context exactly equals that response.
- BOOT-023-AC-002: The embedded digest, digest column, and independently calculated canonical SHA-256 agree.
- BOOT-023-AC-003: Exact instructions and members come from the validated pinned version in deterministic order.
- BOOT-023-AC-004: Required confirmed worktree, current candidate, and persisted retrospective setting are represented correctly.
- BOOT-023-AC-005: Same-key replay works after lease expiry, another key returns the frozen context while ownership is valid, and concurrent capture cannot persist divergent contexts.
- BOOT-023-AC-006: Stale lock, expired lease, stale fencing, cross-repository access, unavailable worktree, unavailable publication intent, and invalid persisted workflow fail without partial state.
- BOOT-023-AC-007: Focused checks, the full project check, RuboCop, and diff validation pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-023 active externally.
2. Add minimal runtime-configuration persistence with a durable false default.
3. Implement verified context assembly, canonical digest calculation, frozen-context validation, and atomic persistence using existing ownership and idempotency infrastructure.
4. Add Rails routing and controller transport plus the Ruby CLI command binding.
5. Add service, persistence, request, CLI, contract, idempotency, and synchronized concurrency coverage.
6. Clarify the deferred publication prerequisite in the behavioral specification and document the CLI command.
7. Run focused checks, the full project quality gate, RuboCop, and diff validation.
8. Review the completed diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused context service, API request, CLI transport, protocol, migration, idempotency, and concurrency specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused service, runtime-config model, API, CLI transport, protocol, idempotency, cross-attempt worktree, candidate-generation, frozen-integrity, and synchronized multi-process concurrency specs passed.
- `mise run check`: passed with 391 examples, 0 failures, 122 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found a pre-existing development-schema trigger drift exposed by schema dumping; the generated structure was restored to the migration-defined guard and the existing migration test was pinned to its explicit target version. Follow-up review confirmed the migration/schema issue was resolved.

## Implementation Result

- Added `WorkflowSteps::CaptureContext` to validate active ownership and the complete pinned workflow definition, resolve confirmed worktree and latest candidate context, compute the RFC 8785 digest, and atomically freeze exact schema-valid input.
- Added durable singleton runtime configuration with `retrospective_enabled: false` and preserved frozen values across later configuration changes.
- Added authenticated REST and Ruby CLI bindings for `step.context`, including repository-scoped idempotent replay after lease expiry and unsupported-version recognition.
- Reused one candidate-selection query for completion and context capture, and covered latest-generation and prior-attempt worktree behavior.
- Documented the implemented command and explicit `context_unavailable` publication boundary until durable publication intent is implemented.

## Risks

- BOOT-023-RISK-001: Reconstructing and validating up to 4 MiB of workflow content must avoid unnecessary SQLite write-lock duration and N+1 queries.
- BOOT-023-RISK-002: Array order is digest-significant even though RFC 8785 sorts object keys, so members must be normalized before hashing.
- BOOT-023-RISK-003: A corrupt context must be rejected before the database immutability trigger can permanently freeze it.
- BOOT-023-RISK-004: Publication execution remains blocked until its durable intent protocol is implemented.

The first three risks are covered by validation and automated tests. Publication context remains intentionally unavailable and is the only known unimplemented behavior within the broader protocol contract.
